import AppKit
import SwiftUI

/// SwiftUI ile sunulan ev-maskot: 5 state'e 5 animasyon. Rive maskotu hazır olana
/// kadar aktif maskottur (ADR-009'daki de-risk yolu).
///
/// Çizim bilinçli olarak SwiftUI view hiyerarşisinde DEĞİL, kendi NSView'ında
/// CoreGraphics ile yapılır: kare başına yalnızca 48x48'lik bir alan yeniden
/// çizilir, SwiftUI layout'u hiç çalışmaz (CPU bütçesi < %3 bunun sayesinde tutar).
/// Tüm hareket, zamandan türetilen saf `MascotPose` fonksiyonuyla üretilir; 3D
/// hissi katmanlı zemin gölgesi ve gradyan boyamayla verilir.
struct PlaceholderMascotView: View, MascotAnimating {
    let state: SessionState

    @Environment(\.mascotAnimationsPaused) private var animationsPaused

    init(state: SessionState) {
        self.state = state
    }

    var body: some View {
        MascotCanvasRepresentable(state: state, isPaused: animationsPaused)
    }
}

/// Bir karedeki maskot duruşu; state + zamandan SAF olarak hesaplanır (yan etkisiz).
struct MascotPose {
    /// Zıplama yüksekliği, karakter boyuna oran (0 = yerde).
    var jumpHeight: CGFloat = 0
    /// Gövde dikey ölçeği; squash & stretch için yatayda tersi uygulanır.
    var squash: CGFloat = 1
    /// Gövde eğimi (attention sallanması), radyan.
    var tilt: CGFloat = 0
    /// 1 açık, 0 kapalı göz.
    var eyeOpenness: CGFloat = 1
    /// -1..1 bakış yönü (gözler yatay kayar).
    var eyeLookX: CGFloat = 0
    /// done konfetisinin ilerlemesi (0..1); aralık dışında konfeti çizilmez.
    var celebration: CGFloat = 0
    /// working'de baca dumanı aktif mi.
    var isSmoking = false
    /// limit'te zZz döngüsü aktif mi.
    var isSleeping = false

    init(state: SessionState, time t: TimeInterval, timeSinceStateChange dt: TimeInterval) {
        switch state {
        case .idle:
            // Yavaş nefes, ara sıra göz kırpma, etrafa bakınma.
            squash = 1 + 0.02 * sin(t * 2 * .pi / 3.2)
            eyeOpenness = t.truncatingRemainder(dividingBy: 3.7) < 0.14 ? 0.1 : 1
            eyeLookX = sin(t * 2 * .pi / 7.5) * 0.6

        case .working:
            // Hızlı, ufak tempolu zıplama + odaklı kısık gözlerle sağa sola tarama.
            let bob = abs(sin(t * 2 * .pi / 0.5))
            jumpHeight = 0.03 * bob
            squash = 1 - 0.03 * bob
            eyeOpenness = 0.7
            eyeLookX = sin(t * 2 * .pi / 0.8) * 0.8
            isSmoking = true

        case .attention:
            // Belirgin zıplama: tepede uzar, yere inince yassılır; hafif sallanır.
            let hop = abs(sin(t * 2 * .pi / 0.6))
            jumpHeight = 0.16 * hop
            squash = 0.94 + 0.14 * hop
            tilt = .pi / 45 * sin(t * 2 * .pi / 1.2)

        case .done:
            // Tek seferlik kutlama: ~1.5 sn coşkulu zıplama + konfeti, sonra sakin nefes.
            if dt < 1.5 {
                let hop = abs(sin(dt * 2 * .pi / 0.75))
                jumpHeight = 0.2 * hop
                squash = 0.92 + 0.16 * hop
                celebration = min(dt / 1.2, 1)
            } else {
                squash = 1 + 0.02 * sin(t * 2 * .pi / 2.4)
            }

        case .limit:
            // Uyku: çökük gövde, kapalı gözler, çok yavaş nefes, zZz.
            squash = 0.94 + 0.02 * sin(t * 2 * .pi / 4.5)
            eyeOpenness = 0
            isSleeping = true
        }
    }
}

