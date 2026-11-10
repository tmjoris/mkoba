import MkobaCore
import SwiftUI

struct GroupListView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCreate = false

    var body: some View {
        NavigationStack {
            Group {
                if model.groups.isEmpty {
                    ContentUnavailableView {
                        Label("No chama yet", systemImage: "person.3")
                    } description: {
                        Text("Create a group to start recording contributions, even offline.")
                    } actions: {
                        Button("Create a chama") { showingCreate = true }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("create-group-empty")
                    }
                } else {
                    List(model.groups) { group in
                        NavigationLink(value: group.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name).font(.headline)
                                HStack {
                                    Text("\(group.members) members").foregroundStyle(.secondary)
                                    Spacer()
                                    MoneyText(amount: group.pot, font: .subheadline.weight(.semibold))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("group-row-\(group.name)")
                    }
                }
            }
            .navigationTitle("Mkoba")
            .navigationDestination(for: GroupID.self) { id in
                GroupDashboardView(groupID: id)
            }
            .toolbar {
                Button { showingCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("create-group")
            }
            .sheet(isPresented: $showingCreate) { CreateGroupView() }
            .task { await model.load() }
            .safeAreaInset(edge: .bottom) { ErrorBanner(message: model.lastError).padding() }
        }
    }
}

struct CreateGroupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var myName = ""
    @State private var myPhone = ""
    @State private var amount: Int64? = 2_000
    @State private var lateFee: Int64? = 200
    @State private var frequency: ContributionSchedule.Frequency = .monthly
    @State private var error: String?
    @State private var saving = false

    private var phone: PhoneNumber? { PhoneNumber(myPhone) }
    private var valid: Bool { !name.isEmpty && !myName.isEmpty && phone != nil && (amount ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    TextField("Group name", text: $name).accessibilityIdentifier("group-name")
                    Picker("Contribute", selection: $frequency) {
                        ForEach(ContributionSchedule.Frequency.allCases, id: \.self) {
                            Text($0.rawValue.capitalized)
                        }
                    }
                    ShillingField(title: "Amount per cycle", shillings: $amount)
                    ShillingField(title: "Late fee", shillings: $lateFee)
                }
                Section("You (chair)") {
                    TextField("Your name", text: $myName).accessibilityIdentifier("my-name")
                    TextField("M-Pesa number", text: $myPhone)
                        .keyboardType(.phonePad)
                        .accessibilityIdentifier("my-phone")
                    if !myPhone.isEmpty && phone == nil {
                        Text("Enter a Safaricom or Airtel number, e.g. 0712 345 678")
                            .font(.footnote).foregroundStyle(Theme.danger)
                    }
                }
                ErrorBanner(message: error)
            }
            .navigationTitle("New chama")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(!valid || saving)
                        .accessibilityIdentifier("create-group-confirm")
                }
            }
        }
    }

    private func create() async {
        guard let phone, let amount else { return }
        saving = true
        defer { saving = false }
        let schedule = ContributionSchedule(frequency: frequency, amount: .kes(amount), startDate: Date(),
                                            lateFee: .kes(lateFee ?? 0))
        do {
            try await model.createGroup(name: name, myName: myName, myPhone: phone, schedule: schedule)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
