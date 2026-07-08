# DECISIONS.md — Mimari Karar Kayıtları (ADR)

Format: her karar numaralı, tarihli, durumu belli. Karar değişirse eski kayıt
silinmez, "superseded by ADR-XX" olarak işaretlenir.

---

## ADR-001 — Sadece macOS
**Durum:** Kabul edildi.
**Karar:** v1.0 yalnızca macOS 14+ hedefler. Windows/Linux yok.
**Gerekçe:** Hedef kitle (Claude Code power user) ağırlıkla Mac'te; rakip araçların
ekosistemi macOS'ta. Overlay penceresi platform-bağımlı en kırılgan parça — Linux'ta
Wayland compositor farkları ciddi maliyet. Kurucunun kariyer hedefi (iOS/Swift) ile
native macOS geliştirme birebir örtüşüyor.
**Sonuç:** Core mantık UI'dan ayrı tutulur ki ileride taşınabilsin, ama taşıma işi
yapılmaz.

## ADR-002 — Native Swift/SwiftUI (Tauri/Electron değil)
**Durum:** Kabul edildi.
**Karar:** Uygulama Swift + SwiftUI + AppKit ile yazılır.
**Gerekçe:** NSPanel'in "her zaman önde, odak çalmayan, şeffaf" davranışı native'de
birinci sınıf. Performans bütçesi (<80 MB RAM) Electron ile tutmaz. Tek platform
olduğumuz için cross-platform framework'ün tek avantajı bize işlemiyor. Kurucu
Swift öğrenmek istiyor.

## ADR-003 — Gözlem-only (etkileşim yok)
**Durum:** Kabul edildi.
**Karar:** v1.0 hiçbir hook'ta karar döndürmez, panelden cevap/onay/prompt yok.
**Gerekçe:** Etkileşim; timeout yönetimi, çift kanal senkronizasyonu ve izin
mekanizmasına müdahale karmaşıklığı getiriyor. Gözlem-only kapsam, tek geliştiricinin
okul yanında ~8 haftada bitirebileceği boyut. Etkileşim ileride ayrı sürümün satış
sebebi olarak saklanıyor.
**Sonuç:** Hook komutları fire-and-forget'tir; EventServer'dan Claude Code'a dönüş
değeri akmaz.

## ADR-004 — Hook-first, JSONL ikincil
**Durum:** Kabul edildi.
**Karar:** State takibi Claude Code hook'larından; JSONL logları SADECE usage
(token/maliyet) ve limit tespiti için okunur.
**Gerekçe:** Hook'lar resmi, event-driven ve gerçek zamanlı. Log tail'lemek
kırılgan ve gecikmeli. İkisini karıştırıp state'i logdan türetmeye çalışmak
senkronizasyon cehennemi yaratır.

## ADR-005 — Event taşıma: localhost HTTP (curl → NWListener)
**Durum:** Kabul edildi.
**Karar:** Hook komutu `curl -s --max-time 1 -X POST http://127.0.0.1:48756/event -d @- || true`.
Uygulama tarafı Network.framework NWListener, sadece loopback'e bind.
**Gerekçe:** Basit, bağımlılıksız, her hook türüyle çalışıyor; benzer araçlarda
kanıtlanmış desen. Unix domain socket daha "şık" ama curl ile taşıma ve debug daha
kolay. `--max-time 1 || true` sayesinde uygulama kapalıyken Claude Code asla beklemez.
**Alternatifler:** Dosyaya yaz + izle (gecikmeli, kilitlenme riskli), UDS (reddedildi,
gereksiz karmaşıklık).

## ADR-006 — App Store'a GİRİLMİYOR
**Durum:** Kabul edildi.
**Karar:** Dağıtım Developer ID imzalı + notarize .dmg ile kendi sitemizden/GitHub'dan.
**Gerekçe:** Mac App Store sandbox'ı `~/.claude/settings.json`'a hook yazmayı ve
serbest dosya erişimini engeller — ürünün çekirdeğiyle çatışır. Kategorideki ciddi
araçların tamamı store dışında dağıtılıyor.
**Sonuç:** Apple Developer Program (99$/yıl) tek zorunlu masraf. Hardened Runtime
açık, App Sandbox kapalı.

## ADR-007 — Orijinal maskot; Anthropic maskotu KULLANILMAZ
**Durum:** Kabul edildi.
**Karar:** Maskot sıfırdan tasarlanan özgün bir karakterdir. Uygulama adında ve
görsellerinde "Claude" ve Anthropic marka öğeleri kullanılmaz; tanım "works with
Claude Code" şeklindedir.
**Gerekçe:** Anthropic'in karakteri/markası onların fikri mülkiyeti; ticari üründe
kullanımı hukuki risk. Özgün maskot ayrıca bizim markamız olur.

