// Gözcü uygulama simgesini çizer: swift simge.swift <çıktı.png>
import AppKit

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let rect = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 80, dy: 80)
let path = NSBezierPath(roundedRect: rect, xRadius: 190, yRadius: 190)
NSGradient(colors: [NSColor(red: 0.10, green: 0.11, blue: 0.20, alpha: 1), NSColor(red: 0.24, green: 0.14, blue: 0.42, alpha: 1)])!
    .draw(in: path, angle: -60)
// Halka
let ring = NSBezierPath()
ring.appendArc(withCenter: NSPoint(x: size / 2, y: size / 2), radius: 270, startAngle: 210, endAngle: -30, clockwise: true)
ring.lineWidth = 56
ring.lineCapStyle = .round
NSColor(red: 0.36, green: 0.67, blue: 1.0, alpha: 1).setStroke()
ring.stroke()
let hot = NSBezierPath()
hot.appendArc(withCenter: NSPoint(x: size / 2, y: size / 2), radius: 270, startAngle: 40, endAngle: -30, clockwise: true)
hot.lineWidth = 56
hot.lineCapStyle = .round
NSColor(red: 1.0, green: 0.45, blue: 0.35, alpha: 1).setStroke()
hot.stroke()
// Göz
if let sym = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 300, weight: .bold).applying(.init(paletteColors: [.white]))) {
    let s = sym.size
    sym.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
