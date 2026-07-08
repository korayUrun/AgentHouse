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
    let character: MascotCharacter

    @Environment(\.mascotAnimationsPaused) private var animationsPaused

    init(state: SessionState, character: MascotCharacter = .default) {
        self.state = state
        self.character = character
    }

    var body: some View {
        MascotCanvasRepresentable(state: state, character: character, isPaused: animationsPaused)
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
    /// -1..1 turntable dönüş illüzyonu (2.5D): gövde yatayda daralır, yüz o yöne
    /// kayar, tepe ışığı ters yöne süzülür. 0 = tam karşıdan.
    var spin: CGFloat = 0
    /// done konfetisinin ilerlemesi (0..1); aralık dışında konfeti çizilmez.
    var celebration: CGFloat = 0
    /// working'de baca dumanı aktif mi.
    var isSmoking = false
    /// limit'te zZz döngüsü aktif mi.
    var isSleeping = false
    /// questioning'de "?" balonu aktif mi (ADR-015).
    var isQuestioning = false

    init(state: SessionState, time t: TimeInterval, timeSinceStateChange dt: TimeInterval) {
        switch state {
        case .idle:
            // Yavaş nefes, ara sıra göz kırpma, etrafa bakınma; bakışla aynı fazda
            // yavaş turntable dönüşü (2.5D).
            squash = 1 + 0.02 * sin(t * 2 * .pi / 3.2)
            eyeOpenness = t.truncatingRemainder(dividingBy: 3.7) < 0.14 ? 0.1 : 1
            eyeLookX = sin(t * 2 * .pi / 7.5) * 0.6
            spin = sin(t * 2 * .pi / 7.5) * 0.5

        case .working:
            // Hızlı, ufak tempolu zıplama + odaklı kısık gözlerle sağa sola tarama.
            let bob = abs(sin(t * 2 * .pi / 0.5))
            jumpHeight = 0.03 * bob
            squash = 1 - 0.03 * bob
            eyeOpenness = 0.7
            eyeLookX = sin(t * 2 * .pi / 0.8) * 0.8
            spin = sin(t * 2 * .pi / 0.8) * 0.2
            isSmoking = true

        case .attention:
            // Belirgin zıplama: tepede uzar, yere inince yassılır; hafif sallanır.
            let hop = abs(sin(t * 2 * .pi / 0.6))
            jumpHeight = 0.16 * hop
            squash = 0.94 + 0.14 * hop
            tilt = .pi / 45 * sin(t * 2 * .pi / 1.2)

        case .questioning:
            // Meraklı bekleyiş: yana eğik kafa, iri gözlerle bakınma, yavaş nefes;
            // bakışla aynı fazda dönüş (2.5D).
            tilt = .pi / 30 * sin(t * 2 * .pi / 2.4)
            squash = 1 + 0.02 * sin(t * 2 * .pi / 2.8)
            eyeOpenness = 1.1
            eyeLookX = sin(t * 2 * .pi / 3.5) * 0.9
            spin = sin(t * 2 * .pi / 3.5) * 0.5
            isQuestioning = true

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
    let character: MascotCharacter
    let isPaused: Bool

    func makeNSView(context: Context) -> MascotCanvasNSView {
        MascotCanvasNSView()
    }

    func updateNSView(_ view: MascotCanvasNSView, context: Context) {
        view.apply(state: state, character: character, isPaused: isPaused)
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
    private var character: MascotCharacter = .default
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
        case .idle, .limit, .questioning: return 2
        case .working, .attention, .done: return 1
        }
    }

    /// MascotFrameClock'un kare işareti.
    func markFrame() {
        mascotLayer.setNeedsDisplay()
    }

    /// SwiftUI güncellemelerini uygular; saat yalnızca state/karakter/pause değişince dürtülür.
    func apply(state: SessionState, character: MascotCharacter, isPaused: Bool) {
        guard state != self.state || character != self.character || isPaused != self.isPaused else { return }
        if state != self.state {
            self.state = state
            stateChangedAt = Date()
        }
        self.character = character
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
            character: character,
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
/// zıplamayla küçülür/soluklaşır, gövdeler gradyanla boyanır. Karakterler (ADR-014)
/// yalnızca statik gövde çizimi ve efekt çapa noktalarıyla ayrışır; yüz konumu ve
/// tüm poz fiziği ortaktır.
struct MascotRenderer {
    let state: SessionState
    let character: MascotCharacter
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
        // Deniz feneri: sıcak cam ve süpüren ışık huzmesi.
        static let lanternGlass = CGColor(red: 1.0, green: 0.92, blue: 0.62, alpha: 1)
        static let beam = CGColor(red: 1.0, green: 0.95, blue: 0.65, alpha: 0.40)
        // Roket alevi: dış turuncu, iç sarı.
        static let flameOuter = CGColor(red: 1.0, green: 0.55, blue: 0.20, alpha: 0.95)
        static let flameInner = CGColor(red: 1.0, green: 0.86, blue: 0.38, alpha: 0.95)
        // Gülen yüz: sıcak sarı-krem tonları, pembe yanak, mavi ter damlası.
        static let smileyTop = CGColor(red: 1.0, green: 0.95, blue: 0.74, alpha: 1)
        static let smileyBottom = CGColor(red: 0.95, green: 0.80, blue: 0.52, alpha: 1)
        static let smileyTopMuted = CGColor(red: 0.90, green: 0.88, blue: 0.82, alpha: 1)
        static let smileyBottomMuted = CGColor(red: 0.78, green: 0.74, blue: 0.66, alpha: 1)
        static let cheek = CGColor(red: 0.96, green: 0.60, blue: 0.50, alpha: 0.45)
        static let sweat = CGColor(red: 0.40, green: 0.65, blue: 0.95, alpha: 0.9)
        // Özgürlük Heykeli (pixel art): bakır yeşili tonları.
        static let statueLight = CGColor(red: 0.64, green: 0.85, blue: 0.73, alpha: 1)
        static let statueMid = CGColor(red: 0.45, green: 0.72, blue: 0.60, alpha: 1)
        static let statueDark = CGColor(red: 0.30, green: 0.54, blue: 0.44, alpha: 1)
        static let statueLightMuted = CGColor(red: 0.78, green: 0.80, blue: 0.78, alpha: 1)
        static let statueMidMuted = CGColor(red: 0.64, green: 0.68, blue: 0.65, alpha: 1)
        static let statueDarkMuted = CGColor(red: 0.48, green: 0.53, blue: 0.50, alpha: 1)
        // Robot (pixel art): çelik grisi tonları.
        static let robotLight = CGColor(red: 0.79, green: 0.83, blue: 0.87, alpha: 1)
        static let robotMid = CGColor(red: 0.60, green: 0.66, blue: 0.73, alpha: 1)
        static let robotDark = CGColor(red: 0.37, green: 0.43, blue: 0.51, alpha: 1)
        static let robotLightMuted = CGColor(red: 0.79, green: 0.79, blue: 0.79, alpha: 1)
        static let robotMidMuted = CGColor(red: 0.64, green: 0.64, blue: 0.64, alpha: 1)
        static let robotDarkMuted = CGColor(red: 0.46, green: 0.46, blue: 0.46, alpha: 1)
        // Yarış arabası: kırmızı gövde, koyu lastik, açık cam.
        static let carTop = CGColor(red: 0.93, green: 0.33, blue: 0.28, alpha: 1)
        static let carBottom = CGColor(red: 0.74, green: 0.18, blue: 0.16, alpha: 1)
        static let carTopMuted = CGColor(red: 0.80, green: 0.62, blue: 0.60, alpha: 1)
        static let carBottomMuted = CGColor(red: 0.66, green: 0.52, blue: 0.50, alpha: 1)
        static let tire = CGColor(red: 0.22, green: 0.20, blue: 0.20, alpha: 1)
        static let glass = CGColor(red: 0.78, green: 0.89, blue: 0.95, alpha: 1)
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
        static let car = make([Palette.carTop, Palette.carBottom])
        static let carMuted = make([Palette.carTopMuted, Palette.carBottomMuted])
        static let smiley = make([Palette.smileyTop, Palette.smileyBottom])
        static let smileyMuted = make([Palette.smileyTopMuted, Palette.smileyBottomMuted])
        static let roofHighlight = make([CGColor(gray: 1, alpha: 0.30), CGColor(gray: 1, alpha: 0)])
        static let movingLight = make([CGColor(gray: 1, alpha: 0.16), CGColor(gray: 1, alpha: 0)])
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

    // Karakter gövdesi her karede aynıdır; gradyan rasterizasyonunu kare başına
    // yapmamak için (karakter, state) başına bir kez 2x bitmap'e çizilir ve
    // her karede tek blit yapılır (profillemede ripc_DrawShading sıcak çıkmıştı).
    private enum Sprites {
        // 64pt kart maskotu @2x = 128 px ister; 48 birim × 3 = 144 px ile keskin kalır.
        static let pixelScale: CGFloat = 3

        struct Key: Hashable {
            let character: MascotCharacter
            let state: SessionState
        }

        static let body: [Key: CGImage] = {
            var result: [Key: CGImage] = [:]
            for character in MascotCharacter.allCases {
                for state in SessionState.allCases {
                    if let image = makeBody(character: character, state: state) {
                        result[Key(character: character, state: state)] = image
                    }
                }
            }
            return result
        }()

        /// 2.5D gezen ışık lekesi (radyal beyaz gradyan), bir kez üretilir.
        static let movingLight: CGImage? = {
            let side = Int(34 * pixelScale)
            guard
                let bitmap = makeBitmap(width: side, height: side),
                let gradient = Gradients.movingLight
            else { return nil }
            let center = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
            bitmap.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: CGFloat(side) / 2,
                options: []
            )
            return bitmap.makeImage()
        }()

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

        private static func makeBody(character: MascotCharacter, state: SessionState) -> CGImage? {
            let side = Int(48 * pixelScale)
            guard let bitmap = makeBitmap(width: side, height: side) else { return nil }
            // Tasarım uzayı üstten aşağı; bitmap'in alt-sol origin'ini çevir.
            bitmap.translateBy(x: 0, y: CGFloat(side))
            bitmap.scaleBy(x: 1, y: -1)
            MascotRenderer.drawBody(bitmap, pixelScale, character: character, state: state)
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
        // ki zıplama fiziksel dursun. 2.5D: zıplamada hafif perspektif büyümesi
        // (kameraya yaklaşma) ve turntable dönüşünde yatay daralma.
        let anchor = CGPoint(x: 24 * u, y: 42 * u)
        let perspective = 1 + pose.jumpHeight * 0.3
        let spinScale = 1 - 0.12 * abs(pose.spin)
        context.translateBy(x: 0, y: -pose.jumpHeight * 48 * u)
        context.translateBy(x: anchor.x, y: anchor.y)
        context.rotate(by: pose.tilt)
        context.scaleBy(x: (2 - pose.squash) * perspective * spinScale, y: pose.squash * perspective)
        context.translateBy(x: -anchor.x, y: -anchor.y)

        if pose.isSmoking { drawWorkingEffect(context, u) }
        if pose.isSleeping { drawSleepZs(context, u) }
        if pose.isQuestioning { drawQuestionMark(context, u) }
        if let body = Sprites.body[Sprites.Key(character: character, state: state)] {
            let rect = CGRect(x: 0, y: 0, width: 48 * u, height: 48 * u)
            blit(body, in: rect, context: context)
            drawMovingLight(in: rect, context: context, u)
        } else {
            Self.drawBody(context, u, character: character, state: state)
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

    /// 2.5D gezen ışık: dönüşe ters yöne kayan yumuşak tepe ışığı. Karakter
    /// dönerken ışığın sabit kalması hacim hissi verir. Maske klibi yerine
    /// `.sourceAtop` blend kullanılır (yalnızca alfası dolu piksellere işler);
    /// gradyan da kare başına değil bir kez rasterize edilir (CPU bütçesi).
    private func drawMovingLight(in rect: CGRect, context: CGContext, _ u: CGFloat) {
        guard let light = Sprites.movingLight else { return }
        let diameter = 34 * u
        let center = CGPoint(x: 24 * u - pose.spin * 7 * u, y: 18 * u)
        context.saveGState()
        context.setBlendMode(.sourceAtop)
        context.draw(light, in: CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        ))
        context.restoreGState()
    }

    /// Karakterin statik gövdesi; hem sprite üretiminde hem (sprite yoksa) doğrudan
    /// çizimde kullanılır. Her karakter yüzü aynı bölgeye (gözler y=29, ağız y=35.5)
    /// oturtacak şekilde tasarlanır ki yüz/poz kodu ortak kalsın.
    private static func drawBody(_ context: CGContext, _ u: CGFloat, character: MascotCharacter, state: SessionState) {
        switch character {
        case .house:
            drawChimney(context, u)
            drawRoof(context, u, state: state)
            drawHouseBody(context, u, state: state)
        case .lighthouse:
            drawLighthouse(context, u, state: state)
        case .rocket:
            drawRocket(context, u, state: state)
        case .raceCar:
            drawRaceCar(context, u, state: state)
        case .statueOfLiberty:
            drawStatueOfLiberty(context, u, state: state)
        case .smiley:
            drawSmiley(context, u, state: state)
        case .robot:
            drawRobot(context, u, state: state)
        }
    }

    /// Pixel art karakterlerin ortak çizicisi: 24x24 hücrelik satır haritasını
    /// (hücre = 2 birim) harf → renk eşlemesiyle boyar. Hücreler tam piksel
    /// sınırına oturduğu için ayrıca antialiasing kapatmaya gerek kalmaz.
    private static func drawPixelMap(
        _ rows: [String],
        colors: [Character: CGColor],
        _ context: CGContext,
        _ u: CGFloat
    ) {
        let cell = 2 * u
        for (rowIndex, row) in rows.enumerated() {
            for (colIndex, symbol) in row.enumerated() {
                guard let color = colors[symbol] else { continue }
                context.setFillColor(color)
                context.fill(CGRect(
                    x: CGFloat(colIndex) * cell,
                    y: CGFloat(rowIndex) * cell,
                    width: cell,
                    height: cell
                ))
            }
        }
    }

    /// Pixel art robot: çelik gövde, yanlarda kulak cıvataları, tepede state-tint
    /// anten ışığı (evdeki çatının karşılığı).
    private static func drawRobot(_ context: CGContext, _ u: CGFloat, state: SessionState) {
        let rows = [
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "...........FF...........",
            "...........FF...........",
            "...........DD...........",
            "......DDDDDDDDDDDD......",
            "......DLLLLLLLLLLD......",
            "......DLLLLLLLLLLD......",
            "......DLLLLLLLLLLD......",
            ".....MDLLLLLLLLLLDM.....",
            ".....MDLLLLLLLLLLDM.....",
            ".....MDLLLLLLLLLLDM.....",
            "......DLLLLLLLLLLD......",
            "......DLLLLLLLLLLD......",
            "......DLLLLLLLLLLD......",
            "......DLLLLLLLLLLD......",
            "......DDDDDDDDDDDD......",
            "........MMM..MMM........",
            "........................",
            "........................",
            "........................",
        ]
        let muted = state == .limit
        drawPixelMap(rows, colors: [
            "L": muted ? Palette.robotLightMuted : Palette.robotLight,
            "M": muted ? Palette.robotMidMuted : Palette.robotMid,
            "D": muted ? Palette.robotDarkMuted : Palette.robotDark,
            "F": Palette.tint[state] ?? Palette.flameInner,
        ], context, u)
    }

    /// Gülen yüz: sarı-krem top gövde, pembe yanaklar, tepede state-tint mini bere.
    /// Gözler/ağız ortak yüz sisteminden gelir (bu karakterde 1.5x ölçekle).
    private static func drawSmiley(_ context: CGContext, _ u: CGFloat, state: SessionState) {
        let face = CGRect(x: 10.5 * u, y: 15 * u, width: 27 * u, height: 26.5 * u)

        let gradient = state == .limit ? Gradients.smileyMuted : Gradients.smiley
        if let gradient {
            context.saveGState()
            context.addEllipse(in: face)
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: face.midX, y: face.minY),
                end: CGPoint(x: face.midX, y: face.maxY),
                options: []
            )
            // Sol üstten vuran yumuşak ışık.
            if let highlight = Gradients.roofHighlight {
                context.drawLinearGradient(
                    highlight,
                    start: CGPoint(x: face.midX, y: face.minY),
                    end: CGPoint(x: face.midX, y: face.midY),
                    options: []
                )
            }
            context.restoreGState()
        }
        context.addEllipse(in: face)
        context.setStrokeColor(Palette.outline)
        context.setLineWidth(0.8 * u)
        context.strokePath()

        // Yanaklar.
        context.setFillColor(Palette.cheek)
        context.fillEllipse(in: CGRect(x: 12.5 * u, y: 31.5 * u, width: 5.5 * u, height: 3.4 * u))
        context.fillEllipse(in: CGRect(x: 30 * u, y: 31.5 * u, width: 5.5 * u, height: 3.4 * u))

        // Mini bere: state renk dili buradan okunur (evdeki çatının karşılığı).
        if let roofGradient = Gradients.roof[state] {
            let cap = CGMutablePath()
            cap.move(to: CGPoint(x: 17.5 * u, y: 16.5 * u))
            cap.addQuadCurve(
                to: CGPoint(x: 30.5 * u, y: 16.5 * u),
                control: CGPoint(x: 24 * u, y: 10.5 * u)
            )
            cap.closeSubpath()
            context.saveGState()
            context.addPath(cap)
            context.clip()
            context.drawLinearGradient(
                roofGradient,
                start: CGPoint(x: 24 * u, y: 10.5 * u),
                end: CGPoint(x: 24 * u, y: 16.5 * u),
                options: []
            )
            context.restoreGState()
            // Ponpon.
            context.setFillColor(CGColor(gray: 1, alpha: 0.9))
            context.fillEllipse(in: CGRect(x: 22.7 * u, y: 9.3 * u, width: 2.6 * u, height: 2.6 * u))
        }
    }

    /// Özgürlük Heykeli, pixel art stilinde: 24x24 hücrelik ızgara (hücre = 2 birim),
    /// harf → renk eşlemeli satır haritasıyla çizilir. Meşale alevi state renk dilini
    /// taşır (evdeki çatının karşılığı). Hücreler tam piksel sınırına oturduğu için
    /// ayrıca antialiasing kapatmaya gerek kalmaz.
    private static func drawStatueOfLiberty(_ context: CGContext, _ u: CGFloat, state: SessionState) {
        // . boş, L açık yeşil, M orta, D koyu, T meşale sapı, F alev (state tint).
        let rows = [
            "........................",
            "........................",
            "..................F.....",
            ".................FFF....",
            ".................FFF....",
            "...........D......F....",
            "........D..D..D..TTT....",
            "........D..D..D...T.....",
            ".......DDDDDDDDDD.T.....",
            ".......MLLLLLLLLM.M.....",
            ".......MLLLLLLLLM.M.....",
            ".......MLLLLLLLLM.M.....",
            ".......MLLLLLLLLM.M.....",
            ".......MLLLLLLLLM.M.....",
            ".......MLLLLLLLLMM......",
            ".......MLLLLLLLLM.......",
            ".......MLLLLLLLLM.......",
            ".......MLLLLLLLLM.......",
            "........MLLLLLLM........",
            "....MMMMMMMMMMMMMMMM....",
            "....MMMDMMMDMMMDMMMM....",
            "........................",
            "........................",
            "........................",
        ]
        let muted = state == .limit
        drawPixelMap(rows, colors: [
            "L": muted ? Palette.statueLightMuted : Palette.statueLight,
            "M": muted ? Palette.statueMidMuted : Palette.statueMid,
            "D": muted ? Palette.statueDarkMuted : Palette.statueDark,
            "T": Palette.chimney,
            "F": Palette.tint[state] ?? Palette.flameInner,
        ], context, u)
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

    private static func drawHouseBody(_ context: CGContext, _ u: CGFloat, state: SessionState) {
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

    /// Deniz feneri: şeritli daralan kule, galeri platformu, fener odası ve
    /// state-tint kubbeli tepe. Yüz kuleye, ortak yüz bölgesine oturur.
    private static func drawLighthouse(_ context: CGContext, _ u: CGFloat, state: SessionState) {
        // Kule (daralan gövde).
        let tower = CGMutablePath()
        tower.move(to: CGPoint(x: 13 * u, y: 41 * u))
        tower.addLine(to: CGPoint(x: 17 * u, y: 14.5 * u))
        tower.addLine(to: CGPoint(x: 31 * u, y: 14.5 * u))
        tower.addLine(to: CGPoint(x: 35 * u, y: 41 * u))
        tower.closeSubpath()

        let gradient = state == .limit ? Gradients.bodyMuted : Gradients.body
        if let gradient {
            context.saveGState()
            context.addPath(tower)
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 24 * u, y: 14.5 * u),
                end: CGPoint(x: 24 * u, y: 41 * u),
                options: []
            )
            // Şeritler (yüz bölgesinin üstünde kalır).
            let stripe = Palette.chimney.copy(alpha: state == .limit ? 0.20 : 0.38) ?? Palette.chimney
            context.setFillColor(stripe)
            context.fill(CGRect(x: 12 * u, y: 16.5 * u, width: 24 * u, height: 2.8 * u))
            context.fill(CGRect(x: 12 * u, y: 22 * u, width: 24 * u, height: 2.8 * u))
            context.restoreGState()
        }
        context.addPath(tower)
        context.setStrokeColor(Palette.outline)
        context.setLineWidth(0.8 * u)
        context.strokePath()

        // Galeri platformu.
        let gallery = CGRect(x: 15.5 * u, y: 12.5 * u, width: 17 * u, height: 2.6 * u)
        context.addPath(CGPath(roundedRect: gallery, cornerWidth: 1.2 * u, cornerHeight: 1.2 * u, transform: nil))
        context.setFillColor(Palette.chimney)
        context.fillPath()

        // Fener odası (sıcak cam).
        let lantern = CGRect(x: 19.5 * u, y: 7 * u, width: 9 * u, height: 6 * u)
        context.addPath(CGPath(roundedRect: lantern, cornerWidth: 1 * u, cornerHeight: 1 * u, transform: nil))
        context.setFillColor(Palette.lanternGlass)
        context.fillPath()

        // Kubbe: state renk dili buradan okunur (evdeki çatının karşılığı).
        let dome = CGMutablePath()
        dome.move(to: CGPoint(x: 18.5 * u, y: 7.5 * u))
        dome.addQuadCurve(
            to: CGPoint(x: 29.5 * u, y: 7.5 * u),
            control: CGPoint(x: 24 * u, y: 1.5 * u)
        )
        dome.closeSubpath()
        if let roofGradient = Gradients.roof[state] {
            context.saveGState()
            context.addPath(dome)
            context.clip()
            context.drawLinearGradient(
                roofGradient,
                start: CGPoint(x: 18.5 * u, y: 2 * u),
                end: CGPoint(x: 29.5 * u, y: 7.5 * u),
                options: []
            )
            context.restoreGState()
        }
    }

    /// Jenerik yarış arabası (önden görünüm): koyu lastikler, kırmızı gövde,
    /// cam kabin ve state-tint arka kanat. Yüz kaputa, ortak yüz bölgesine oturur.
    /// Bilinçli olarak hiçbir markanın ayırt edici öğesini taşımaz (telif).
    private static func drawRaceCar(_ context: CGContext, _ u: CGFloat, state: SessionState) {
        // Lastikler (gövdenin arkasında).
        context.setFillColor(Palette.tire)
        for x in [9.5, 31.5] {
            context.addPath(CGPath(
                roundedRect: CGRect(x: x * u, y: 33 * u, width: 7 * u, height: 8.5 * u),
                cornerWidth: 2.4 * u,
                cornerHeight: 2.4 * u,
                transform: nil
            ))
        }
        context.fillPath()

        // Arka kanat: state renk dili buradan okunur (evdeki çatının karşılığı).
        if let roofGradient = Gradients.roof[state] {
            let wing = CGRect(x: 13 * u, y: 9.5 * u, width: 22 * u, height: 3 * u)
            context.saveGState()
            context.addPath(CGPath(roundedRect: wing, cornerWidth: 1.2 * u, cornerHeight: 1.2 * u, transform: nil))
            context.clip()
            context.drawLinearGradient(
                roofGradient,
                start: CGPoint(x: wing.minX, y: wing.minY),
                end: CGPoint(x: wing.maxX, y: wing.maxY),
                options: []
            )
            context.restoreGState()
        }
        // Kanat direkleri.
        context.setFillColor(Palette.tire)
        context.fill(CGRect(x: 18 * u, y: 12 * u, width: 1.6 * u, height: 3.5 * u))
        context.fill(CGRect(x: 28.4 * u, y: 12 * u, width: 1.6 * u, height: 3.5 * u))

        // Kabin (cam).
        let cabin = CGMutablePath()
        cabin.move(to: CGPoint(x: 15 * u, y: 25 * u))
        cabin.addLine(to: CGPoint(x: 17.5 * u, y: 15 * u))
        cabin.addQuadCurve(
            to: CGPoint(x: 30.5 * u, y: 15 * u),
            control: CGPoint(x: 24 * u, y: 13 * u)
        )
        cabin.addLine(to: CGPoint(x: 33 * u, y: 25 * u))
        cabin.closeSubpath()
        context.addPath(cabin)
        context.setFillColor(Palette.glass)
        context.fillPath()
        context.addPath(cabin)
        context.setStrokeColor(Palette.outline)
        context.setLineWidth(0.8 * u)
        context.strokePath()

        // Gövde: geniş, yumuşak köşeli kaput. Yüz (ortak bölge) bunun üstüne çizilir.
        let body = CGRect(x: 8.5 * u, y: 24 * u, width: 31 * u, height: 15.5 * u)
        let bodyPath = CGPath(roundedRect: body, cornerWidth: 5.5 * u, cornerHeight: 5.5 * u, transform: nil)
        let gradient = state == .limit ? Gradients.carMuted : Gradients.car
        if let gradient {
            context.saveGState()
            context.addPath(bodyPath)
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: body.midX, y: body.minY),
                end: CGPoint(x: body.midX, y: body.maxY),
                options: []
            )
            context.restoreGState()
        }
        context.addPath(bodyPath)
        context.setStrokeColor(Palette.outline)
        context.setLineWidth(0.8 * u)
        context.strokePath()
    }

    /// Roket: kapsül gövde, state-tint burun konisi ve yan kanatçıklar.
    /// Yüz gövdeye, ortak yüz bölgesine oturur.
    private static func drawRocket(_ context: CGContext, _ u: CGFloat, state: SessionState) {
        // Kanatçıklar (gövdenin arkasında).
        context.setFillColor(Palette.chimney)
        let leftFin = CGMutablePath()
        leftFin.move(to: CGPoint(x: 15.5 * u, y: 30 * u))
        leftFin.addLine(to: CGPoint(x: 9.5 * u, y: 41 * u))
        leftFin.addLine(to: CGPoint(x: 15.5 * u, y: 41 * u))
        leftFin.closeSubpath()
        context.addPath(leftFin)
        let rightFin = CGMutablePath()
        rightFin.move(to: CGPoint(x: 32.5 * u, y: 30 * u))
        rightFin.addLine(to: CGPoint(x: 38.5 * u, y: 41 * u))
        rightFin.addLine(to: CGPoint(x: 32.5 * u, y: 41 * u))
        rightFin.closeSubpath()
        context.addPath(rightFin)
        context.fillPath()

        // Gövde: altı düz, tepesi kubbeli kapsül.
        let bodyPath = CGMutablePath()
        bodyPath.move(to: CGPoint(x: 15 * u, y: 41 * u))
        bodyPath.addLine(to: CGPoint(x: 15 * u, y: 17 * u))
        bodyPath.addQuadCurve(to: CGPoint(x: 24 * u, y: 6.5 * u), control: CGPoint(x: 15 * u, y: 8.5 * u))
        bodyPath.addQuadCurve(to: CGPoint(x: 33 * u, y: 17 * u), control: CGPoint(x: 33 * u, y: 8.5 * u))
        bodyPath.addLine(to: CGPoint(x: 33 * u, y: 41 * u))
        bodyPath.closeSubpath()

        let gradient = state == .limit ? Gradients.bodyMuted : Gradients.body
        if let gradient {
            context.saveGState()
            context.addPath(bodyPath)
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 24 * u, y: 6.5 * u),
                end: CGPoint(x: 24 * u, y: 41 * u),
                options: []
            )
            // Burun konisi: state renk dili (evdeki çatının karşılığı).
            if let roofGradient = Gradients.roof[state] {
                let nose = CGMutablePath()
                nose.move(to: CGPoint(x: 15 * u, y: 15 * u))
                nose.addLine(to: CGPoint(x: 33 * u, y: 15 * u))
                nose.addLine(to: CGPoint(x: 33 * u, y: 6.5 * u))
                nose.addLine(to: CGPoint(x: 15 * u, y: 6.5 * u))
                nose.closeSubpath()
                context.saveGState()
                context.addPath(nose)
                context.clip()
                context.drawLinearGradient(
                    roofGradient,
                    start: CGPoint(x: 24 * u, y: 6.5 * u),
                    end: CGPoint(x: 24 * u, y: 15 * u),
                    options: []
                )
                context.restoreGState()
            }
            context.restoreGState()
        }
        context.addPath(bodyPath)
        context.setStrokeColor(Palette.outline)
        context.setLineWidth(0.8 * u)
        context.strokePath()
    }

    /// Yüz ölçeği: smiley'de kimlik iri yüzden gelir; diğer karakterlerde 1.
    private var faceScale: CGFloat {
        character == .smiley ? 1.5 : 1
    }

    /// Yüzün turntable dönüşüyle kaydığı ofset (2.5D); göz ve ağız birlikte döner.
    private func spinOffset(_ u: CGFloat) -> CGFloat {
        pose.spin * 3 * u
    }

    private func drawEyes(_ context: CGContext, _ u: CGFloat) {
        let scale = faceScale
        let openness = max(pose.eyeOpenness, 0.08)
        let eyeHeight = 4.6 * u * scale * openness
        context.setFillColor(Palette.eye)
        for centerX in [19.0, 29.0] {
            let x = centerX * u + pose.eyeLookX * 1.5 * u + spinOffset(u)
            let rect = CGRect(
                x: x - 2.3 * u * scale,
                y: 29 * u - eyeHeight / 2,
                width: 4.6 * u * scale,
                height: eyeHeight
            )
            context.fillEllipse(in: rect)
        }
        if pose.eyeOpenness > 0.3 {
            // Minik ışık yansıması gözü canlandırır.
            context.setFillColor(CGColor(gray: 1, alpha: 0.85))
            for centerX in [19.0, 29.0] {
                let x = centerX * u + pose.eyeLookX * 1.5 * u + spinOffset(u)
                let highlight = CGRect(
                    x: x - 1.6 * u * scale,
                    y: 29 * u - 1.6 * u * scale * openness,
                    width: 1.4 * u * scale,
                    height: 1.4 * u * scale
                )
                context.fillEllipse(in: highlight)
            }
        }
    }

    private func drawMouth(_ context: CGContext, _ u: CGFloat) {
        let scale = faceScale
        let center = CGPoint(x: 24 * u + spinOffset(u), y: 35.5 * u)
        switch state {
        case .done, .idle:
            let width: CGFloat = (state == .done ? 8 : 5) * u * scale
            let depth: CGFloat = (state == .done ? 4 : 2.5) * u * scale
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
        case .attention, .questioning:
            // Şaşkın/meraklı yuvarlak ağız; soruda biraz daha küçük.
            let radius = (state == .attention ? 1.75 : 1.4) * u
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
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

    /// working efekti karaktere göre ayrışır: ev tüter, fener ışık süpürür,
    /// roket alev püskürtür, yarış arabası egzoz atar.
    private func drawWorkingEffect(_ context: CGContext, _ u: CGFloat) {
        switch character {
        case .house: drawSmoke(context, u)
        case .lighthouse: drawLighthouseBeam(context, u)
        case .rocket: drawRocketFlame(context, u)
        case .raceCar: drawExhaust(context, u)
        case .statueOfLiberty: drawTorchSparkles(context, u)
        case .smiley: drawSweatDrop(context, u)
        case .robot: drawAntennaSignal(context, u)
        }
    }

    /// working (robot): antenden iki yana yayılan, yanıp sönen piksel sinyal noktaları.
    private func drawAntennaSignal(_ context: CGContext, _ u: CGFloat) {
        let tint = Palette.tint[state] ?? Palette.flameInner
        let positions: [(CGFloat, CGFloat)] = [(18, 9), (30, 9), (15, 13), (33, 13)]
        for (index, position) in positions.enumerated() {
            let phase = (time / 1.0 + Double(index) / Double(positions.count))
                .truncatingRemainder(dividingBy: 1)
            let alpha = phase < 0.5 ? phase * 2 : (1 - phase) * 2
            let side = 1.6 * u
            context.setFillColor(tint.copy(alpha: alpha * 0.85) ?? tint)
            context.fill(CGRect(
                x: position.0 * u - side / 2,
                y: position.1 * u - side / 2,
                width: side,
                height: side
            ))
        }
    }

    /// working (gülen yüz): şakaktan süzülüp kaybolan emoji-dili ter damlası.
    private func drawSweatDrop(_ context: CGContext, _ u: CGFloat) {
        let phase = (time / 1.6).truncatingRemainder(dividingBy: 1)
        let alpha = phase < 0.2 ? phase / 0.2 : 1 - (phase - 0.2) / 0.8
        let center = CGPoint(x: 36.5 * u, y: (20 + phase * 7) * u)
        let width = 3.2 * u
        let height = 4.4 * u
        // Damla: üstte sivri, altta yuvarlak.
        let drop = CGMutablePath()
        drop.move(to: CGPoint(x: center.x, y: center.y - height / 2))
        drop.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y + height / 2),
            control: CGPoint(x: center.x + width, y: center.y + height * 0.55)
        )
        drop.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y - height / 2),
            control: CGPoint(x: center.x - width, y: center.y + height * 0.55)
        )
        context.setFillColor(Palette.sweat.copy(alpha: alpha * 0.9) ?? Palette.sweat)
        context.addPath(drop)
        context.fillPath()
    }

    /// working (heykel): meşale çevresinde yanıp sönen piksel kıvılcımlar
    /// (stille uyum için daire değil kare).
    private func drawTorchSparkles(_ context: CGContext, _ u: CGFloat) {
        let tint = Palette.tint[state] ?? Palette.flameInner
        let positions: [(CGFloat, CGFloat)] = [(32, 4), (40, 7), (34, 11), (41, 2)]
        for (index, position) in positions.enumerated() {
            let phase = (time / 1.2 + Double(index) / Double(positions.count))
                .truncatingRemainder(dividingBy: 1)
            let alpha = phase < 0.5 ? phase * 2 : (1 - phase) * 2
            let side = 1.6 * u
            context.setFillColor(tint.copy(alpha: alpha * 0.85) ?? tint)
            context.fill(CGRect(
                x: position.0 * u - side / 2,
                y: position.1 * u - side / 2,
                width: side,
                height: side
            ))
        }
    }

    /// working (yarış arabası): iki yandan dışarı savrulan egzoz lokmaları.
    private func drawExhaust(_ context: CGContext, _ u: CGFloat) {
        for (index, side) in [-1.0, 1.0].enumerated() {
            for puff in 0..<2 {
                let phase = (time / 1.1 + Double(index) / 4 + Double(puff) / 2)
                    .truncatingRemainder(dividingBy: 1)
                let diameter = (2 + 3 * phase) * u
                let center = CGPoint(
                    x: (24 + side * (17 + phase * 7)) * u,
                    y: (38 - phase * 2 + sin(phase * 5 * .pi) * 0.8) * u
                )
                context.setFillColor(Palette.smoke.copy(alpha: (1 - phase) * 0.45) ?? Palette.smoke)
                context.fillEllipse(in: CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                ))
            }
        }
    }

    /// working (deniz feneri): fener odasından iki yana, yatay eksende süpüren
    /// çift ışık huzmesi (tam dönüş kule arkasında kaybolduğu için salınım tercih edildi).
    private func drawLighthouseBeam(_ context: CGContext, _ u: CGFloat) {
        let center = CGPoint(x: 24 * u, y: 10 * u)
        let sweep = sin(time * 2 * .pi / 2.4) * 0.35
        let spread = 0.16
        let radius = 16 * u
        context.setFillColor(Palette.beam)
        for direction in [0.0, Double.pi] {
            let angle = sweep + direction
            let wedge = CGMutablePath()
            wedge.move(to: center)
            wedge.addLine(to: CGPoint(
                x: center.x + cos(angle - spread) * radius,
                y: center.y + sin(angle - spread) * radius
            ))
            wedge.addLine(to: CGPoint(
                x: center.x + cos(angle + spread) * radius,
                y: center.y + sin(angle + spread) * radius
            ))
            wedge.closeSubpath()
            context.addPath(wedge)
        }
        context.fillPath()
    }

    /// working (roket): gövde altında titreşen alev + iki minik egzoz lokması.
    private func drawRocketFlame(_ context: CGContext, _ u: CGFloat) {
        let flicker = 0.7 + 0.3 * abs(sin(time * 2 * .pi / 0.18))
        let outerHeight = 6.5 * flicker * u
        context.setFillColor(Palette.flameOuter)
        context.fillEllipse(in: CGRect(
            x: 24 * u - 3.4 * u,
            y: 40.5 * u,
            width: 6.8 * u,
            height: outerHeight
        ))
        context.setFillColor(Palette.flameInner)
        context.fillEllipse(in: CGRect(
            x: 24 * u - 1.8 * u,
            y: 40.5 * u,
            width: 3.6 * u,
            height: outerHeight * 0.6
        ))
        for (index, offset) in [-5.5, 5.5].enumerated() {
            let phase = (time / 0.9 + Double(index) / 2).truncatingRemainder(dividingBy: 1)
            let diameter = (1.6 + 2 * phase) * u
            context.setFillColor(Palette.smoke.copy(alpha: (1 - phase) * 0.4) ?? Palette.smoke)
            context.fillEllipse(in: CGRect(
                x: (24 + offset + phase * offset * 0.6) * u - diameter / 2,
                y: (42 + phase * 3) * u - diameter / 2,
                width: diameter,
                height: diameter
            ))
        }
    }

    /// working (ev): bacadan düzenli aralıklarla yükselip dağılan duman lokmaları.
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

    /// questioning: karakterin tepesinde hafifçe süzülen, nefes alan "?" (ADR-015).
    private func drawQuestionMark(_ context: CGContext, _ u: CGFloat) {
        let anchor: CGPoint = {
            switch character {
            case .house: return CGPoint(x: 36, y: 10)
            case .lighthouse: return CGPoint(x: 34, y: 6)
            case .rocket: return CGPoint(x: 34, y: 7)
            case .raceCar: return CGPoint(x: 36, y: 10)
            // Meşale sağ üstte; "?" sol tarafta belirir.
            case .statueOfLiberty: return CGPoint(x: 8, y: 10)
            case .smiley: return CGPoint(x: 37, y: 12)
            case .robot: return CGPoint(x: 37, y: 11)
            }
        }()
        let bob = sin(time * 2 * .pi / 2.0)
        let fontSize = (7 + 0.5 * bob) * u
        let tint = Palette.tint[state].flatMap(NSColor.init(cgColor:)) ?? .systemTeal
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) }
        let text = NSAttributedString(
            string: "?",
            attributes: [
                .font: rounded ?? font,
                .foregroundColor: tint.withAlphaComponent(0.9),
            ]
        )
        text.draw(at: CGPoint(
            x: anchor.x * u - fontSize * 0.3,
            y: (anchor.y + bob * 0.8) * u - fontSize * 0.6
        ))
    }

    /// limit: karakterin tepesinden süzülüp kaybolan zZz harfleri.
    private func drawSleepZs(_ context: CGContext, _ u: CGFloat) {
        // Başlangıç noktası ve yükselme payı karakter siluetine göre seçilir
        // (uzun karakterlerde harfler tuvalin dışına taşmasın).
        let (anchor, rise): (CGPoint, CGFloat) = {
            switch character {
            case .house: return (CGPoint(x: 35, y: 14), 12)
            case .lighthouse: return (CGPoint(x: 34, y: 9), 7)
            case .rocket: return (CGPoint(x: 34, y: 10), 8)
            case .raceCar: return (CGPoint(x: 35, y: 13), 11)
            // Sağ üst meşalenin olduğu yer; zZz sol taraftan süzülür.
            case .statueOfLiberty: return (CGPoint(x: 6, y: 14), 9)
            case .smiley: return (CGPoint(x: 36, y: 15), 11)
            case .robot: return (CGPoint(x: 36, y: 14), 10)
            }
        }()
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
                x: (anchor.x + phase * 5) * u - fontSize * 0.3,
                y: (anchor.y - phase * rise) * u - fontSize * 0.6
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

/// Testler ve görsel doğrulama için: bir karakter×state karesini PNG'ye çizer.
/// UI hiyerarşisi kurmadan renderer'ın tüm kombinasyonlarda çıktı ürettiğini kanıtlar.
enum MascotSnapshot {
    static func png(
        character: MascotCharacter,
        state: SessionState,
        size: Int = 96,
        time: TimeInterval = 0.9
    ) -> Data? {
        guard let bitmap = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        bitmap.translateBy(x: 0, y: CGFloat(size))
        bitmap.scaleBy(x: 1, y: -1)

        let renderer = MascotRenderer(
            state: state,
            character: character,
            pose: MascotPose(state: state, time: time, timeSinceStateChange: time),
            time: time
        )
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: true)
        renderer.draw(in: bitmap, size: CGSize(width: size, height: size))
        NSGraphicsContext.current = previous

        guard let image = bitmap.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
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

#Preview("Karakterler") {
    VStack(spacing: 12) {
        ForEach(MascotCharacter.allCases) { character in
            HStack(spacing: 16) {
                ForEach(SessionState.allCases, id: \.self) { state in
                    PlaceholderMascotView(state: state, character: character)
                        .frame(width: 48, height: 48)
                }
            }
        }
    }
    .padding()
}
