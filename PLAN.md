# AgentHouse — Master Proje Planı

> Geçici isim: **AgentHouse** (lansmandan önce marka kontrolü yapılacak, "Claude" kelimesi isimde GEÇMEYECEK).
> Sürüm hedefi: **v1.0 — tek sürüm, tek maskot, gözlem-only.**
> Platform: **Sadece macOS** (Apple Silicon + Intel, macOS 14+).
> Dağıtım: App Store DIŞI — Developer ID ile imzalı + notarize edilmiş .dmg.

---

## 1. Vizyon (tek cümle)

Claude Code kullanan geliştiricinin, terminale bakmadan — YouTube izlerken bile —
ekranın köşesindeki şık bir çerçeveden Claude'un o an ne durumda olduğunu
(bekliyor / çalışıyor / cevap bekliyor / bitti / limit doldu) tatlı bir maskot
animasyonuyla görmesini sağlayan, tamamen lokal çalışan macOS uygulaması.

## 2. Hedef kullanıcı

- Claude Code'u terminalde veya VS Code içinde yoğun kullanan geliştiriciler.
- Aynı anda birden fazla projede Claude oturumu çalıştıran power user'lar.
- Terminal çıktısını takip etmek yerine göz ucuyla durum görmek isteyen herkes.

## 3. Kapsam — v1.0'da OLANLAR (kesin liste, büyümez)

| # | Özellik | Açıklama |
|---|---------|----------|
| 1 | Floating overlay panel | Şeffaf, her zaman önde, odak çalmayan NSPanel. Köşe seçilebilir, sürüklenebilir. |
| 2 | State takibi | Hook tabanlı 5 durum: `idle`, `working`, `attention`, `done`, `limit`. |
| 3 | Maskot animasyonları | TEK maskot. Her state için ayrı animasyon (Rive; ilk fazlarda SwiftUI placeholder). |
| 4 | Çoklu proje kartları | Her Claude oturumu = proje adıyla bir kart. Kartlar panelde yan yana. |
| 5 | Limit bildirimi + reset sayacı | Limit dolunca maskot uyur, kartta tahmini reset saati (lokal hesap). |
| 6 | İş bitti bildirimi | Uzun görev bitince spring animasyonlu bildirim düşer. |
| 7 | Tıkla → terminale git | Karta tıklayınca ilgili terminal/VS Code penceresi öne gelir. |
| 8 | Menü bar ikonu | Panel aç/kapa, ayarlar, aktif oturum özeti, çıkış. |
| 9 | Lokal usage gösterimi | `~/.claude/projects` JSONL loglarından oturum başına token + tahmini maliyet. |

## 4. Kapsam DIŞI (v1.0'da kesinlikle YOK — bkz. DECISIONS.md)

- Panelden Claude'a cevap verme / izin onaylama (etkileşim yok, salt gözlem).
- Panelden prompt gönderme.
- Gemini / Codex / diğer araç adapter'ları (mimari hazır, implementasyon yok).
- Birden fazla maskot, tema mağazası.
- Windows / Linux.
- Anthropic hesabına bağlanıp resmi limit yüzdesi çekme (usage tamamen lokal).
- Her türlü ağ isteği (localhost hariç), telemetri, analytics, veri toplama.

## 5. Mimari genel bakış

```
Claude Code (terminal veya VS Code)
      │  hook eventleri (SessionStart, UserPromptSubmit,
      │  PreToolUse, PostToolUse, Notification, Stop, SessionEnd)
      ▼
hook komutu: curl -s --max-time 1 -X POST http://127.0.0.1:48756/event -d @-
      │  (uygulama kapalıysa sessizce başarısız olur, Claude Code'u ASLA bloklamaz)
      ▼
┌───────────────────────── AgentHouse.app ─────────────────────────┐
│  EventServer (Network.framework NWListener, sadece 127.0.0.1)    │
│        ▼                                                         │
│  SessionManager  ── oturum başına ──►  SessionStateMachine       │
│        │                                (idle→working→attention  │
│        │                                 →done→idle, +limit)     │
│        ▼                                                         │
│  UsageReader (JSONL parser, ~/.claude/projects, salt-okunur)     │
│        ▼                                                         │
│  OverlayPanel (NSPanel + SwiftUI)  ◄── ObservableObject store    │
│  ├── SessionCard × N (proje adı, state, usage, reset sayacı)     │
│  ├── MascotView (Rive state machine / placeholder)               │
│  └── DoneNotificationBanner (spring animasyon)                   │
│  MenuBarController (NSStatusItem + popover ayarlar)              │
│  HookInstaller (~/.claude/settings.json güvenli merge)           │
│  TerminalFocuser (NSRunningApplication ile pencere odaklama)     │
└──────────────────────────────────────────────────────────────────┘
```

