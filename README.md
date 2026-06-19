# Maketto (iOS)

Ev tasarım uygulaması. Bu repo şu an **F0 (app shell) + F1 (RoomPlan tarama)** milestone'unu içeriyor.

- **F0:** taranmış odaların listesi + SwiftData kalıcılığı (Home → Room → Version snapshot iskeleti) + NavigationStack/Router.
- **F1:** RoomPlan ile oda tarama → Apple `CapturedRoom` kendi taşınabilir `RoomModel`'imize çevrilir → duvar uzunlukları mezurayla doğrulama ekranında gösterilir → oda kaydedilir.

Sonraki milestone'lar: 2D plan editörü, eşya yerleştirme, native 3D, Gemini render, tam versiyonlama. (Bkz. `PLAN.md`.)

## Gereksinimler
- Xcode 26.5+ (iOS 17.0 deployment target)
- [XcodeGen](https://github.com/yonwoo9/XcodeGen) (`brew install xcodegen`) — `.xcodeproj` elle düzenlenmez, `project.yml`'den üretilir
- Tarama (F1) için **LiDAR'lı cihaz** (iPhone 12 Pro+/iPad Pro). Simülatörde uygulama açılır ama tarama ekranı "LiDAR gerekli" der.

## Projeyi üret & aç
```bash
xcodegen generate          # project.yml -> ios-home-design.xcodeproj
open ios-home-design.xcodeproj
```
Xcode'da hedefi iPhone'una seç, imzalama için kendi Apple ID takımını gir, Run.

## Komut satırından derleme doğrulaması
Tam `xcodebuild` build, iOS platform paketi gerektirir (Xcode > Settings > Components veya `xcodebuild -downloadPlatform iOS`). Onsuz, kaynakları cihaz SDK'sına karşı **type-check** edebilirsin:
```bash
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
swiftc -sdk "$SDK" -target arm64-apple-ios17.0 \
  -swift-version 6 -strict-concurrency=complete \
  -parse-as-library -typecheck $(find Sources -name '*.swift')
```

## Mimari notu
`RoomModel` (Codable değer tipleri) tüm katmanların sözleşmesidir; RoomPlan'e bağımlılık yalnızca `Sources/Scanner/RoomModelConverter.swift` + `RoomCaptureViewRepresentable.swift` içinde. Saf geometri (`FloorGeometry`) ve model katmanı cihazsız test edilebilir.
