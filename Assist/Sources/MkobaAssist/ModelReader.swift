import AnyLanguageModel
import Foundation
import MkobaCore

/// The fields a model fills in for one message. Guided generation makes the model's
/// output always decode into this shape; whether the values are right is checked later.
@Generable
struct GeneratedReading {
    @Guide(description: "true if the text says the treasurer received money, or a member says they sent money to the treasurer. false for money sent or paid by the treasurer, withdrawals, airtime, Fuliza, M-Shwari, reversals, balance checks and chat.")
    var isIncomingPayment: Bool

    @Guide(description: "The M-Pesa transaction code copied exactly, usually 10 capital letters and digits. Empty if there is none.")
    var receipt: String

    @Guide(description: "The amount received copied exactly as written, for example Ksh2,000.00 or 2k. Never the balance. Empty if there is none.")
    var amountText: String

    @Guide(description: "The sender's name copied exactly. Empty if there is none.")
    var senderName: String

    @Guide(description: "The sender's phone number copied exactly, including any * characters. Empty if there is none.")
    var senderPhone: String

    @Guide(description: "Only if the text says the money is for a different person than the sender: that person's name copied exactly. Otherwise empty.")
    var paidForName: String

    @Guide(description: "The date and time copied exactly, for example 3/11/26 at 7:42 PM. Empty if there is none.")
    var dateText: String
}

// Outside the struct body: @Generable would treat a property inside it as a field to generate.
extension GeneratedReading {
    var reading: MessageReading {
        MessageReading(isIncomingPayment: isIncomingPayment, receipt: receipt, amountText: amountText,
                       senderName: senderName, senderPhone: senderPhone, paidForName: paidForName,
                       dateText: dateText)
    }
}

/// Reads one pasted message with a language model.
///
/// The model only copies text out of the message; `ImportReviewer` turns that text into an
/// entry and checks it. The same code runs against Apple's on-device model on iOS 26 and
/// against any Ollama model on Linux, which is how it is evaluated.
public struct ModelReader: Sendable {
    public let model: any LanguageModel

    public init(model: any LanguageModel) {
        self.model = model
    }

    public static let instructions = """
        You read text that the treasurer of a chama (a savings group) pasted into a bookkeeping \
        app. Usually it is an M-Pesa SMS, sometimes forwarded with a note, sometimes a member's \
        message. Fill in what it says about money the treasurer received. Copy every value \
        exactly as it appears in the text; do not reformat amounts, names, codes or dates. \
        Leave a field empty when the text does not contain it.
        """

    public func read(_ message: String) async throws -> MessageReading {
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(to: message, generating: GeneratedReading.self,
                                                 options: GenerationOptions(sampling: .greedy))
        return response.content.reading
    }
}
