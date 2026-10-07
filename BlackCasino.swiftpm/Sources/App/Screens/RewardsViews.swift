import SwiftUI

/// Kopf für Sheets mit Schließen-Button.
struct SheetHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.display(30)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 16)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            IconButton(systemName: "xmark", size: 44) { dismiss() }
        }
    }
}

// MARK: - Login-Bonus

struct LoginBonusView: View {
    @Environment(AppModel.self) private var model
    let offer: LoginBonusOffer

    var body: some View {
        VStack(spacing: 26) {
            Text("WILLKOMMEN ZURÜCK").font(.display(26)).foregroundStyle(.white)
            Text("Täglicher Login-Bonus · Tag \(offer.streakDay)")
                .font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.textSecondary)

            HStack(spacing: 10) {
                ForEach(1...7, id: \.self) { day in
                    let current = ((offer.streakDay - 1) % 7) + 1
                    VStack(spacing: 6) {
                        Text("TAG \(day)").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textSecondary)
                        ChipIcon(color: day == current ? Theme.red : day < current ? Theme.gold : Color(white: 0.25), size: 34)
                        Text(ChipFormat.compact(RewardTable.loginReward(streakDay: day)))
                            .font(.numeric(13, weight: .bold)).foregroundStyle(.white)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(day == current ? Theme.red.opacity(0.18) : Theme.surfaceRaised))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(day == current ? Theme.red : Color.clear, lineWidth: 2))
                }
            }

            Button("+\(ChipFormat.string(offer.amount)) CHIPS ABHOLEN") { model.claimLoginBonus() }
                .buttonStyle(.casino(.gold, size: .large))
            NoCashValueNote(compact: true)
        }
        .padding(32)
    }
}

// MARK: - Tägliche Belohnung

struct DailyRewardView: View {
    @Environment(AppModel.self) private var model
    @State private var glow = false

    var body: some View {
        VStack(spacing: 30) {
            SheetHeader(title: "DAILY REWARD", subtitle: "Einmal pro Kalendertag kostenlose virtuelle Chips. Hat keinen Einfluss auf Spielergebnisse.")

            Spacer()
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.gold.opacity(glow ? 0.45 : 0.2), .clear], center: .center,
                                         startRadius: 0, endRadius: 200))
                    .frame(width: 400, height: 400)
                Image(systemName: model.canClaimDailyReward ? "gift.fill" : "checkmark.seal.fill")
                    .font(.system(size: 120, weight: .bold))
                    .foregroundStyle(Theme.goldGradient)
                    .shadow(color: Theme.gold.opacity(0.6), radius: 30)
                    .scaleEffect(glow ? 1.04 : 0.98)
            }
            Text("+\(ChipFormat.string(RewardTable.dailyReward)) CHIPS")
                .font(.display(40)).foregroundStyle(.white)

            if model.canClaimDailyReward {
                Button("JETZT ABHOLEN") { model.claimDailyReward() }
                    .buttonStyle(.casino(.gold, size: .large))
            } else if let next = model.profile.nextDailyReward(now: .now) {
                VStack(spacing: 6) {
                    Text("Bereits abgeholt").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    Text("Nächste Belohnung \(next, style: .relative)")
                        .font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                }
            }

            if model.canClaimRescue {
                RescueHint()
            }
            Spacer()
            NoCashValueNote()
        }
        .padding(32)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}

// MARK: - Missionen

struct MissionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: "MISSIONS", subtitle: "Optionale Tagesaufgaben. Sie geben nur zusätzliche Chips – und verändern keine Gewinnchancen.")
                ForEach(model.profile.dailyMissions) { mission in
                    if let def = RewardTable.mission(mission.missionID) {
                        MissionRow(definition: def, progress: mission.progress, claimed: mission.isClaimed) {
                            model.claimMission(def.id)
                        }
                    }
                }
                Text("Neue Missionen gibt es um Mitternacht.")
                    .font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
            }
            .padding(32)
        }
    }
}

private struct MissionRow: View {
    let definition: MissionDefinition
    let progress: Int
    let claimed: Bool
    let onClaim: () -> Void

    var body: some View {
        let complete = progress >= definition.target
        HStack(spacing: 18) {
            Image(systemName: claimed ? "checkmark.circle.fill" : complete ? "flag.checkered" : "flag")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(claimed ? Theme.success : complete ? Theme.gold : Theme.textSecondary)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.white.opacity(0.05)))
            VStack(alignment: .leading, spacing: 8) {
                Text(definition.title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                ProgressBar(value: Double(progress) / Double(definition.target))
                Text("\(ChipFormat.string(progress)) / \(ChipFormat.string(definition.target)) · Belohnung \(ChipFormat.string(definition.rewardChips)) Chips")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 10)
            if claimed {
                Text("EINGELÖST").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.success)
            } else {
                Button("EINLÖSEN", action: onClaim)
                    .buttonStyle(.casino(.gold, size: .small))
                    .disabled(!complete)
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 22)
    }
}

// MARK: - Erfolge

struct AchievementsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: "ACHIEVEMENTS",
                            subtitle: "\(model.profile.unlockedAchievements.count) von \(RewardTable.achievements.count) freigeschaltet · reine Anzeige, ohne Einfluss auf das Spiel")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(RewardTable.achievements) { def in
                        AchievementTile(definition: def,
                                        value: model.profile.metricValue(def.metric),
                                        unlocked: model.profile.unlockedAchievements.contains(def.id),
                                        claimed: model.profile.claimedAchievements.contains(def.id)) {
                            model.claimAchievement(def.id)
                        }
                    }
                }
            }
            .padding(32)
        }
    }
}

private struct AchievementTile: View {
    let definition: AchievementDefinition
    let value: Int
    let unlocked: Bool
    let claimed: Bool
    let onClaim: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: definition.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(unlocked ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.textTertiary))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(unlocked ? Theme.gold.opacity(0.14) : Color.white.opacity(0.04)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(definition.title).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    Text(definition.detail).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
            }
            ProgressBar(value: Double(value) / Double(definition.threshold), height: 6,
                        fill: AnyShapeStyle(unlocked ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.redGradient)))
            HStack {
                Text("\(ChipFormat.string(min(value, definition.threshold))) / \(ChipFormat.string(definition.threshold))")
                    .font(.numeric(13, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                Spacer()
                if claimed {
                    Label("Erhalten", systemImage: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.success)
                } else if unlocked {
                    Button("+\(ChipFormat.string(definition.rewardChips))", action: onClaim)
                        .buttonStyle(.casino(.gold, size: .small))
                } else {
                    Text("+\(ChipFormat.string(definition.rewardChips))")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 22)
        .opacity(unlocked || value > 0 ? 1 : 0.75)
    }
}
