# iOS Ev Tasarım Uygulaması — Plan

> Durum: **plan aşaması, henüz kod yok.** Xcode evde kurulacak. Cihaz: iPhone 14 Pro Max (LiDAR ✅).

## Vizyon / akış
Evi RoomPlan ile tara → 2D tepeden ölçülü plan → kullanıcı düzeltir → istediği yere ölçülü eşya (örn. L koltuk, fotoğraflı) koyar → native 3D ve/veya Gemini render → odaların versiyonları (her versiyon tam snapshot).

```
RoomPlan tarama → [RoomModel]  → 2D plan çiz → düzelt → eşya koy → [Layout]
                  (kendi modelin)                                      │
                                              ┌───────────────────────┤
                                         Versiyonlar            Görselleştirme
                                      (Layout snapshot)         ├─ Native 3D (RealityKit)
                                                                └─ Gemini render (sonra)
```

## Anahtar tasarım kararı
RoomPlan `CapturedRoom`'unu hemen kendi taşınabilir **`RoomModel` / `Layout`** modeline çevir. Tüm özellikler bu model üzerinden çalışır → her özellik **mock veriyle bağımsız** test edilebilir (cihaz/tarama gerekmeden).

Doğruluk: native 3D ölçüye birebir sadık. Gemini sadece sunum/stil katmanı (ölçüye sadık değil; plan görselini input olarak ver).

## Stack
SwiftUI · RoomPlan · RealityKit/SceneKit · SwiftData (+ sonra CloudKit) · Gemini API (sonra)

## Özellikler (bağımsız modüller)

| # | Özellik | Framework | Doğrulama yeri | Ön koşul |
|---|---------|-----------|----------------|----------|
| F0 | Veri modeli + app iskeleti (ev/oda listesi) | SwiftData+SwiftUI | Simülatör | Xcode |
| F1 | **RoomPlan tarama → RoomModel** | RoomPlan | Gerçek cihaz | Xcode + cihaz |
| F2 | 2D tepeden plan çizimi | SwiftUI Canvas | Simülatör (mock) | Xcode |
| F3 | Plan düzeltme (uzunluk, köşe, snap) | SwiftUI Canvas | Simülatör | Xcode |
| F4 | Eşya yerleştirme (2D, ölçekli, döndür) | SwiftUI/SpriteKit | Simülatör | Xcode |
| F5 | Eşya kataloğu (boyut + fotoğraf) | SwiftData+PhotosUI | Simülatör | Xcode |
| F6 | Native 3D görünüm | RealityKit/SceneKit | Simülatör/cihaz | Xcode |
| F7 | Gemini render | Gemini API | Script/app | API key — ertelendi |
| F8 | Versiyonlama (snapshot/seç/kaydet) | SwiftData | Simülatör | Xcode |

**Entegrasyon sırası:** F0 → F1 → F2 → F3 → F4 → F5 → F8 → F6 → (F7 en son)

## "Bitti/doğrulandı" kriterleri
- **F1:** Tara → duvar ölçülerini dök → mezurayla fark < ~5 cm. RoomModel JSON dışa verilebiliyor.
- **F2:** Elle yazılmış RoomModel JSON'u → doğru oranlı, ölçü etiketli plan çizsin.
- **F3:** Duvar sürükle/uzunluk yaz → ölçüler ve komşu köşeler tutarlı güncellensin.
- **F4:** "L koltuk 260×200" → plandaki ölçek doğru orantılı; döndürme çalışıyor.
- **F5:** Yeni eşya (boyut+fotoğraf) oluştur → listede → plana yerleştir.
- **F6:** Aynı Layout 3D'de → boyutlar 2D ile birebir uyuşsun.
- **F8:** v1 yap → değiştir → v2 kaydet → v1'e dön → v1 tam eski haliyle gelsin.

## Versiyonlama modeli (kavramsal)
```
Ev (Home)
 └─ Oda (Room)
     ├─ versions: [Version]      ← her biri tam snapshot
     └─ activeVersionId
Version = { id, ad, oluşturulma, roomModel, placedFurniture[], generatedImages[] }
```
**Açık karar:** "yeni versiyon ekleyince oda sıfırlanır" → (a) snapshot al + editör boş başlar, mı (b) kopyadan devam mı? Şimdilik (a) snapshot tabanlı varsayılıyor. Kodlamadan önce netleştirilecek.

