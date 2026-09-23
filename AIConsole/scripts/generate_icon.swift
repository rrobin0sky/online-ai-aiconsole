import AppKit
import CoreGraphics

func createIcon() -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    // Clear
    ctx.clear(CGRect(origin: .zero, size: size))
    
    // 1. App Icon Rounded Squircle Base (Apple HIG: 824x824 inside 1024x1024)
    let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let cornerRadius: CGFloat = 185.0
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    // Outer Soft Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 40, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.addPath(squirclePath)
    ctx.setFillColor(CGColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()
    
    // Clip to Squircle for internal rendering
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    
    // Background Dark Cyber Metallic Gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(hex: "#1F2335").cgColor,
        NSColor(hex: "#13141F").cgColor,
        NSColor(hex: "#0B0C14").cgColor
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.5, 1.0]
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }
    
    // Subtle background glowing orb in center
    let glowColors = [
        NSColor(hex: "#00E5FF").withAlphaComponent(0.18).cgColor,
        NSColor(hex: "#BD93F9").withAlphaComponent(0.10).cgColor,
        NSColor(hex: "#000000").withAlphaComponent(0.0).cgColor
    ] as CFArray
    if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.5, 1.0]) {
        ctx.drawRadialGradient(glowGradient, startCenter: CGPoint(x: 512, y: 512), startRadius: 10, endCenter: CGPoint(x: 512, y: 512), endRadius: 380, options: [])
    }
    
    // Top inner rim light
    ctx.saveGState()
    ctx.setLineWidth(2.5)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
    ctx.addPath(squirclePath)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 2. Draw Terminal Prompt Chevron `>` with Neon Cyan to Magenta Gradient
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 28, color: NSColor(hex: "#00E5FF").withAlphaComponent(0.65).cgColor)
    
    let chevronPath = CGMutablePath()
    chevronPath.move(to: CGPoint(x: 290, y: 650))
    chevronPath.addLine(to: CGPoint(x: 430, y: 512))
    chevronPath.addLine(to: CGPoint(x: 290, y: 374))
    
    ctx.addPath(chevronPath)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(56)
    
    // Stroke chevron with gradient
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    
    let promptColors = [
        NSColor(hex: "#00F0FF").cgColor,
        NSColor(hex: "#7000FF").cgColor,
        NSColor(hex: "#FF007A").cgColor
    ] as CFArray
    if let promptGradient = CGGradient(colorsSpace: colorSpace, colors: promptColors, locations: [0.0, 0.6, 1.0]) {
        ctx.drawLinearGradient(promptGradient, start: CGPoint(x: 250, y: 680), end: CGPoint(x: 480, y: 350), options: [])
    }
    ctx.restoreGState()
    
    // 3. Draw Terminal Cursor `_`
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 24, color: NSColor(hex: "#00F0FF").withAlphaComponent(0.7).cgColor)
    let cursorRect = CGRect(x: 485, y: 346, width: 140, height: 56)
    let cursorPath = CGPath(roundedRect: cursorRect, cornerWidth: 28, cornerHeight: 28, transform: nil)
    ctx.addPath(cursorPath)
    ctx.setFillColor(NSColor(hex: "#00F0FF").cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 4. Draw AI Magical Sparkles (Top Right)
    func drawSparkle(center: CGPoint, radius: CGFloat, colorHex: String) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 22, color: NSColor(hex: colorHex).withAlphaComponent(0.85).cgColor)
        
        let path = CGMutablePath()
        let r = radius
        let innerR = radius * 0.22
        
        path.move(to: CGPoint(x: center.x, y: center.y + r))
        path.addQuadCurve(to: CGPoint(x: center.x + innerR, y: center.y), control: CGPoint(x: center.x, y: center.y))
        path.addQuadCurve(to: CGPoint(x: center.x + r, y: center.y), control: CGPoint(x: center.x, y: center.y))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - innerR), control: CGPoint(x: center.x, y: center.y))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - r), control: CGPoint(x: center.x, y: center.y))
        path.addQuadCurve(to: CGPoint(x: center.x - innerR, y: center.y), control: CGPoint(x: center.x, y: center.y))
        path.addQuadCurve(to: CGPoint(x: center.x - r, y: center.y), control: CGPoint(x: center.x, y: center.y))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + innerR), control: CGPoint(x: center.x, y: center.y))
        path.closeSubpath()
        
        ctx.addPath(path)
        ctx.setFillColor(NSColor(hex: colorHex).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }
    
    drawSparkle(center: CGPoint(x: 690, y: 670), radius: 68, colorHex: "#A855F7")
    drawSparkle(center: CGPoint(x: 690, y: 670), radius: 46, colorHex: "#E0E7FF")
    drawSparkle(center: CGPoint(x: 770, y: 740), radius: 28, colorHex: "#38BDF8")
    drawSparkle(center: CGPoint(x: 610, y: 730), radius: 18, colorHex: "#50FA7B")
    
    ctx.restoreGState() // Unclip squircle
    
    image.unlockFocus()
    return image
}

extension NSColor {
    convenience init(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        var rgbValue: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&rgbValue)
        let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgbValue & 0x0000FF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

// Generate PNG
let iconImage = createIcon()
guard let tiffData = iconImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to generate PNG data")
}

let outputURL = URL(fileURLWithPath: "AppIcon.png")
try pngData.write(to: outputURL)
print("✅ Generated AppIcon.png (1024x1024)")
