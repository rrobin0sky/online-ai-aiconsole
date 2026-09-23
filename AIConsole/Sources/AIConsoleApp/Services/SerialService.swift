import Foundation
import Darwin

public final class SerialService: @unchecked Sendable {
    private var fileDescriptor: Int32 = -1
    private let readQueue = DispatchQueue(label: "com.aiconsole.serial.read", qos: .userInitiated)
    private var readSource: DispatchSourceRead?
    
    public var onDataReceived: ((Data) -> Void)?
    public var onError: ((String) -> Void)?
    
    public init() {}
    
    public static func availablePorts() -> [String] {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(atPath: "/dev") else { return [] }
        return items
            .filter { $0.hasPrefix("cu.") }
            .map { "/dev/\($0)" }
            .sorted()
    }
    
    public func connect(path: String, baudRate: Int) -> Bool {
        disconnect()
        
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            onError?("无法打开串口设备: \(path) (errno: \(errno))")
            return false
        }
        
        var options = termios()
        tcgetattr(fd, &options)
        
        // Convert baud rate
        let speed = getBaudRateConstant(baudRate)
        cfsetispeed(&options, speed)
        cfsetospeed(&options, speed)
        
        // 8N1 raw mode
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(PARENB)
        options.c_cflag &= ~tcflag_t(CSTOPB)
        options.c_cflag &= ~tcflag_t(CSIZE)
        options.c_cflag |= tcflag_t(CS8)
        options.c_lflag &= ~tcflag_t(ICANON | ECHO | ECHOE | ISIG)
        options.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        options.c_oflag &= ~tcflag_t(OPOST)
        
        tcsetattr(fd, TCSANOW, &options)
        
        self.fileDescriptor = fd
        startEventDrivenReading(fd: fd)
        return true
    }
    
    public func write(data: Data) {
        guard fileDescriptor >= 0 else { return }
        data.withUnsafeBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                _ = Darwin.write(fileDescriptor, baseAddress, buffer.count)
            }
        }
    }
    
    public func disconnect() {
        if let source = readSource {
            source.cancel()
            readSource = nil
        } else if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }
    
    /// Kernel event-driven I/O using DispatchSource (0% idle CPU and zero battery drain)
    private func startEventDrivenReading(fd: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = Darwin.read(fd, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                DispatchQueue.main.async {
                    self.onDataReceived?(data)
                }
            }
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        self.readSource = source
        source.resume()
    }
    
    private func getBaudRateConstant(_ rate: Int) -> speed_t {
        switch rate {
        case 9600: return speed_t(B9600)
        case 19200: return speed_t(B19200)
        case 38400: return speed_t(B38400)
        case 57600: return speed_t(B57600)
        case 115200: return speed_t(B115200)
        case 230400: return speed_t(B230400)
        default: return speed_t(B115200)
        }
    }
    
    deinit {
        disconnect()
    }
}