## "Eve gidince" hazırlık
- [ ] Xcode (App Store, tam sürüm, ~10+ GB)
- [ ] iPhone 14 Pro Max'e yükleme için Apple Developer hesabı (ücretsiz yeter)
- [ ] iOS 16+ (multi-room istenirse iOS 17+)
- [ ] (sonra) Gemini API anahtarı — F7 için

---

# F1 — RoomPlan Tarama (detay)

## Ekran akışı
1. **Oda listesi** → "Yeni oda tara" butonu.
2. **Tarama ekranı** → `RoomCaptureView` (Apple'ın hazır rehberli UI'ı: "telefonu gezdir" overlay'i, otomatik yüzey algılama). Spike için en hızlısı bu; özel UI istersek sonra `RoomCaptureSession`'a geçeriz.
3. **İşleme** → tarama bitince `CapturedRoom` üretilir.
4. **Sonuç ekranı** → ölçüleri dök (her duvar + oda boyutu); opsiyonel USDZ 3D önizleme.
5. **Kaydet** → `CapturedRoom` → `RoomModel`'e çevrilip JSON olarak saklanır.

## İzinler
- `NSCameraUsageDescription` (Info.plist) — RoomPlan kamera + LiDAR kullanır.

## CapturedRoom ne veriyor
- `walls: [Surface]` — `dimensions` (en, yükseklik, kalınlık), `transform` (dünya konumu+rotasyon), kategori, güven.
- `doors`, `windows`, `openings: [Surface]` — duvarlara göre konumlu.
- `objects: [Object]` — otomatik algılanan eşyalar (koltuk, masa, yatak, dolap…) boyut+konum+güven ile. (Mevcut eşyaları bedavaya algılar — işe yarar.)
- USDZ dışa: `try capturedRoom.export(to: url)`.

## Zor kısım — duvarları 2D zemin planına çevirme
- Her duvarın `transform`'u merkez+yön verir; `dimensions.x` duvar uzunluğu.
- Zemine projeksiyon: yükseklik (Y) eksenini at → X,Z düzlemi = zemin.
- Her duvar → çizgi parçası: merkez ± (yarı-uzunluk, duvarın yönüne döndürülmüş).
- Duvarlar her zaman tam birleşmez → komşu uçları kesiştirip/snap'leyerek köşe çıkar (bu F2'nin asıl işi).
- **F1 için yeterli:** her duvarı ayrı segment olarak çizmek bile tarama doğruluğunu doğrulamaya yeter.

## RoomModel — alan listesi (sonraki tüm özelliklerin sözleşmesi)
```
RoomModel {
  id; name; createdAt
  unit = meters            // kanonik birim
  walls: [Wall {
    id
    start: Point2D(x,z)    // zemin düzlemi, metre
    end:   Point2D(x,z)
    thickness: Float
    height: Float
  }]
  openings: [Opening {
    id
    type: door | window | opening
    onWallId
    offset: Float          // duvar.start'tan uzaklık
    width: Float; height: Float
    sillHeight: Float?     // pencere için
  }]
  detectedObjects: [DetectedObject {   // RoomPlan otomatik algılama (opsiyonel)
    id; category
    center: Point2D
    size: (w, d)           // taban alanı, metre
    rotation: Float
    height: Float
  }]
  floorOutline: [Point2D]?  // türetilen kapalı poligon (F2 doldurur)
  source: roomplan | manual
}
```

## F1 doğrulama (kabul testi)
1. Odayı tara → her duvarın start/end/uzunluğunu logla.
2. Gerçek odada mezurayla 2-3 duvarı ölç → fark < ~5 cm.
3. RoomModel JSON dışa verilip tekrar okunabiliyor.

## Bilinen tuzaklar
- Ayna, cam, çok karanlık, dağınık oda → düşük doğruluk.
- Telefonu yavaş gezdir, her duvarı kameraya göster (coaching UI yardımcı olur).
- `RoomCaptureView` simülatörde derlenir ama çalışmaz → test cihazda.
- Çok-odalı birleştirme iOS 17+ `StructureBuilder`; spike için tek oda yeter.
