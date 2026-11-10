import Charts
import MkobaCore
import SwiftUI

struct GroupDashboardView: View {
    @Environment(AppModel.self) private var model
    let groupID: GroupID
    @State private var session: GroupSession?

    var body: some View {
        if let session {
            DashboardContent(session: session)
        } else {
            ProgressView().task {
                session = try? await model.session(for: groupID)
            }
        }
    }
}

private struct DashboardContent: View {
    @Bindable var session: GroupSession

    var body: some View {
        List {
            Section {
                PotCard(session: session)
            }
            Section("Contributions") {
                ContributionChart(data: session.contributionsByCycle())
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                NavigationLink {
                    ContributeView(session: session)
                } label: {
                    Label("Pay my contribution via M-Pesa", systemImage: "iphone.radiowaves.left.and.right")
                }
                .accessibilityIdentifier("contribute-link")
                if session.amOfficial {
                    NavigationLink {
                        RecordCashView(session: session)
                    } label: {
                        Label("Record a cash contribution", systemImage: "banknote")
                    }
                    .accessibilityIdentifier("record-cash-link")
                }
            }
            Section("This cycle") {
                let arrears = session.state.arrears(for: session.currentCycle)
                if arrears.isEmpty {
                    Label("Everyone has paid", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.green)
                } else {
                    ForEach(arrears, id: \.member) { entry in
                        HStack {
                            Text(session.member(entry.member)?.name ?? "Unknown")
                            Spacer()
                            Text("owes").foregroundStyle(.secondary)
                            MoneyText(amount: entry.shortfall)
                        }
                    }
                }
            }
            Section {
                NavigationLink { MembersView(session: session) } label: {
                    Label("Members (\(session.state.members.count))", systemImage: "person.3")
                }
                .accessibilityIdentifier("members-link")
                NavigationLink { LoansView(session: session) } label: {
                    Label("Loans (\(session.state.loans.count))", systemImage: "hand.coins")
                }
                .accessibilityIdentifier("loans-link")
            }
            if !session.state.rejected.isEmpty {
                Section("Rejected entries") {
                    Text("\(session.state.rejected.count) entries were refused by the group rules and are kept for audit.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(session.state.group?.name ?? "Chama")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SyncStatusButton(session: session)
            }
        }
        .refreshable { await session.sync() }
        .task { await session.sync() }
    }
}

private struct PotCard: View {
    let session: GroupSession
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In the pot").font(.subheadline).foregroundStyle(.secondary)
            MoneyText(amount: session.state.pot, font: .system(size: 34, weight: .bold, design: .rounded))
                .accessibilityIdentifier("pot-amount")
            if let schedule = session.state.group?.schedule {
                Text("\(schedule.amount.display) \(schedule.frequency.rawValue), due \(schedule.dueDate(for: session.currentCycle).formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct ContributionChart: View {
    let data: [(cycle: CycleID, total: Money, target: Money)]

    var body: some View {
        Chart {
            ForEach(data, id: \.cycle) { point in
                BarMark(x: .value("Cycle", "C\(point.cycle.index)"),
                        y: .value("Collected", Double(point.total.minor) / 100))
                    .foregroundStyle(point.total >= point.target ? Theme.green : Theme.gold)
            }
            if let target = data.first?.target {
                RuleMark(y: .value("Target", Double(target.minor) / 100))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("target").font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let shillings = value.as(Double.self) {
                        Text(Money.kes(Int64(shillings)).display)
                    }
                }
            }
        }
    }
}

struct SyncStatusButton: View {
    let session: GroupSession
    var body: some View {
        Button { Task { await session.sync() } } label: {
            if session.isSyncing {
                ProgressView()
            } else if session.lastSyncError != nil {
                Image(systemName: "icloud.slash").foregroundStyle(Theme.gold)
            } else {
                Image(systemName: "checkmark.icloud")
            }
        }
        .accessibilityIdentifier("sync-button")
        .accessibilityLabel(session.lastSyncError ?? "Synced")
    }
}
