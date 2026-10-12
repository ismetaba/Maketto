# Maketto (iOS)

Evinizi LiDAR ile tarayıp ölçülü 2D plana ve 3D maket görünümüne çeviren,
planı düzeltip gerçek ölçülerinde eşya yerleştirebildiğiniz ev tasarım uygulaması.

## Özellikler

| Alan | Ne yapar |
|------|----------|
| **Tüm ev taraması** | RoomPlan ile evi tek seferde dolaşın; Maketto taramayı odalara böler, duvar köşelerini birleştirir, planı eksenlere hizalar, odalara tür ve isim verir. Kamera izni reddedilirse Ayarlar'a yönlendirir. |
| **Tarama sonucu** | Odaları haritada seçip adını/türünü düzeltme, yanlış algılanan alanı kaldırma, evi adlandırıp kaydetme. |
| **Ev haritası** | Oda renkli tüm ev planı; yakınlaştır/kaydır/sığdır, oda kartı, 2D ⇄ 3D ev görünümü, planı PNG olarak paylaşma, evi yeniden adlandırma/silme. |
| **Oda planı (2D)** | Ölçeğe sadık mimari plan: duvar kalınlıkları, kapı açılış yayları, pencereler, dinamik metrik ızgara; duvara dokununca ölçüsü. |
| **Plan düzenleyici** | Köşe sürükleme (eksen hizalama kılavuzları, köşelere kaynama), yazarak duvar uzunluğu girme, yeni duvar çizme (köşelere bağlanır / duvarı böler), duvar silme; tümü geri al / yinele. Kapı ve pencereler duvar uzayınca dünyadaki yerinde kalır. |
| **Eşya** | Gerçek ölçülü katalog (260×200 L koltuk dahil), fotoğraflı kendi eşyalarınız, taramada algılanan eşyaları tek dokunuşla içe aktarma; sürükle (duvara yaslanır), döndür, ölçü/açı gir, aynala, çoğalt, sil. |
| **3D** | SceneKit ile RoomModel'den üretilen maket: kapı/pencere boşlukları gerçek delik, camlar, zemin, eşyalar (fotoğraf üst yüzeyde). 2D ile birebir aynı ölçü. |
| **Sürümler** | Her kayıt yeni bir sürüm; önizlemeli sürüm geçmişi, eski sürüme dönme (hiçbir şey silinmez), adlandırma, silme. |
| **Dışa aktarma** | Plan kartı (PNG) ve ölçüler (JSON, metre). |

## Gereksinimler
- Xcode 16.4+ (Xcode 26 ile de derlenir), iOS 17.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — `.xcodeproj` elle düzenlenmez, `project.yml`'den üretilir
- Tarama için **LiDAR'lı cihaz** (iPhone 12 Pro+ / iPad Pro). Simülatörde uygulama açılır; tarama ekranı "LiDAR gerekli" der, diğer her şey çalışır.

## Projeyi üret & aç
```bash
xcodegen generate          # project.yml -> Maketto.xcodeproj
open Maketto.xcodeproj
```
Xcode'da hedefi iPhone'una seç, imzalama için kendi Apple ID takımını gir, Run.

## Testler
- **Xcode / CI:** `MakettoTests` hedefi (Swift Testing) — geometri, plan düzenleyici, eşya, sürüm geçmişi ve SwiftData deposu.
  ```bash
  xcodebuild test -project Maketto.xcodeproj -scheme Maketto \
    -destination 'platform=iOS Simulator,name=iPhone 16'
  ```
- **CI:** `.github/workflows/ci.yml` her push'ta macOS 15 (Xcode 16) ve macOS 26 (Xcode 26) üzerinde cihaz derlemesi yapar (RoomPlan yolları dahil) ve testleri çalıştırır.

## Mimari
- `Sources/Model` — saf, taşınabilir değer tipleri ve geometri (RoomPlan/SwiftUI bağımlılığı yok, cihazsız test edilir): `RoomModel`, `FloorGeometry` (kapalı zemin poligonu, köşe kaynatma), `PlanGeometry` (dünya ↔ ekran), `HomeGeometry` (tüm evi eksenlere hizalama), `Furniture` (eşya, katalog, ayak izi), `WallMesh` (3D için duvar delikleri), `VersionSnapshot`.
- `Sources/Scanner` — RoomPlan'e bağımlı tek katman: tarama oturumu yaşam döngüsü ve `CapturedRoom` → `RoomModel` dönüşümü.
- `Sources/Persistence` — SwiftData (`Home → Room → Version`); her `Version` değişmez bir JSON anlık görüntüsüdür. `RoomStore` görünümleri SwiftData'dan yalıtır; kendi eşya kütüphanesi ve fotoğraflar dosya olarak saklanır.
- `Sources/Features` — SwiftUI ekranları; `PlanEditor/EditableRoom` köşe-grafı tabanlı, geri alınabilir düzenleyici.
- Koordinatlar: zemin düzlemi dünya XZ (metre). Ev, ekranda baskın duvar açısına göre döndürülerek düz gösterilir; kayıtlar ham çerçevede tutulur.
