import SwiftUI

/// "Hakkında": scanning tips that make or break scan quality, how the app
/// treats your data, and credits.
struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Sürüm \(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        MakettoLogo(size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Maketto").font(.display(28)).foregroundStyle(Brand.textPrimary)
                            Text(version).font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("İyi bir tarama için") {
                    tip("lightbulb", "Işıkları açın", "RoomPlan karanlıkta ve doğrudan güneş ışığında zorlanır.")
                    tip("figure.walk", "Yavaş ve sürekli yürüyün",
                        "Telefonu göğüs hizasında tutun; her duvarı, köşeyi ve zemini kameraya gösterin.")
                    tip("door.left.hand.open", "Kapıları açık bırakın",
                        "Odalar arasında geçerken kapılardan yavaşça geçin; Maketto odaları tek haritada birleştirir.")
                    tip("rectangle.on.rectangle.slash", "Aynalara dikkat",
                        "Ayna ve büyük camlar duvar gibi algılanabilir; tarama sonrası planda kolayca silebilirsiniz.")
                    tip("ruler", "Ölçüyü doğrulayın",
                        "Bir duvara dokunup ölçüsünü mezurayla karşılaştırın; gerekirse düzenleyicide uzunluğu yazarak düzeltin.")
                }

                Section("Verileriniz") {
                    Label {
                        Text("Taramalar, planlar ve fotoğraflar yalnızca bu cihazda saklanır; hiçbir sunucuya gönderilmez ve takip yapılmaz.")
                    } icon: {
                        Image(systemName: "lock.shield").foregroundStyle(Brand.evergreenAdaptive)
                    }
                    .font(.system(size: 14))
                }

                Section("Teşekkürler") {
                    Text("Başlık yazı tipi: Cormorant Garamond — Christian Thalmann, SIL Open Font License 1.1.")
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.textSecondary)
                    Text("Tarama: Apple RoomPlan.")
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            .navigationTitle("Hakkında")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func tip(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.clay)
                .frame(width: 30, height: 30)
                .background(Brand.clay.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Text(body).font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AboutSheet()
}
