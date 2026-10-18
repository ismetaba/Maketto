# Maketto — İş-Zaman Çizelgesi (Gantt)

- **Ders:** Mobil Programlama, 2026–27 Güz
- **Proje konusu:** RGB-D ve LiDAR ile SLAM
- **Proje:** Maketto — telefonla evi tara, planı düzenle, evde konumunu haritada bul, bir duvarın fotoğrafını çek ve o duvar için AI tasarım al.
- **Referans makale:** Yan vd., *RGB-D SLAM: A Review of Methods and Performance Trade-Offs for Different Requirements*, Sensors 2026, 26(11), 3513. [doi:10.3390/s26113513](https://doi.org/10.3390/s26113513)

```mermaid
%%{init: {"gantt": {"leftPadding": 150, "barHeight": 24, "barGap": 6, "fontSize": 13, "sectionFontSize": 13, "numberSectionStyles": 3}}}%%
gantt
    title Maketto · RGB-D ve LiDAR ile SLAM — İş-Zaman Çizelgesi
    dateFormat YYYY-MM-DD
    axisFormat %d.%m
    tickInterval 1week
    weekday monday

    section Planlama ve tasarım
    Konu seçimi, literatür, Gantt          :2026-10-07, 10d
    Gereksinimler ve sistem mimarisi       :2026-10-19, 5d
    Mock-up ve uygulama iskeleti           :2026-10-26, 12d
    Use Case ve Activity diyagramları      :2026-11-02, 5d

    section Geliştirme
    Veri toplama ve kalibrasyon            :2026-11-09, 5d
    SLAM ile haritalama                    :2026-11-23, 12d
    2D plan ve plan düzenleme              :2026-12-07, 5d
    Haritada konum bulma                   :2026-12-14, 5d
    Duvar fotoğrafı ve AI tasarım          :2026-12-14, 12d
    Test ve sunum hazırlığı                :2026-12-21, 5d

    section Ders takvimi
    Faz-1 teslimi                          :milestone, 2026-10-16, 0d
    Faz-2 teslimi                          :milestone, 2026-11-09, 0d
    Vize haftası                           :crit, 2026-11-16, 5d
    Faz-3 proje sunumu                     :crit, 2026-12-28, 5d
```

Rapor ve sunum için görsel: [`docs/gantt.png`](docs/gantt.png)

| Hafta | Tarih | İş | Çıktı |
|---|---|---|---|
| H2–H3 | 7–16 Ekim | Konu seçimi, literatür, Gantt | **Faz-1 teslimi** |
| H4 | 19–23 Ekim | Gereksinimler ve sistem mimarisi | Mimari şema |
| H5–H6 | 26 Ekim – 6 Kasım | Mock-up ve uygulama iskeleti | Ekranlar ve geçişler |
| H6 | 2–6 Kasım | Use Case ve Activity diyagramları | **Faz-2 teslimi** (9 Kasım) |
| H7 | 9–13 Kasım | Veri toplama (RGB-D + LiDAR) ve kalibrasyon | Kayıtlı tarama verisi |
| H8 | 16–20 Kasım | Vize haftası | — |
| H9–H10 | 23 Kasım – 4 Aralık | SLAM ile haritalama | Evin 3B haritası |
| H11 | 7–11 Aralık | 2D plan çıkarma ve plan düzenleme | Düzenlenebilir plan |
| H12 | 14–18 Aralık | Haritada konum bulma | Planda "buradasınız" |
| H12–H13 | 14–25 Aralık | Duvar fotoğrafı ve AI tasarım | AI tasarım görseli |
| H13 | 21–25 Aralık | Test ve sunum hazırlığı | Çalışan uygulama |
| H14 | 28 Aralık – 1 Ocak | Proje sunumu | **Faz-3 teslimi** |
