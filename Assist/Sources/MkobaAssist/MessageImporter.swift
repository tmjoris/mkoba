import AnyLanguageModel
import Foundation
import MkobaCore

/// Reads a paste of M-Pesa messages on this device and checks each one against the books.
///
/// The regex reader handles the standard SMS. On an iPhone with Apple Intelligence on,
/// whatever it cannot read goes to Apple's on-device model; otherwise that is left for the
/// treasurer. Either way nothing leaves the phone, and nothing is recorded until the
/// treasurer taps Record.
public struct MessageImporter: Sendable {
    public enum Engine: Sendable, Equatable {
        case onDeviceModel
        case rules
    }

    public let engine: Engine
    private let reader: ModelReader?

    public init(reader: ModelReader?) {
        self.reader = reader
        engine = reader == nil ? .rules : .onDeviceModel
    }

    /// Apple's on-device model when it is ready on this device, else the rules.
    public static func best() -> MessageImporter {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                let model = SystemLanguageModel.default
                if model.isAvailable {
                    return MessageImporter(reader: ModelReader(model: model))
                }
            }
        #endif
        return MessageImporter(reader: nil)
    }

    public func review(paste: String, against state: LedgerState, now: Date = Date()) async -> [ImportReview] {
        var items: [(message: String, reading: MessageReading)] = []
        for message in MessageSplitter.split(paste) {
            items.append((message, await read(message)))
        }
        return ImportReviewer().review(items, against: state, now: now)
    }

    /// Rules first: the regex reads the standard SMS exactly and instantly, so the model only
    /// sees what the rules cannot read (notes, Swahili, text mangled in copying).
    private func read(_ message: String) async -> MessageReading {
        let rules = MpesaSMSReader.read(message)
        guard let reader, !rules.isIncomingPayment else { return rules }
        do {
            return try await reader.read(message)
        } catch {
            // A failed read must not quietly drop a payment: show it to the treasurer to check.
            return MessageReading(isIncomingPayment: true)
        }
    }
}