## ADR-008 — Tek maskot, protokol arkasında
**Durum:** Kabul edildi.
**Karar:** v1.0'da tek maskot. Maskot, `MascotAnimating` protokolü (state → animasyon)
arkasına konur ama ikinci implementasyon yazılmaz.
**Gerekçe:** Kapsam disiplini. Protokol, ileride maskot paketleri kapısını sıfır
maliyetle açık tutar.

## ADR-009 — Animasyon: Rive, placeholder ile de-risk
**Durum:** Kabul edildi.
**Karar:** Nihai maskot Rive state machine ile. Faz 1-4'te SwiftUI ile çizilmiş
basit placeholder maskot kullanılır; Rive Faz 5'te girer.
**Gerekçe:** Rive, state-driven animasyonu doğal destekler ve GPU'ya 3D gibi yük
bindirmez ("2D ama 3D hissiyatlı" hedefi tasarımla çözülür). Placeholder sayesinde
animasyon aracı riski kritik yolu bloklamaz. 3D render reddedildi: pil/fan maliyeti
"hafif uygulama" vaadini bozar.

## ADR-010 — Usage tamamen lokal, hesap bağlantısı yok
**Durum:** Kabul edildi.
**Karar:** Token/maliyet verisi yalnızca `~/.claude/projects` JSONL dosyalarından
okunur. Anthropic hesabına bağlanma, session key/OAuth kullanımı YOK.
**Gerekçe:** Sıfır kimlik bilgisi = en güçlü güven hikayesi + sıfır bakım yükü.
Resmi limit yüzdeleri bu yüzden gösterilmez; onun yerine 5 saatlik pencere
mantığından lokal reset tahmini yapılır. Limit tespiti best-effort'tur ve öyle
etiketlenir.

## ADR-011 — Sıfır persistans
**Durum:** Kabul edildi.
**Karar:** Oturum/state/usage verisi RAM'de yaşar, uygulama kapanınca gider.
Sadece UI ayarları UserDefaults'ta.
**Gerekçe:** "Stateless & safe" satış vaadi; veritabanı yok = güvenlik yüzeyi yok,
kod yok, bakım yok.

## ADR-012 — Açık kaynak dağıtım
**Durum:** Kabul edildi.
**Karar:** Repo public, kod incelenebilir. Gelir bu sürümün hedefi değil.
**Gerekçe:** Bu kategoride güven ve dağıtım açık kaynakla geliyor (rakiplerin tümü
açık). Projenin birincil getirisi portfolyo/görünürlük; gelecekteki paralı özellikler
(etkileşim, maskot paketleri) bu sürümün üstüne ayrıca konumlanır.

## ADR-013 — Usage kartta değil, menü bar popover'ında
**Durum:** Kabul edildi (Faz 7 sonrası kurucu kararı).
**Karar:** Token/maliyet bilgisi overlay kartında GÖSTERİLMEZ. UsageReader veriyi
toplamaya devam eder; döküm Faz 8'deki menü bar popover'ında sunulur.
**Gerekçe:** Kartın işi bir bakışta state okutmak; token/dolar sayısı görsel gürültü.
Kullanıcının asıl istediği "kalan kota" ise lokal olarak güvenilir hesaplanamaz
(tavan plana/sunucuya bağlı; ADR-010 hesap bağlantısını reddediyor). Yanıltıcı
tahmin göstermektense hiç göstermemek tercih edildi.
**Sonuç:** "Resmi limit yüzdeleri" ertelenen fikirler listesinde durmaya devam
ediyor; ileride hesap bağlantısıyla gelirse kartta "kalan" gösterimi o zaman düşünülür.

