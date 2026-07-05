# PHASES.md — Faz Faz Uygulama Planı

Kural: Bir faz "Bitti sayılır" kriterlerinin TAMAMINI geçmeden sonrakine geçilmez.
Her fazın sonunda commit at. Claude Code'a verilecek örnek prompt her fazın altında.
(Promptlar başlangıç noktasıdır; kendi kelimelerinle genişlet, ama kapsamı genişletme.)

---

## Faz 0 — Proje iskeleti (yarım gün)

**Hedef:** Boş ama derlenen, doğru yapılandırılmış Xcode projesi.

**İşler:**
- Xcode'da macOS App (SwiftUI) projesi: `AgentHouse`, minimum macOS 14.0.
- `LSUIElement = YES` (Dock'ta görünmeyen menü bar uygulaması).
- App Sandbox kapalı, Hardened Runtime açık.
- CLAUDE.md, DECISIONS.md, PHASES.md, PLAN.md repo köküne konur. Git init + ilk commit.
- CLAUDE.md'deki klasör yapısı boş dosyalarla oluşturulur.

**Bitti sayılır:**
- [ ] Uygulama derleniyor ve çalışınca Dock'ta İKON YOK, menü barda geçici bir ikon VAR.
- [ ] Klasör yapısı CLAUDE.md ile birebir aynı.

**Örnek prompt:**
> CLAUDE.md'yi oku. Faz 0'ı uygula: LSUIElement=YES olan, App Sandbox kapalı,
> Hardened Runtime açık bir SwiftUI macOS menü bar uygulaması iskeleti kur.
> CLAUDE.md'deki klasör yapısını oluştur. Menü barda şimdilik sistem ikonu göster.

---

## Faz 1 — Overlay panel iskeleti (2-3 gün)

**Hedef:** Şeffaf, her zaman önde, odak çalmayan, sürüklenebilir boş panel.

**İşler:**
- `OverlayPanel: NSPanel` — `.nonactivatingPanel` stili, `level = .floating`,
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`,
  `isOpaque = false`, `backgroundColor = .clear`, gölgesiz.
- İçine `NSHostingView` ile `OverlayRootView` (SwiftUI) yerleştir.
- Panel sürüklenebilir; pozisyon UserDefaults'a kaydedilir, açılışta geri yüklenir.
- Menü bar ikonundan panel göster/gizle.

**Bitti sayılır:**
- [ ] Panel her uygulamanın (tam ekran dahil) üstünde duruyor.
- [ ] Panele tıklamak aktif uygulamanın odağını ÇALMIYOR (arkadaki uygulamada yazı yazmaya devam edilebiliyor).
- [ ] Sürükle-bırak sonrası pozisyon, uygulama yeniden açılınca korunuyor.

**Örnek prompt:**
> Faz 1: Core/UI ayrımına uyarak nonactivating bir NSPanel oluştur. .floating level,
> tüm space'lerde görünür, şeffaf arka plan. İçine SwiftUI OverlayRootView koy
> (şimdilik yarı saydam yuvarlatılmış bir dikdörtgen). Sürüklemeyi ve pozisyonun
> UserDefaults'ta saklanmasını ekle. Menü bar ikonuna göster/gizle bağla.

---

## Faz 2 — Hook boru hattı (3-4 gün) ★ projenin kalbi

**Hedef:** Claude Code'da olan her şeyin uygulamaya JSON olarak akması.

**İşler:**
- `EventServer`: NWListener, sadece 127.0.0.1, port UserDefaults'tan (varsayılan 48756).
  POST /event gövdesini alır, `HookEvent` modeline decode eder, Combine publisher'a basar.
- `HookEvent`: hook_event_name, session_id, cwd, tool_name, message vb. alanlar —
  hepsi optional, savunmacı decode (bilinmeyen alanlar yok sayılır).
- `HookInstaller`: `~/.claude/settings.json`'ı okur, YEDEK alır, SessionStart,
  UserPromptSubmit, PreToolUse, PostToolUse, Notification, Stop, SessionEnd için
  `curl -s --max-time 1 -X POST http://127.0.0.1:48756/event -H 'Content-Type: application/json' -d @- || true`
  komutlarını merge eder. `uninstall()` sadece kendi girdilerini kaldırır.
- Uygulama içinde geçici bir "Event Log" debug penceresi: gelen her event bir satır.

**Bitti sayılır:**
- [ ] Terminalde `claude` başlatıp bir prompt verince debug penceresinde SessionStart → UserPromptSubmit → PreToolUse... akıyor.
- [ ] VS Code içindeki Claude Code'dan da aynı eventler geliyor.
- [ ] Uygulama KAPALIYKEN Claude Code normal çalışıyor (hiç takılma yok).
- [ ] Uninstall sonrası settings.json, kurulum öncesiyle eşdeğer.
- [ ] Bozuk/eksik JSON gönderildiğinde uygulama crash olmuyor, logluyor.

**Örnek prompt:**
> Faz 2: CLAUDE.md'deki kurallara uyarak EventServer (NWListener, sadece loopback),
> savunmacı decode'lu HookEvent modeli ve yedek alan/merge eden/geri alabilen
> HookInstaller'ı yaz. Hook komutları --max-time 1 ve || true içermeli. Gelen
> eventleri gösteren geçici bir debug listesi ekle. HookInstaller ve HookEvent
> decode için unit test yaz.

---

## Faz 3 — State machine + SessionManager (3-4 gün)

**Hedef:** Event akışının, oturum başına doğru state'e dönüşmesi.

**İşler:**
- `SessionState` enum: idle, working, attention, done, limit (+ stale bayrağı).
- `SessionStateMachine.apply(event:)` — CLAUDE.md'deki eşleme tablosu birebir.
  done → 5 sn sonra idle (Timer). attention → sonraki PreToolUse'ta working
  ("terminalden cevaplandı" senkronizasyonu).
- `SessionManager: ObservableObject` — session_id → Session sözlüğü; cwd'den proje
  adı türetme (son klasör adı); SessionEnd'de kaldırma; 30 dk inaktivitede stale.
- Debug penceresi artık oturumları ve canlı state'lerini gösterir.

**Bitti sayılır:**
- [ ] İki farklı klasörde iki Claude oturumu açınca iki ayrı oturum, doğru proje adlarıyla görünüyor.
- [ ] İzin isteyen bir komutta state `attention` oluyor; terminalden onaylayınca `working`a dönüyor.
- [ ] İş bitince `done`, 5 sn sonra `idle`.
- [ ] StateMachine unit testleri tüm geçişleri kapsıyor (event sıraları senaryo olarak test edilir).

**Örnek prompt:**
> Faz 3: SessionState, SessionStateMachine ve SessionManager'ı CLAUDE.md'deki hook
> eşleme tablosuna göre yaz. Geçişler yalnızca apply(event:) içinde. done→idle
> 5 sn gecikmesi ve attention→working senkronizasyonu dahil. Her geçiş için
> senaryo bazlı unit test yaz (örn. start→prompt→tool→notification→tool→stop).

---

## Faz 4 — Kart UI (3-4 gün)

**Hedef:** Panelde gerçek verili, şık oturum kartları.

**İşler:**
- `SessionCardView`: proje adı, state etiketi/rengi, maskot alanı (şimdilik boş daire),
  son aktivite göstergesi. Kartlar HStack'te; oturum gelince/gidince yumuşak
  insert/remove animasyonu.
- State renk dili: idle=nötr, working=mavi/mor, attention=amber (dikkat çekici puls),
  done=yeşil, limit=gri/uyku.
- Panel boyutu kart sayısına göre otomatik büyür/küçülür.
- Debug penceresi kaldırılır (ayarlarda gizli "debug log" seçeneğine taşınır).

**Bitti sayılır:**
- [ ] 1, 2 ve 3 eşzamanlı oturum senaryolarında panel düzgün diziliyor ve boyutlanıyor.
- [ ] attention state'i göz ucuyla fark ediliyor (puls animasyonu).
- [ ] Kart eklenme/çıkma animasyonları takılmasız.

**Örnek prompt:**
> Faz 4: SessionManager'a bağlı SessionCardView'ları OverlayRootView içinde HStack
> ile göster. State başına renk ve etiket; attention için hafif puls animasyonu;
> kart ekleme/çıkarma için spring animasyon. Panel içerik boyutuna göre yeniden
> boyutlansın. Maskot için şimdilik 48x48 boş bir placeholder alan bırak.

---

## Faz 5 — Maskot (1-2 hafta; tasarım + entegrasyon)

**Hedef:** TEK maskot, 5 state'e 5 animasyon, "2D ama 3D hissiyatlı".

**İşler:**
- Karakter tasarımı (Rive editöründe): basit silüet, 2-3 renk, okunaklı 48-64px'de.
  3D hissi: katmanlı gölge/derinlik, hafif perspektif — render değil çizim hilesi.
- Rive state machine: idle (nefes/etrafa bakma), working (hızlı yazma/koşturma),
  attention (el sallama/zıplama), done (kutlama, tek seferlik), limit (uyku, zZz).
- `MascotAnimating` protokolü + `RiveMascotView` implementasyonu (rive-ios SPM).
- Rive'da beklenmedik engel çıkarsa: `PlaceholderMascotView`'ı SwiftUI keyframe
  animasyonlarıyla zenginleştir ve Rive'ı ertele (kritik yolu bloklamaz — ADR-009).

**Bitti sayılır:**
- [ ] 5 state'in 5'inde de maskot doğru animasyona ANINDA geçiyor.
- [ ] Panel gizliyken animasyon durduruluyor (CPU ölçümüyle doğrula).
- [ ] Animasyon oynarken CPU < %3 (Activity Monitor).

**Örnek prompt (entegrasyon kısmı için):**
> Faz 5: rive-ios'u SPM ile ekle. MascotAnimating protokolünü ve state→Rive input
> eşlemesi yapan RiveMascotView'ı yaz; SessionCardView'daki placeholder'ı değiştir.
> Panel gizlendiğinde animasyonların durdurulmasını sağla.

---

## Faz 6 — Bildirimler: done banner + limit (3 gün)

**Hedef:** "İş bitti" anının hissedilmesi; limit durumunun net gösterimi.

**İşler:**
- `DoneBanner`: uzun süren iş (working süresi > eşik, örn. 30 sn) bitince kartın
  altından spring animasyonla sarkan, proje adını söyleyen, birkaç saniye sonra
  toplanan bildirim. Tıklanınca ilgili karta/terminale gider (Faz 8 ile birleşir).
- Limit tespiti: UsageReader'dan (Faz 7 ile paralel) veya Notification içeriğinden;
  tespit edilince kart `limit`, maskot uykuda, kartta "~HH:mm'de sıfırlanır" metni
  (oturumun 5 saatlik penceresinin başlangıcından lokal hesap).
- İsteğe bağlı macOS sistem bildirimi (UNUserNotificationCenter) — ayarlardan aç/kapa.

**Bitti sayılır:**
- [ ] 30 sn'den uzun bir Claude işinin sonunda banner yay efektiyle düşüyor ve kendiliğinden toplanıyor.
- [ ] Limit senaryosunda (simüle edilebilir) kart limit görünümüne geçiyor ve saat gösteriyor.
- [ ] Kısa işlerde (< eşik) banner ÇIKMIYOR (bildirim yorgunluğu yok).

---

## Faz 7 — Lokal usage (JSONL) (3-4 gün)

**Hedef:** Oturum başına token ve tahmini maliyet, tamamen lokal.

**İşler:**
- `UsageReader`: `~/.claude/projects/**/*.jsonl` — aktif oturumların dosyalarını
  `DispatchSource` ile izle, SADECE yeni eklenen satırları oku (FileHandle offset),
  her satırı savunmacı decode et (usage alanları: input/output/cache token).
- Model adına göre yaklaşık maliyet tablosu (sabit, "tahmini ~" etiketiyle gösterilir).
- Kartta kompakt gösterim: `42K tok · ~$1.80`. Menü bar popover'ında oturum dökümü.
- Rate-limit izi görürse SessionManager'a limit sinyali (Faz 6 ile bağlanır).

**Bitti sayılır:**
- [ ] Aktif bir oturumda token sayısı Claude çalıştıkça artıyor.
- [ ] 10 MB'lık bir JSONL dosyasıyla test: okuma artımlı, RAM şişmiyor, dosyanın tamamı her seferinde okunmuyor.
- [ ] `~/.claude` klasörü hiç olmayan bir makinede uygulama sorunsuz (usage alanı gizli).
- [ ] UsageReader unit testli (örnek JSONL fixture'larıyla).

---

## Faz 8 — Tıkla→terminale git + Menü bar + Ayarlar (3-4 gün)

**Hedef:** v1.0 özellik setinin tamamlanması.

**İşler:**
- `TerminalFocuser`: SessionStart payload'ından kaynak uygulamayı belirle
  (Terminal/iTerm/VS Code vb. — bundle id tespiti), karta tıklanınca
  NSRunningApplication.activate ile öne getir. Kesin pencere eşleşmesi garanti
  edilemiyorsa en azından doğru UYGULAMAYI öne getir (v1.0 için yeterli — dürüst
  davran, README'ye yaz).
- Menü bar popover: aktif oturum özeti, usage dökümü, panel göster/gizle,
  Ayarlar, Çıkış.
- SettingsView: port, panel köşesi/pozisyon sıfırlama, done-banner eşiği,
  sistem bildirimi aç/kapa, hook kur/kaldır butonları, "Login'de başlat"
  (SMAppService).
- Onboarding: ilk açılışta tek ekran — "Hook'ları kur" butonu + ne yaptığının
  şeffaf açıklaması.

**Bitti sayılır:**
- [ ] Karta tıklayınca ilgili terminal/VS Code öne geliyor.
- [ ] Hook kur/kaldır ayarlardan tek tıkla çalışıyor; kaldırma sonrası settings.json temiz.
- [ ] "Login'de başlat" çalışıyor.
- [ ] Uygulamayı hiç bilmeyen biri onboarding'i okuyup 1 dakikada kurabiliyor (arkadaşında test et).

---

## Faz 9 — Cila, paketleme, lansman (1 hafta)

**Hedef:** Yabancı birinin indirdiğinde sorunsuz kullandığı, imzalı ürün.

**İşler:**
- Performans turu: Instruments ile RAM/CPU ölçümü, PLAN.md bütçesine uygunluk.
- Edge-case turu: uygulama açıkken Mac uykuya girip uyanınca; port çakışması;
  Claude Code güncellenmiş/hiç kurulmamışken; 5+ eşzamanlı oturum.
- Uygulama ikonu + son görsel dokunuşlar.
- Developer ID ile imzala, `xcrun notarytool` ile notarize et, staple et, .dmg üret.
- README (kurulum, hook şeffaflığı, uninstall), landing page (tek sayfa + demo GIF).
- Lansman: r/ClaudeAI postu, X thread'i (build-in-public özetiyle), Product Hunt.

**Bitti sayılır:**
- [ ] Temiz bir Mac'te (veya yeni kullanıcı hesabında) .dmg indirilip Gatekeeper uyarısı OLMADAN açılıyor.
- [ ] PLAN.md lansman kontrol listesinin tamamı işaretli.
- [ ] En az 2 dış test kullanıcısı bir hafta sorunsuz kullandı.

---

## Faz sırası neden böyle (özet mantık)

Kritik belirsizlik önce: Faz 1-2 (panel davranışı + hook akışı) projenin "olur mu?"
sorusudur; ikisi çalıştığı an geri kalanı emek meselesidir. Maskot (en keyifli kısım)
bilerek ortada: iskelet olmadan maskota başlamak, motoru olmayan arabaya boya yapmaktır.
Usage ve odaklama sona yakın: bağımsız modüllerdir, kritik yolu bloklamaz.