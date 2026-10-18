# Maketto — İş-Zaman Çizelgesi

## Proje Bilgileri

| | |
|---|---|
| **Ders** | Mobil Programlama (2026–2027 Güz Yarıyılı) |
| **Proje Konusu** | RGB-D ve LiDAR ile SLAM |
| **Proje Adı** | Maketto |
| **Proje Amacı** | Mobil cihazın RGB-D kamerası ve LiDAR sensörüyle iç mekânın haritasını çıkaran, kullanıcının bu harita üzerindeki konumunu belirleyen ve seçilen duvar için yapay zekâ destekli tasarım önerisi üreten bir mobil uygulama geliştirmek |
| **Proje Süresi** | 07.10.2026 – 25.12.2026 |
| **Referans Çalışma** | Yan, Y.; Li, J.; Liu, Q.; Lv, S.; Wu, Q. *RGB-D SLAM: A Review of Methods and Performance Trade-Offs for Different Requirements.* Sensors 2026, 26(11), 3513. [doi:10.3390/s26113513](https://doi.org/10.3390/s26113513) |

## Gantt Şeması

```mermaid
%%{init: {"gantt": {"leftPadding": 170, "barHeight": 24, "barGap": 6, "fontSize": 13, "sectionFontSize": 13, "numberSectionStyles": 3}}}%%
gantt
    title Maketto: RGB-D ve LiDAR ile SLAM — İş-Zaman Çizelgesi
    dateFormat YYYY-MM-DD
    axisFormat %d.%m
    tickInterval 1week
    weekday monday

    section Planlama ve Tasarım
    İP-1 Konu Belirleme, Literatür ve Planlama  :done, 2026-10-07, 10d
    İP-2 Gereksinim Analizi ve Sistem Mimarisi  :2026-10-19, 5d
    İP-3 Arayüz Tasarımı (Mock-up) ve Altyapı   :2026-10-26, 12d
    İP-4 Use Case ve Activity Diyagramları      :2026-11-02, 5d
    M1 Tasarım Tamamlandı                       :milestone, 2026-11-07, 0d

    section Geliştirme
    İP-5 Veri Toplama ve Sensör Kalibrasyonu    :2026-11-09, 5d
    İP-6 SLAM ile İç Mekân Haritalama           :2026-11-16, 19d
    M2 İç Mekân Haritası Hazır                  :milestone, 2026-12-05, 0d
    İP-7 2B Kat Planı Çıkarımı ve Düzenleme     :2026-12-07, 5d
    İP-8 Harita Üzerinde Konum Belirleme        :2026-12-14, 5d
    İP-9 Yapay Zekâ Destekli Duvar Tasarımı     :2026-12-14, 12d
    İP-10 Test, Değerlendirme ve Sunum          :2026-12-21, 5d
    M3 Uygulama Tamamlandı                      :milestone, 2026-12-26, 0d
```

Gri çubuk tamamlanan iş paketini, elmas işareti kilometre taşını gösterir. Rapor ve sunumlarda kullanılmak üzere görsel: [`docs/gantt.png`](docs/gantt.png)

## İş Paketleri

| İP | İş Paketi | Hafta | Tarih Aralığı | Çıktı |
|---|---|:---:|---|---|
| İP-1 | Proje konusunun belirlenmesi, literatür taraması ve iş-zaman planlaması | 2–3 | 07.10.2026 – 16.10.2026 | Proje tanımı ve Gantt şeması |
| İP-2 | Gereksinim analizi ve sistem mimarisinin tasarlanması | 4 | 19.10.2026 – 23.10.2026 | Gereksinim listesi ve sistem mimarisi şeması |
| İP-3 | Kullanıcı arayüzü tasarımı (mock-up) ve uygulama altyapısının kurulması | 5–6 | 26.10.2026 – 06.11.2026 | Ekran tasarımları ve ekranlar arası geçişler |
| İP-4 | Use Case ve Activity diyagramlarının hazırlanması | 6 | 02.11.2026 – 06.11.2026 | UML diyagramları ve fonksiyonel tanım raporu |
| İP-5 | RGB-D ve LiDAR verilerinin toplanması, sensör kalibrasyonu | 7 | 09.11.2026 – 13.11.2026 | Kalibre edilmiş tarama veri seti |
| İP-6 | SLAM algoritmasının geliştirilmesi ve iç mekânın haritalanması | 8–10 | 16.11.2026 – 04.12.2026 | İç mekânın üç boyutlu haritası |
| İP-7 | Haritadan iki boyutlu kat planı çıkarımı ve plan düzenleme modülü | 11 | 07.12.2026 – 11.12.2026 | Ölçülü ve düzenlenebilir kat planı |
| İP-8 | Harita üzerinde konum belirleme (relokalizasyon) | 12 | 14.12.2026 – 18.12.2026 | Kullanıcının plan üzerindeki konumu ve bakış yönü |
| İP-9 | Duvar görüntüsü üzerinden yapay zekâ destekli tasarım | 12–13 | 14.12.2026 – 25.12.2026 | Seçilen duvar için tasarım önerisi |
| İP-10 | Sistem testleri, performans değerlendirmesi ve sunum hazırlığı | 13 | 21.12.2026 – 25.12.2026 | Test raporu ve çalışır durumda uygulama |

## Kilometre Taşları

| No | Kilometre Taşı | Tarih | Kapsadığı İş Paketleri |
|---|---|---|---|
| M1 | Tasarım tamamlandı | 06.11.2026 | İP-1 – İP-4 |
| M2 | İç mekân haritası hazır | 04.12.2026 | İP-5 – İP-6 |
| M3 | Uygulama tamamlandı | 25.12.2026 | İP-7 – İP-10 |