## ADR-014 — Çoklu maskot karakteri (kural 6 revizyonu)
**Durum:** Kabul edildi (Faz 9 içinde kurucu kararı).
**Karar:** "Tek maskot" kuralı (CLAUDE.md kural 6) gevşetildi: maskot sistemi birden
fazla KARAKTER destekler. Animasyon beyni (MascotPose — state başına fizik/zamanlama)
tüm karakterlerde ORTAKTIR; yeni karakter yalnızca yeni bir çizim (gövde + yüz/efekt
çapa noktaları) ekler. Seçim modeli: her yeni proje varsayılan karakterle başlar;
kullanıcı bir projenin maskotunu kart menüsünden değiştirirse bu tercih o projeye
(cwd anahtarıyla, UserDefaults'ta) kalıcı olarak bağlanır.
**Gerekçe:** MascotAnimating soyutlaması ve karakterden bağımsız MascotPose zaten bu
gün için kurulmuştu; karakter başına maliyet bir renderer'a düştü. Proje-bazlı kalıcı
seçim, kartların bir bakışta ayrışmasını sağlar ve "maskot paketleri" (ADR-012'deki
gelecek konumlanma) için zemin hazırlar.
**Sonuç:** UserDefaults'ta yalnızca UI tercihi saklanır (kural 2 ile uyumlu:
proje yolu → karakter id sözlüğü). Rive/ikinci parti karakter paketleri ertelenen
fikirler listesinde durmaya devam ediyor.

## ADR-015 — Questioning state (6. oturum durumu)
**Durum:** Kabul edildi (Faz 9 içinde kurucu kararı).
**Karar:** State modeline `questioning` eklendi: Claude, AskUserQuestion tool'uyla
kullanıcıya soru sorduğunda kart "Question" durumuna geçer (camgöbeği tint, maskotta
kafa eğme + "?" balonu). Sinyal: `PreToolUse` eventinde `tool_name == "AskUserQuestion"`.
Sorudayken gelen sıradan Notification state'i attention'a düşürmez (soru zaten daha
spesifik bir "girdi bekliyor" bilgisidir); limit Notification'ı yine limit'e taşır.
Çıkış diğer state'lerle aynıdır: sonraki tool/prompt eventi working'e çeker.
**Gerekçe:** attention "izin VEYA girdi" ikisini birden taşıyordu; soru sorma, panelin
asıl değer önerisi olan "hangi oturum benden ne bekliyor?" sorusunun en sık cevabı.
Tool adı sinyali, Notification metni ayrıştırmaya (kırılgan, dile bağlı) gerek
bırakmaz. Tespit best-effort'tur: hook AskUserQuestion için tetiklenmezse davranış
bugünkü gibi kalır (Notification → attention), hiçbir şey bozulmaz.

## ADR-016 — Limit reset tahmini kaldırıldı
**Durum:** Kabul edildi (Faz 9 içinde kurucu kararı).
**Karar:** Karttaki "Resets: ~14:30" tahmini kaldırıldı. `limit` state kalır —
girişi somut kanıta dayalıdır (transcript'te gerçek rate-limit hata izi veya
limit içerikli Notification); bulanık olan yalnızca reset SAATİYDİ.
**Gerekçe:** 5 saatlik pencerenin gerçek başlangıcı lokal olarak bilinemez
(oturum başlangıcı ≠ pencere başlangıcı); tahmin yanılttığında kullanıcı yanlış
saate güvenip bekliyor. ADR-013'ün ilkesiyle tutarlı: yanıltıcı tahmin
göstermektense hiç göstermemek. `LimitDetector.estimateReset` ve
`Session.limitResetAt` kodla birlikte kaldırıldı (YAGNI).

## Ertelenen fikirler (v1.0 sonrası, sırasız)
- Panelden izin onaylama / Claude'a mesajla yönlendirme (gelecek paralı sürümün çekirdeği)
- Gemini CLI / Codex CLI adapter'ları (capability protokolüyle)
- Maskot ve tema paketleri
- Resmi limit yüzdeleri (Keychain'de kullanıcı kimliğiyle)
- Activity timeline, akıllı bildirim kuralları
- Maskot etkileşimi: panel/kart sallanınca maskotun "çıldırma" animasyonu oynaması
- Ayarlar'dan uygulama içi dil seçimi (Sistem/EN/TR — `AppleLanguages` + yeniden
  başlatma). v1.0'da gerek görülmedi: macOS, Sistem Ayarları → Dil ve Bölge →
  Uygulamalar'dan uygulamaya özel dil seçimini zaten native sunuyor; README'de
  bu yol anlatılacak.
- Düz metin soru tespiti: Claude soruyu AskUserQuestion tool'u yerine turu bitiren
  düz metinle sorduğunda hook seviyesinde sinyal yok (Stop → done görünür; ~60 sn
  sonra idle Notification'ı attention'a çeker). Erken yakalamak için Stop anında
  transcript'teki son asistan mesajının soruyla bitip bitmediğine bakan bir
  sezgisel düşünüldü ama ertelendi: retorik "?" işaretlerinde yanlış tetikler,
  "emin değilsen state'i bozma" ilkesine aykırı (bkz. ADR-015).

