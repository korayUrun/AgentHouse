# CLAUDE.md — AgentHouse

Bu dosya Claude Code için proje bağlamıdır. Her oturumda bu kurallara uy.

## Proje nedir

AgentHouse: Claude Code oturumlarını izleyen, macOS'ta her zaman önde duran şeffaf
bir overlay panelde her oturumu proje adıyla bir kart olarak gösteren, oturum
state'ini (idle / working / attention / done / limit) tek bir maskot animasyonuyla
yansıtan, tamamen lokal (stateless) bir menü bar uygulaması.

**Gözlem-only:** Bu uygulama Claude Code'a HİÇBİR ŞEY GÖNDERMEZ, hiçbir hook'ta
karar döndürmez, izin onaylamaz. Sadece dinler ve gösterir.

## Kesin kurallar (ihlal etme)

1. **Ağ:** `127.0.0.1` dışına HİÇBİR network isteği yazma. Analytics, telemetri,
   crash reporter, update check — hiçbiri yok. Tek network noktası: EventServer'ın
   localhost listener'ı.
2. **Veri:** Kullanıcı verisi diske YAZILMAZ. Sadece `UserDefaults` ile UI ayarları
   (panel pozisyonu, port, tema tercihi) saklanır. `~/.claude` altındaki dosyalar
   SALT-OKUNUR açılır.
3. **Hook güvenliği:** `~/.claude/settings.json`'a yazan kod (HookInstaller) mevcut
   içeriği ASLA silmez/ezmez — parse et, kendi hook girdilerini merge et, geri yaz.
   Yazmadan önce `settings.json.agenthouse-backup` yedeği al. Uninstall fonksiyonu
   sadece kendi eklediklerini kaldırır.
4. **Hook komutları bloklamaz:** settings.json'a eklenen her hook komutu
   `--max-time 1` ile curl kullanır ve `|| true` ile biter. Uygulama kapalıyken
   Claude Code'un çalışması etkilenmemeli.
5. **Kapsam:** PLAN.md'deki v1.0 listesi dışına ÇIKMA. "Şunu da ekleyeyim" yok.
   Yeni fikirler DECISIONS.md'ye "ertelendi" olarak not edilir.
6. **Maskot karakterleri (ADR-014):** Birden fazla karakter desteklenir; animasyon
   beyni (`MascotPose`) tüm karakterlerde ORTAKTIR — yeni karakter yalnızca çizim
   ekler, state fiziğine karakter özel kod yazılmaz. Seçim proje bazlıdır: yeni
   proje varsayılan karakterle başlar, kullanıcı değiştirirse tercih projeye
   (cwd → karakter, UserDefaults) kaydedilir.

## Teknoloji ve sürümler

- Swift 5.10+, SwiftUI + AppKit köprüsü. Minimum deployment: macOS 14.0.
- Xcode projesi, SPM ile bağımlılık. İzinli bağımlılıklar: `rive-ios` (Faz 5+).
  Başka üçüncü parti kütüphane eklemeden önce SOR.
