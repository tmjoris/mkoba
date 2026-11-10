import MkobaCore
import SwiftUI

enum Theme {
    static let green = Color(red: 0.0, green: 0.42, blue: 0.31)
    static let gold = Color(red: 0.85, green: 0.65, blue: 0.13)
    static let danger = Color(red: 0.75, green: 0.16, blue: 0.16)
}

extension Money {
    /// "KES 2,000" when there are no cents, otherwise "KES 2,000.50". Views only.
    var display: String {
        minorPart == 0 ? "\(currency.code) \(formatted(showCode: false).dropLast(3))" : formatted()
    }
}

struct MoneyText: View {
    let amount: Money
    var font: Font = .body
    var body: some View {
        Text(amount.display)
            .font(font.monospacedDigit())
            .foregroundStyle(amount.isNegative ? Theme.danger : .primary)
    }
}

/// Amount entry that only ever produces whole shillings, which is what M-Pesa accepts.
struct ShillingField: View {
    let title: String
    @Binding var shillings: Int64?

    var body: some View {
        HStack {
            Text("KES").foregroundStyle(.secondary)
            TextField(title, value: $shillings, format: .number.grouping(.automatic))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("amount-field")
        }
    }
}

struct ErrorBanner: View {
    let message: String?
    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.danger, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("error-banner")
        }
    }
}
