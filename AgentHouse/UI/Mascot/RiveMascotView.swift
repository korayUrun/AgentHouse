// ADR-009'un de-risk yolu devrede: Rive editöründe tasarlanmış bir .riv maskot
// dosyası henüz olmadığı için rive-ios entegrasyonu ertelendi; aktif maskot
// PlaceholderMascotView'dur (bkz. MascotAnimating.swift'teki ActiveMascot).
// .riv hazır olduğunda: rive-ios SPM ile eklenir, state → Rive state machine
// input eşlemesi burada MascotAnimating'e uygun olarak yazılır ve ActiveMascot
// typealias'ı bu tipe çevrilir.