- App Sandbox: KAPALI (App Store'a gitmiyoruz; ~/.claude erişimi gerekli).
  Hardened Runtime: AÇIK (notarization için).

## Mimari ve klasör yapısı

```
AgentHouse/
├── App/            AgentHouseApp.swift, AppDelegate.swift
├── Core/
│   ├── Events/     HookEvent.swift (payload modelleri), EventServer.swift
│   ├── State/      SessionState.swift (enum), SessionStateMachine.swift,
│   │               SessionManager.swift (ObservableObject, tek doğruluk kaynağı)
│   ├── Usage/      UsageReader.swift (JSONL parser), UsageModel.swift
│   ├── Install/    HookInstaller.swift
│   └── Focus/      TerminalFocuser.swift
├── UI/
│   ├── Overlay/    OverlayPanel.swift (NSPanel), OverlayRootView.swift,
│   │               SessionCardView.swift, DoneBanner.swift
│   ├── Mascot/     MascotAnimating.swift (protokol), PlaceholderMascotView.swift,
│   │               RiveMascotView.swift (Faz 5)
│   └── MenuBar/    MenuBarController.swift, SettingsView.swift
└── Tests/          Core katmanının unit testleri (UI testi zorunlu değil)
```

- Veri akışı tek yönlü: `EventServer → SessionManager → StateMachine → @Published → UI`.
- UI katmanı Core'a bağımlıdır; Core, UI'dan hiçbir şey import etmez.
- State geçişleri SADECE `SessionStateMachine.apply(event:)` içinde yapılır.

## Claude Code hook eşlemesi (davranışın kaynağı)

| Hook | Anlamı bizde |
|---|---|
| SessionStart | Yeni kart (idle). Payload'daki cwd'den proje adı türet. |
| UserPromptSubmit | working |
| PreToolUse / PostToolUse | working (lastActivity güncelle) |
| Notification | attention (izin veya input bekliyor) |
| Stop | done → 5 sn sonra idle |
| SessionEnd | kartı kaldır |

Limit tespiti: UsageReader JSONL'de rate-limit izini görürse veya Notification
içeriği limit belirtiyorsa `limit` state + reset tahmini (5 saatlik pencere
başlangıcından hesapla). Bu tespit best-effort'tur; emin değilsen state'i bozma.

## Kod stili

- SwiftLint kurallarına yakın temiz Swift; zorlama kısaltma yok, açık isimlendirme.
- Her public tipe bir cümlelik doc comment.
- Hata yönetimi: Core'da `throws` / `Result`; UI'da asla crash — bozuk payload'ı
  logla ve yok say. `fatalError` yasak (yalnızca programlama hatası assert'leri).
- Loglama: `os.Logger`, subsystem `com.agenthouse.app`. print() bırakma.
- Test: StateMachine ve UsageReader %100'e yakın unit test kapsamı; UI için gerekmiyor.
- Lokalizasyon (Faz 8.5+): kullanıcıya görünür HER string `App/Localizable.xcstrings`
  kataloğundan geçer — temel dil İngilizce, tam Türkçe çeviri. SwiftUI literal'ları
  otomatik; `String` gereken yerde `String(localized:)`. Yeni anahtar eklerken
  kataloğa tr çevirisini de ekle.

## Mühendislik ilkeleri

**Asenkron programlama:**
- Paylaşılan mutable state ya TEK bir seri `DispatchQueue`'ya ya da bir aktöre
  hapsedilir; kilitsiz "umarım çakışmaz" kodu yazılmaz.
- UI'a çıkan her veri ana thread'de teslim edilir (`receive(on: .main)` /
  `@MainActor`). Ana thread'de bloklayan iş (dosya, ağ, parse) yapılmaz.
- Callback tabanlı sistem API'leri (NWListener, DispatchSource) ince sarmalayıcı
  tiplerde izole edilir; dışarıya Combine publisher veya async arayüz verilir.

**SOLID:**
- **S** — Her tip tek iş yapar: EventServer taşır, StateMachine karar verir,
  SessionManager tutar, View gösterir. "Bir de şunu yapsın" denen an tip bölünür.
- **O/D** — Katmanlar somut tiplere değil protokollere bağlanır (`MascotAnimating`
  gibi). Bağımlılıklar init'ten enjekte edilir (URL, port, timer/saat) — testte
  gerçek dosya sistemi/saat yerine sahtesi geçirilebilmeli.
- **L** — Bir protokolü uygulayan tip, sözleşmenin beklentisini daraltamaz.
- **I** — Şişman protokol yok; kullanıcısının ihtiyacı kadar arayüz.

**Genel:**
- KISS ve YAGNI (kural 5 ile aynı ruh): en basit doğru çözüm; "ileride lazım olur"
  diye soyutlama/altyapı yazılmaz.
- DRY: aynı bilgi iki yerde yaşamaz (örn. hook komutu tek yerde üretilir).
- Karar veren kod (state geçişi, parse) saf fonksiyon olarak yazılır (girdi→çıktı,
  yan etkisiz) ki tek başına unit test edilebilsin; yan etkiler kenarlara itilir.

## Çalışma şekli

- Her fazın sonunda PHASES.md'deki "Bitti sayılır" kriterlerini kontrol et.
- Mimari bir karar değiştireceksen ÖNCE DECISIONS.md'ye yeni kayıt öner, onay iste.
- Commit mesajları: `faz2: EventServer NWListener implementasyonu` formatında.