/// MascotCanvasNSView'ı SwiftUI'ye bağlayan ince köprü.
private struct MascotCanvasRepresentable: NSViewRepresentable {
    let state: SessionState
    let isPaused: Bool

    func makeNSView(context: Context) -> MascotCanvasNSView {
        MascotCanvasNSView()
    }

    func updateNSView(_ view: MascotCanvasNSView, context: Context) {
        view.apply(state: state, isPaused: isPaused)
    }

    static func dismantleNSView(_ view: MascotCanvasNSView, coordinator: ()) {
        MascotFrameClock.shared.remove(view)
    }
}

/// Tüm maskot view'larını TEK bir zamanlayıcıyla senkron invalidate eden saat.
/// Kare başına tek CA commit'i garantiler (maskot başına ayrı timer, ayrı commit
/// üretip CPU'yu katlıyordu). Yalnızca ana thread'den kullanılır; view'lar zayıf
/// tutulur, çizmek isteyen kimse kalmayınca timer tamamen durur.
private final class MascotFrameClock {
    static let shared = MascotFrameClock()
    /// Tam kare temposu; sakin maskotlar frameDivisor ile bunun altına iner.
    /// 48 px'lik karakter için 20 fps akıcı; CPU bütçesi (< %3) için bilinçli tercih.
    static let baseInterval: TimeInterval = 1.0 / 20.0

    private let views = NSHashTable<MascotCanvasNSView>.weakObjects()
    private var timer: Timer?
    private var tick = 0

    func add(_ view: MascotCanvasNSView) {
        views.add(view)
        updateTimer()
    }

    func remove(_ view: MascotCanvasNSView) {
        views.remove(view)
        updateTimer()
    }

    /// Kayıtlı view'ların istekleri değiştiğinde timer'ı başlatır/durdurur.
    func updateTimer() {
        let anyActive = views.allObjects.contains { $0.wantsFrames }
        if anyActive {
            guard timer == nil else { return }
            let newTimer = Timer(timeInterval: Self.baseInterval, repeats: true) { [weak self] _ in
                self?.fire()
            }
            newTimer.tolerance = Self.baseInterval / 4
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func fire() {
        tick &+= 1
        var anyActive = false
        for view in views.allObjects where view.wantsFrames {
            anyActive = true
            if tick % view.frameDivisor == 0 {
                view.markFrame()
            }
        }
        if !anyActive {
            updateTimer()
        }
    }
}

/// Maskotu MascotFrameClock temposunda kendi CALayer'ına CoreGraphics ile çizen
/// görünüm. Kare üretimi NSView display döngüsüne HİÇ girmez (view display'i
/// NSHostingView'ın SwiftUI render/layout'unu da uyandırıyordu); sublayer'ın
/// setNeedsDisplay'i saf CA yolundan gider ve SwiftUI tarafı hiç çalışmaz.
private final class MascotCanvasNSView: NSView, CALayerDelegate {
    private let mascotLayer = CALayer()
    private var state: SessionState = .idle
    private var isPaused = false
    private var stateChangedAt = Date()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        mascotLayer.delegate = self
        mascotLayer.needsDisplayOnBoundsChange = true
        // İçerik/geometri değişiminde CA'nın örtük animasyonları istenmez
        // (kart insert animasyonunda layer'ın geride sürüklenmemesi için).
        mascotLayer.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
        ]
        // Varsayılan derin renk (RGBA16) backing store'u kare başına iki kat
        // bant genişliği yakıyordu; maskot için 8 bit fazlasıyla yeterli.
        mascotLayer.contentsFormat = .RGBA8Uint
        layer?.addSublayer(mascotLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Storyboard/NIB kullanılmıyor")
    }

    /// Saat bu view için kare üretmeli mi (pencerede ve duraklatılmamış).
    var wantsFrames: Bool { window != nil && !isPaused }

    /// Sakin state'lerde kare hızı yarıya düşer (15 fps); 48 px için yeterli.
    var frameDivisor: Int {
        switch state {
        case .idle, .limit: return 2
        case .working, .attention, .done: return 1
        }
    }

    /// MascotFrameClock'un kare işareti.
    func markFrame() {
        mascotLayer.setNeedsDisplay()
    }

    /// SwiftUI güncellemelerini uygular; saat yalnızca state/pause değişince dürtülür.
    func apply(state: SessionState, isPaused: Bool) {
        guard state != self.state || isPaused != self.isPaused else { return }
        if state != self.state {
            self.state = state
            stateChangedAt = Date()
        }
        self.isPaused = isPaused
        MascotFrameClock.shared.updateTimer()
        mascotLayer.setNeedsDisplay()
    }

    override func layout() {
        super.layout()
        mascotLayer.frame = bounds
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        mascotLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            mascotLayer.contentsScale = window?.backingScaleFactor ?? 2
            MascotFrameClock.shared.add(self)
        } else {
            MascotFrameClock.shared.remove(self)
        }
    }

