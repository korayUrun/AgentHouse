import AppKit

// AgentHouse uygulama ikonu üretici: maskot evi (PlaceholderMascotView paletiyle)
// indigo squircle zemin üzerine çizer, macOS AppIcon boyutlarında PNG üretir.

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "./AppIcon.appiconset"

struct P {
    static let bgTop = NSColor(calibratedRed: 0.42, green: 0.40, blue: 0.85, alpha: 1)
    static let bgBottom = NSColor(calibratedRed: 0.24, green: 0.22, blue: 0.55, alpha: 1)
    static let bodyTop = NSColor(calibratedRed: 0.99, green: 0.94, blue: 0.86, alpha: 1)
    static let bodyBottom = NSColor(calibratedRed: 0.90, green: 0.81, blue: 0.69, alpha: 1)
    static let roofTop = NSColor(calibratedRed: 0.58, green: 0.55, blue: 0.98, alpha: 1)
    static let roofBottom = NSColor(calibratedRed: 0.38, green: 0.35, blue: 0.80, alpha: 1)
    static let chimney = NSColor(calibratedRed: 0.55, green: 0.38, blue: 0.30, alpha: 1)
    static let eye = NSColor(calibratedRed: 0.25, green: 0.18, blue: 0.12, alpha: 1)
    static let mouth = NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.20, alpha: 1)
    static let smoke = NSColor(calibratedWhite: 1, alpha: 0.75)
}

/// 1024'lük tasarım uzayında ikonu çizer; her hedef boyut buradan ölçeklenir.
func drawIcon(size: CGFloat) {
    let s = size / 1024.0
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    // --- macOS squircle plakası (kenarlardan ~%10 boşluk) ---
    let plate = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let platePath = NSBezierPath(roundedRect: plate, xRadius: 185 * s, yRadius: 185 * s)

    // Hafif zemin gölgesi (büyük boyutlarda algılanır, küçükte kaybolur).
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -12 * s),
        blur: 24 * s,
        color: NSColor.black.withAlphaComponent(0.3).cgColor
    )
    P.bgBottom.setFill()
    platePath.fill()
    ctx.restoreGState()

    NSGradient(starting: P.bgTop, ending: P.bgBottom)?
        .draw(in: platePath, angle: -90)

    // Bundan sonrası plaka içinde kalsın.
    platePath.addClip()

    // --- Ev gövdesi (yatayda ortalı; çatı+gövde bloğu dikeyde ortalı) ---
    // Tasarım uzayı (1024): gövde 480x360 @ y=280..640, çatı tepesi y=740, taban gölgesi.
    let bodyRect = NSRect(x: 272 * s, y: 280 * s, width: 480 * s, height: 360 * s)
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 56 * s, yRadius: 56 * s)

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -10 * s),
        blur: 30 * s,
        color: NSColor.black.withAlphaComponent(0.25).cgColor
    )
    P.bodyBottom.setFill()
    bodyPath.fill()
    ctx.restoreGState()
    NSGradient(starting: P.bodyTop, ending: P.bodyBottom)?
        .draw(in: bodyPath, angle: -90)

    // --- Çatı (gövdeden taşan saçaklı üçgen) ---
    let roof = NSBezierPath()
    roof.move(to: NSPoint(x: 216 * s, y: 600 * s))
    roof.line(to: NSPoint(x: 512 * s, y: 780 * s))
    roof.line(to: NSPoint(x: 808 * s, y: 600 * s))
    roof.line(to: NSPoint(x: 776 * s, y: 560 * s))
    roof.line(to: NSPoint(x: 512 * s, y: 720 * s))
    roof.line(to: NSPoint(x: 248 * s, y: 560 * s))
    roof.close()
    // Üçgen dolgu (saçak altı): önce tam üçgeni doldur.
    let roofFill = NSBezierPath()
    roofFill.move(to: NSPoint(x: 248 * s, y: 574 * s))
    roofFill.line(to: NSPoint(x: 512 * s, y: 744 * s))
    roofFill.line(to: NSPoint(x: 776 * s, y: 574 * s))
    roofFill.close()
    NSGradient(starting: P.roofTop, ending: P.roofBottom)?
        .draw(in: roofFill, angle: -90)
    NSGradient(starting: P.roofTop, ending: P.roofBottom)?
        .draw(in: roof, angle: -90)

    // --- Baca + duman ---
    let chimney = NSRect(x: 640 * s, y: 640 * s, width: 72 * s, height: 150 * s)
    P.chimney.setFill()
    NSBezierPath(roundedRect: chimney, xRadius: 12 * s, yRadius: 12 * s).fill()
    P.smoke.setFill()
    NSBezierPath(ovalIn: NSRect(x: 648 * s, y: 806 * s, width: 56 * s, height: 56 * s)).fill()
    NSBezierPath(ovalIn: NSRect(x: 692 * s, y: 866 * s, width: 38 * s, height: 38 * s)).fill()

    // --- Yüz: gözler + gülümseme ---
    P.eye.setFill()
    NSBezierPath(ovalIn: NSRect(x: 388 * s, y: 468 * s, width: 44 * s, height: 56 * s)).fill()
    NSBezierPath(ovalIn: NSRect(x: 592 * s, y: 468 * s, width: 44 * s, height: 56 * s)).fill()

    let smile = NSBezierPath()
    smile.appendArc(
        withCenter: NSPoint(x: 512 * s, y: 430 * s),
        radius: 52 * s,
        startAngle: 200,
        endAngle: 340,
        clockwise: false
    )
    smile.lineWidth = 16 * s
    smile.lineCapStyle = .round
    P.mouth.setStroke()
    smile.stroke()

    // Yanaklar: maskotun sıcaklığını taşıyan hafif allık.
    NSColor(calibratedRed: 0.95, green: 0.60, blue: 0.50, alpha: 0.35).setFill()
    NSBezierPath(ovalIn: NSRect(x: 344 * s, y: 420 * s, width: 52 * s, height: 34 * s)).fill()
    NSBezierPath(ovalIn: NSRect(x: 628 * s, y: 420 * s, width: 52 * s, height: 34 * s)).fill()
}

func renderPNG(pixels: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap rep") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encode")
    }
    try data.write(to: url)
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let dir = URL(fileURLWithPath: outputDir)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for px in sizes {
    let url = dir.appendingPathComponent("icon_\(px).png")
    try renderPNG(pixels: px, to: url)
    print("yazıldı: \(url.path)")
}
