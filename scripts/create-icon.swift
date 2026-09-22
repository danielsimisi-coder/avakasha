import Cocoa
// Avakasha icon: open space. A deep sky, a warm circle rising over a clean horizon, and clutter thinning out below it.
let size = 1024
let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let tile = CGRect(x: 30, y: 30, width: 964, height: 964)
c.addPath(CGPath(roundedRect: tile, cornerWidth: 210, cornerHeight: 210, transform: nil)); c.clip()
let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 0.09, green: 0.12, blue: 0.30, alpha: 1), CGColor(red: 0.12, green: 0.38, blue: 0.52, alpha: 1), CGColor(red: 0.53, green: 0.80, blue: 0.78, alpha: 1)] as CFArray, locations: [0, 0.55, 1])!
c.drawLinearGradient(sky, start: CGPoint(x: 512, y: 994), end: CGPoint(x: 512, y: 30), options: [])
// Glow and the rising circle.
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 1.0, green: 0.85, blue: 0.55, alpha: 0.55), CGColor(red: 1.0, green: 0.85, blue: 0.55, alpha: 0)] as CFArray, locations: [0, 1])!
c.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 60, endCenter: CGPoint(x: 512, y: 560), endRadius: 420, options: [])
let sun = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 1.0, green: 0.93, blue: 0.72, alpha: 1), CGColor(red: 0.99, green: 0.72, blue: 0.40, alpha: 1)] as CFArray, locations: [0, 1])!
c.saveGState(); c.addEllipse(in: CGRect(x: 512 - 190, y: 560 - 190, width: 380, height: 380)); c.clip()
c.drawRadialGradient(sun, startCenter: CGPoint(x: 470, y: 620), startRadius: 20, endCenter: CGPoint(x: 512, y: 560), endRadius: 210, options: [])
c.restoreGState()
// Clean horizon band.
c.setFillColor(CGColor(red: 0.07, green: 0.20, blue: 0.30, alpha: 1))
c.addPath(CGPath(roundedRect: CGRect(x: 30, y: 30, width: 964, height: 360), cornerWidth: 0, cornerHeight: 0, transform: nil)); c.fillPath()
c.setStrokeColor(CGColor(red: 1.0, green: 0.93, blue: 0.75, alpha: 0.9)); c.setLineWidth(10); c.setLineCap(.round)
c.move(to: CGPoint(x: 150, y: 392)); c.addLine(to: CGPoint(x: 874, y: 392)); c.strokePath()
// Clutter thinning out: three bars, each shorter and fainter.
c.setLineCap(.round)
for (i, (width, alpha)) in [(560.0, 0.95), (380.0, 0.62), (200.0, 0.32)].enumerated() {
    c.setStrokeColor(CGColor(red: 0.63, green: 0.88, blue: 0.80, alpha: alpha)); c.setLineWidth(36)
    let y = 300.0 - Double(i) * 92.0
    c.move(to: CGPoint(x: 512 - width / 2, y: y)); c.addLine(to: CGPoint(x: 512 + width / 2, y: y)); c.strokePath()
}
let image = NSBitmapImageRep(cgImage: c.makeImage()!)
try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
