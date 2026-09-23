import Foundation
import Network

public final class TelnetService: @unchecked Sendable {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.aiconsole.telnet", qos: .userInitiated)
    
    public var onDataReceived: ((Data) -> Void)?
    public var onStateChanged: ((NWConnection.State) -> Void)?
    
    public init() {}
    
    public func connect(host: String, port: Int) {
        disconnect()
        
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return }
        
        let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.connection = conn
        
        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.onStateChanged?(state)
            }
            if case .ready = state {
                self?.receiveData()
            }
        }
        
        conn.start(queue: queue)
    }
    
    public func send(data: Data) {
        connection?.send(content: data, completion: .contentProcessed({ _ in }))
    }
    
    public func disconnect() {
        connection?.cancel()
        connection = nil
    }
    
    private func receiveData() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, isComplete, error in
            if let data = content, !data.isEmpty {
                // Filter out telnet IAC negotiation bytes if necessary or pass through
                DispatchQueue.main.async {
                    self?.onDataReceived?(data)
                }
            }
            if isComplete || error != nil {
                self?.disconnect()
            } else {
                self?.receiveData()
            }
        }
    }
}