Veri akışı tek yönlü: Event → StateMachine → Store → UI. UI asla state üretmez.

## 6. State makinesi (oturum başına)

| Tetikleyici (hook) | Geçiş |
|---|---|
| SessionStart | kart oluştur → `idle` |
| UserPromptSubmit | → `working` |
| PreToolUse / PostToolUse | `working` (aktivite tazele) |
| Notification (izin/input isteği) | → `attention` |
| Notification sonrası PreToolUse | `attention` → `working` (kullanıcı terminalden cevapladı) |
| Stop | → `done` (5 sn sonra otomatik → `idle`) |
| Limit tespiti (JSONL'de rate-limit izi / özel Notification) | → `limit` + reset sayacı |
| SessionEnd | kartı kaldır (fade-out) |
| 30 dk hiç event yok | kartı "stale" işaretle, soluklaştır |

## 7. Teknoloji seçimleri (gerekçeler DECISIONS.md'de)

- **Dil/UI:** Swift 5.10+, SwiftUI (panel içeriği) + AppKit (NSPanel, NSStatusItem).
- **Sunucu:** Network.framework `NWListener`, sadece `127.0.0.1:48756` (port ayarlanabilir).
- **Animasyon:** Rive (rive-ios, macOS destekli). Faz 1-4'te SwiftUI placeholder animasyon.
- **Usage:** JSONL dosyalarını `FileHandle` ile artımlı okuma + `DispatchSource` dosya izleme.
- **Persistans:** YOK. Ayarlar için sadece `UserDefaults`. Kullanıcı verisi hiçbir yere yazılmaz.
- **Paketleme:** Xcode → Developer ID sertifikası → notarization → .dmg (create-dmg).

## 8. Performans bütçesi (uygulamanın satış vaadi "hafif")

- RAM < 80 MB, boşta CPU ~%0, animasyon oynarken CPU < %3.
- Enerji etkisi: "Low". Panel gizliyken animasyonlar durur.
- Uygulama boyutu < 25 MB.

## 9. Riskler ve B planları

| Risk | Olasılık | B planı |
|---|---|---|
| Hook şeması Claude Code güncellemesiyle değişir | Orta | Adapter katmanı tek dosyada; payload'ı savunmacı parse et, bilinmeyen alanları yok say; hızlı patch çıkar |
| Rive macOS runtime'ında sürpriz | Düşük-Orta | Placeholder SwiftUI animasyon zaten Faz 5'e kadar ana yol; gerekirse Lottie'ye geç |
| Limit tespiti güvenilmez çıkar | Orta | "Best-effort" olarak işaretle; tespit edilemezse state'i bozmadan sadece göstermemeye devam et |
| Anthropic native companion çıkarır | Orta | Kabul edilmiş risk; proje CV/öğrenme değeri taşımaya devam eder |
| Notarization süreci ilk kez yapana sancılı | Yüksek | Faz 9'da tam gün ayrıldı; xcrun notarytool akışı adım adım PHASES.md'de |

## 10. Zaman tahmini (okul yanında, haftada ~10-12 saat)

- Faz 0-2 (iskelet + boru hattı): 1.5 hafta
- Faz 3-4 (state machine + kartlar): 1.5 hafta
- Faz 5 (maskot): 1-2 hafta (tasarım dahil)
- Faz 6-8 (bildirimler, usage, menü bar, odaklama): 2 hafta
- Faz 9 (cila + paketleme + lansman): 1 hafta
- **Toplam: ~7-8 hafta.**

## 11. Lansman kontrol listesi (Faz 9 sonu)

- [ ] İsim finalize + basit landing page (tek sayfa, GIF demo şart)
- [ ] Developer ID imza + notarization tamam, Gatekeeper uyarısız açılıyor
- [ ] README: kurulum, hook'ların ne yaptığı, kaldırma (uninstall) adımları ŞEFFAF yazılmış
- [ ] "Verileriniz makinenizden çıkmaz" iddiası kodda doğrulanabilir (tek network noktası: localhost)
- [ ] r/ClaudeAI + X (build in public zinciri) + Product Hunt lansmanı
- [ ] GitHub repo public (açık kaynak — dağıtım ve güven stratejimizin parçası)