    func draw(_ layer: CALayer, in context: CGContext) {
        // Tasarım uzayı üstten aşağı (y=0 tepe); CA'nın alt-sol origin'ini çevir.
        context.translateBy(x: 0, y: layer.bounds.height)
        context.scaleBy(x: 1, y: -1)

        let now = Date()
        let time = now.timeIntervalSinceReferenceDate
        let renderer = MascotRenderer(
            state: state,
            pose: MascotPose(
                state: state,
                time: time,
                timeSinceStateChange: now.timeIntervalSince(stateChangedAt)
            ),
            time: time
        )
        // NSAttributedString.draw (zZz) mevcut bir NSGraphicsContext ister.
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        renderer.draw(in: context, size: layer.bounds.size)
        NSGraphicsContext.current = previous
    }
}

/// Maskotu 48x48'lik tasarım uzayında CGContext'e çizen renderer. Zemin gölgesi
/// zıplamayla küçülür/soluklaşır, çatı ve gövde gradyanla boyanır.
private struct MascotRenderer {
    let state: SessionState
    let pose: MascotPose
    let time: TimeInterval

    private enum Palette {
        static let bodyTop = CGColor(red: 0.99, green: 0.94, blue: 0.86, alpha: 1)
        static let bodyBottom = CGColor(red: 0.90, green: 0.81, blue: 0.69, alpha: 1)
        // limit'te uyuyan, soluk gövde.
        static let bodyTopMuted = CGColor(red: 0.88, green: 0.86, blue: 0.83, alpha: 1)
        static let bodyBottomMuted = CGColor(red: 0.76, green: 0.74, blue: 0.70, alpha: 1)
        static let outline = CGColor(red: 0.45, green: 0.33, blue: 0.22, alpha: 0.35)
        static let chimney = CGColor(red: 0.55, green: 0.38, blue: 0.30, alpha: 1)
        static let eye = CGColor(red: 0.25, green: 0.18, blue: 0.12, alpha: 1)
        static let mouth = CGColor(red: 0.45, green: 0.30, blue: 0.20, alpha: 1)
        static let smoke = CGColor(gray: 0.55, alpha: 1)
        static let confetti: [CGColor] = [
            CGColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1),
            CGColor(red: 0.98, green: 0.82, blue: 0.25, alpha: 1),
            CGColor(red: 0.98, green: 0.58, blue: 0.22, alpha: 1),
            CGColor(red: 0.35, green: 0.82, blue: 0.75, alpha: 1),
            CGColor(red: 0.95, green: 0.52, blue: 0.70, alpha: 1),
        ]
        /// State renk dilinin (SessionState.tint) CG karşılığı, bir kez çözülür.
        static let tint: [SessionState: CGColor] = Dictionary(
            uniqueKeysWithValues: SessionState.allCases.map { ($0, NSColor($0.tint).cgColor) }
        )
    }

    // Gradyanlar ve renk uzayı dönüşümleri pahalıdır; kare başına değil, bir kez
    // yaratılır (CGGradientCreate + CMS dönüşümü profillemede sıcak çıkmıştı).
    private enum Gradients {
        static let body = make([Palette.bodyTop, Palette.bodyBottom])
        static let bodyMuted = make([Palette.bodyTopMuted, Palette.bodyBottomMuted])
        static let roofHighlight = make([CGColor(gray: 1, alpha: 0.30), CGColor(gray: 1, alpha: 0)])
        static let shadow = make([CGColor(gray: 0, alpha: 0.22), CGColor(gray: 0, alpha: 0)])
        static let roof: [SessionState: CGGradient] = Dictionary(
            uniqueKeysWithValues: SessionState.allCases.compactMap { state in
                guard let tint = Palette.tint[state] else { return nil }
                return make([tint.copy(alpha: 0.95) ?? tint, tint.copy(alpha: 0.65) ?? tint])
                    .map { (state, $0) }
            }
        )

        private static func make(_ colors: [CGColor]) -> CGGradient? {
            CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1]
            )
        }
    }

    // Ev gövdesi (baca+çatı+gövde) her karede aynıdır; gradyan rasterizasyonunu
    // kare başına yapmamak için state başına bir kez 2x bitmap'e çizilir ve
    // her karede tek blit yapılır (profillemede ripc_DrawShading sıcak çıkmıştı).
    private enum Sprites {
        static let pixelScale: CGFloat = 2
        static let house: [SessionState: CGImage] = Dictionary(
            uniqueKeysWithValues: SessionState.allCases.compactMap { state in
                makeHouse(for: state).map { (state, $0) }
            }
        )

        /// Yumuşak kenarlı elips zemin gölgesi (radyal gradyan), bir kez üretilir.
        static let shadow: CGImage? = {
            let width = Int(30 * pixelScale)
            let height = Int(5 * pixelScale)
            guard
                let bitmap = makeBitmap(width: width, height: height),
                let gradient = Gradients.shadow
            else { return nil }
            bitmap.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
            bitmap.scaleBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
            bitmap.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: 1,
                options: []
            )
            return bitmap.makeImage()
        }()

        private static func makeHouse(for state: SessionState) -> CGImage? {
            let side = Int(48 * pixelScale)
            guard let bitmap = makeBitmap(width: side, height: side) else { return nil }
            // Tasarım uzayı üstten aşağı; bitmap'in alt-sol origin'ini çevir.
            bitmap.translateBy(x: 0, y: CGFloat(side))
            bitmap.scaleBy(x: 1, y: -1)
            MascotRenderer.drawHouse(bitmap, pixelScale, state: state)
            return bitmap.makeImage()
        }

        private static func makeBitmap(width: Int, height: Int) -> CGContext? {
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
    }

    func draw(in context: CGContext, size: CGSize) {
        let u = min(size.width, size.height) / 48
        if state == .attention {
            drawAttentionRing(context, u)
        }
        drawGroundShadow(context, u)

        context.saveGState()
        if state == .limit {
            context.setAlpha(0.85)
        }
        // Squash & stretch ve eğim, karakterin taban çizgisinden (y=42) uygulanır
        // ki zıplama fiziksel dursun.
        let anchor = CGPoint(x: 24 * u, y: 42 * u)
        context.translateBy(x: 0, y: -pose.jumpHeight * 48 * u)
        context.translateBy(x: anchor.x, y: anchor.y)
        context.rotate(by: pose.tilt)
        context.scaleBy(x: 2 - pose.squash, y: pose.squash)
        context.translateBy(x: -anchor.x, y: -anchor.y)

        if pose.isSmoking { drawSmoke(context, u) }
        if pose.isSleeping { drawSleepZs(context, u) }
        if let house = Sprites.house[state] {
            blit(house, in: CGRect(x: 0, y: 0, width: 48 * u, height: 48 * u), context: context)
        } else {
            Self.drawHouse(context, u, state: state)
        }
        drawEyes(context, u)
        drawMouth(context, u)
        context.restoreGState()

        if pose.celebration > 0 && pose.celebration < 1 {
            drawConfetti(context, u)
        }
    }

    /// Üstten-aşağı (flipped) hedef context'e bitmap'i dik çizer.
    private func blit(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// Evin statik parçaları; hem sprite üretiminde hem (sprite yoksa) doğrudan çizimde kullanılır.
    private static func drawHouse(_ context: CGContext, _ u: CGFloat, state: SessionState) {
        drawChimney(context, u)
        drawRoof(context, u, state: state)
        drawBody(context, u, state: state)
    }

    // MARK: - Attention halkası

    /// attention: karakterin arkasında dışa yayılıp sönen puls halkası.
    private func drawAttentionRing(_ context: CGContext, _ u: CGFloat) {
        guard let tint = Palette.tint[state] else { return }
        let phase = (time / 1.1).truncatingRemainder(dividingBy: 1)
        let radius = (14 + 9 * phase) * u
        let center = CGPoint(x: 24 * u, y: 26 * u)
        context.saveGState()
        context.setStrokeColor(tint.copy(alpha: (1 - phase) * 0.7) ?? tint)
        context.setLineWidth((2.2 - 1.4 * phase) * u)
        context.strokeEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        context.restoreGState()
    }

    // MARK: - Zemin gölgesi

    private func drawGroundShadow(_ context: CGContext, _ u: CGFloat) {
        let lift = min(pose.jumpHeight / 0.2, 1)
        guard let shadow = Sprites.shadow else { return }
        // Zıplama arttıkça gölge küçülür ve soluklaşır; sprite simetrik olduğu
        // için flip dansına gerek yok.
        let width = (30 - 8 * lift) * u
        let height = 5 * u
        context.saveGState()
        context.setAlpha(1.0 - 0.6 * lift)
        context.draw(shadow, in: CGRect(
            x: 24 * u - width / 2,
            y: 44 * u - height / 2,
            width: width,
            height: height
        ))
        context.restoreGState()
    }

    // MARK: - Karakter parçaları (statik; sprite üretiminde kullanılır)

    private static func drawBody(_ context: CGContext, _ u: CGFloat, state: SessionState) {
        let rect = CGRect(x: 10 * u, y: 21 * u, width: 28 * u, height: 20 * u)
        let path = CGPath(roundedRect: rect, cornerWidth: 5 * u, cornerHeight: 5 * u, transform: nil)
        let gradient = state == .limit ? Gradients.bodyMuted : Gradients.body
        if let gradient {
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )
            context.restoreGState()
        }
        context.addPath(path)
        context.setStrokeColor(Palette.outline)
        context.setLineWidth(0.8 * u)
        context.strokePath()
    }

    private static func drawRoof(_ context: CGContext, _ u: CGFloat, state: SessionState) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 24 * u, y: 8 * u))
        path.addLine(to: CGPoint(x: 41 * u, y: 22 * u))
        path.addLine(to: CGPoint(x: 7 * u, y: 22 * u))
        path.closeSubpath()

        if let gradient = Gradients.roof[state] {
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 7 * u, y: 8 * u),
                end: CGPoint(x: 41 * u, y: 22 * u),
                options: []
            )
            // Üstten vuran ışık; çatıya hacim katar.
            if let highlight = Gradients.roofHighlight {
                context.drawLinearGradient(
                    highlight,
                    start: CGPoint(x: 24 * u, y: 8 * u),
                    end: CGPoint(x: 24 * u, y: 22 * u),
                    options: []
                )
            }
            context.restoreGState()
        }
    }

    private static func drawChimney(_ context: CGContext, _ u: CGFloat) {
        let rect = CGRect(x: 30 * u, y: 8 * u, width: 5 * u, height: 8 * u)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 1.2 * u, cornerHeight: 1.2 * u, transform: nil))
        context.setFillColor(Palette.chimney)
        context.fillPath()
    }

    private func drawEyes(_ context: CGContext, _ u: CGFloat) {
        let openness = max(pose.eyeOpenness, 0.08)
        let eyeHeight = 4.6 * u * openness
        context.setFillColor(Palette.eye)
        for centerX in [19.0, 29.0] {
            let x = centerX * u + pose.eyeLookX * 1.5 * u
            let rect = CGRect(x: x - 2.3 * u, y: 29 * u - eyeHeight / 2, width: 4.6 * u, height: eyeHeight)
            context.fillEllipse(in: rect)
        }
        if pose.eyeOpenness > 0.3 {
            // Minik ışık yansıması gözü canlandırır.
            context.setFillColor(CGColor(gray: 1, alpha: 0.85))
            for centerX in [19.0, 29.0] {
                let x = centerX * u + pose.eyeLookX * 1.5 * u
                let highlight = CGRect(
                    x: x - 1.6 * u,
                    y: 29 * u - 1.6 * u * openness,
                    width: 1.4 * u,
                    height: 1.4 * u
                )
                context.fillEllipse(in: highlight)
            }
        }
    }

    private func drawMouth(_ context: CGContext, _ u: CGFloat) {
        let center = CGPoint(x: 24 * u, y: 35.5 * u)
        switch state {
        case .done, .idle:
            let width: CGFloat = state == .done ? 8 * u : 5 * u
            let depth: CGFloat = state == .done ? 4 * u : 2.5 * u
            let smile = CGMutablePath()
            smile.move(to: CGPoint(x: center.x - width / 2, y: center.y))
            smile.addQuadCurve(
                to: CGPoint(x: center.x + width / 2, y: center.y),
                control: CGPoint(x: center.x, y: center.y + depth)
            )
            context.addPath(smile)
            context.setStrokeColor(Palette.mouth)
            context.setLineWidth((state == .done ? 1.3 : 1.1) * u)
            context.setLineCap(.round)
            context.strokePath()
        case .attention:
            let rect = CGRect(x: center.x - 1.75 * u, y: center.y - 1.75 * u, width: 3.5 * u, height: 3.5 * u)
            context.setFillColor(Palette.mouth)
            context.fillEllipse(in: rect)
        case .working, .limit:
            let rect = CGRect(x: center.x - 2.25 * u, y: center.y - 0.65 * u, width: 4.5 * u, height: 1.3 * u)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 0.65 * u, cornerHeight: 0.65 * u, transform: nil))
            context.setFillColor(Palette.mouth)
            context.fillPath()
        }
    }

    // MARK: - Aksesuarlar

    /// working: bacadan düzenli aralıklarla yükselip dağılan duman lokmaları.
    private func drawSmoke(_ context: CGContext, _ u: CGFloat) {
        for index in 0..<3 {
            let phase = (time / 1.4 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let diameter = (2.5 + 3.5 * phase) * u
            let center = CGPoint(
                x: (32.5 + sin(phase * 4 * .pi + Double(index)) * 1.5) * u,
                y: (7 - phase * 9) * u
            )
            let rect = CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.setFillColor(Palette.smoke.copy(alpha: (1 - phase) * 0.5) ?? Palette.smoke)
            context.fillEllipse(in: rect)
        }
    }

    /// limit: çatının yanından süzülüp kaybolan zZz harfleri.
    private func drawSleepZs(_ context: CGContext, _ u: CGFloat) {
        for index in 0..<3 {
            let phase = (time / 2.2 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let fontSize = (4.5 + 3 * phase) * u
            let alpha = phase < 0.15 ? phase / 0.15 : 1 - phase
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) }
            let text = NSAttributedString(
                string: "z",
                attributes: [
                    .font: rounded ?? font,
                    .foregroundColor: NSColor.gray.withAlphaComponent(alpha),
                ]
            )
            text.draw(at: CGPoint(
                x: (35 + phase * 5) * u - fontSize * 0.3,
                y: (14 - phase * 12) * u - fontSize * 0.6
            ))
        }
    }

    /// done: karakterin etrafına saçılıp sönen konfeti parçacıkları.
    private func drawConfetti(_ context: CGContext, _ u: CGFloat) {
        let angles: [Double] = [-150, -110, -80, -50, -20]
        let progress = pose.celebration
        let radius = (10 + 15 * progress) * u
        let side = (2.6 - 1.4 * progress) * u
        for index in 0..<5 {
            let angle = angles[index] * .pi / 180
            context.saveGState()
            context.setAlpha(1 - progress)
            context.translateBy(
                x: 24 * u + cos(angle) * radius,
                y: 22 * u + sin(angle) * radius
            )
            context.rotate(by: (progress * 180 + Double(index) * 30) * .pi / 180)
            let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 0.6 * u, cornerHeight: 0.6 * u, transform: nil))
            context.setFillColor(Palette.confetti[index])
            context.fillPath()
            context.restoreGState()
        }
    }
}

#Preview("State'ler") {
    HStack(spacing: 16) {
        ForEach(SessionState.allCases, id: \.self) { state in
            VStack(spacing: 6) {
                PlaceholderMascotView(state: state)
                    .frame(width: 48, height: 48)
                Text(state.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
}
