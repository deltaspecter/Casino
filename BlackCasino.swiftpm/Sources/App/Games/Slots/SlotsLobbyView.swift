import SwiftUI

struct SlotsLobbyView: View {
    @Environment(AppModel.self) private var model
    @Binding var path: [Route]

    var body: some View {
        ZStack {
            LightSweepBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    GameTopBar(title: "SLOTS", subtitle: "Wähle deinen Automaten")
                        .padding(.horizontal, -Theme.gutter)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 22)], spacing: 22) {
                        ForEach(SlotCatalog.all) { machine in
                            Button {
                                Haptics.tap()
                                path.append(.slotMachine(id: machine.id))
                            } label: {
                                MachineCard(definition: machine)
                            }
                            .buttonStyle(PressableCardStyle())
                        }
                    }

                    NoCashValueNote()
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 40)
            }
        }
    }
}

private struct MachineCard: View {
    let definition: SlotMachineDefinition

    var body: some View {
        let theme = SlotTheme.forMachine(definition.id)
        let preview = definition.symbols.filter { $0.kind == .regular }.suffix(3).map(\.id) + ["wild"]
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ForEach(preview, id: \.self) { id in
                    SlotSymbolView(symbolID: id, size: 62)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.35)))

            VStack(alignment: .leading, spacing: 6) {
                Text(definition.name.uppercased()).font(.display(22)).foregroundStyle(.white)
                Text(definition.tagline).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
            }
            HStack {
                Label("5×3 · \(definition.paylines.count) Linien", systemImage: "rectangle.split.3x3")
                Spacer()
                Text("RTP \(SlotInfo.rtpText(definition.id))")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .fill(LinearGradient(colors: theme.background, startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .strokeBorder(theme.glow.opacity(0.5), lineWidth: 1.5)
        )
        .shadow(color: theme.glow.opacity(0.3), radius: 24, y: 10)
    }
}
