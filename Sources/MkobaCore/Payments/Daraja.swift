import Foundation

/// Safaricom Daraja "Lipa na M-Pesa Online" (STK push) request and callback types.
/// Field names follow Daraja's PascalCase JSON exactly.
public enum Daraja {
    public static let sandboxBase = URL(string: "https://sandbox.safaricom.co.ke")!
    public static let productionBase = URL(string: "https://api.safaricom.co.ke")!

    /// Daraja's well known sandbox paybill.
    public static let sandboxShortCode = "174379"

    public struct Credentials: Sendable {
        public let consumerKey: String
        public let consumerSecret: String
        public let shortCode: String
        public let passkey: String

        public init(consumerKey: String, consumerSecret: String, shortCode: String, passkey: String) {
            self.consumerKey = consumerKey
            self.consumerSecret = consumerSecret
            self.shortCode = shortCode
            self.passkey = passkey
        }

        /// Basic auth header for the OAuth token endpoint.
        public var basicAuthorization: String {
            let raw = Data("\(consumerKey):\(consumerSecret)".utf8).base64EncodedString()
            return "Basic \(raw)"
        }

        /// Daraja password: base64(shortcode + passkey + timestamp).
        public func password(timestamp: String) -> String {
            Data((shortCode + passkey + timestamp).utf8).base64EncodedString()
        }
    }

    /// "yyyyMMddHHmmss" in Nairobi time, the only format Daraja accepts.
    public static func timestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Africa/Nairobi")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: date)
    }

    public struct TokenResponse: Codable, Sendable {
        public let accessToken: String
        public let expiresIn: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }

    public struct StkPushRequest: Codable, Sendable, Hashable {
        public let businessShortCode: String
        public let password: String
        public let timestamp: String
        public let transactionType: String
        public let amount: Int64
        public let partyA: String
        public let partyB: String
        public let phoneNumber: String
        public let callBackURL: String
        public let accountReference: String
        public let transactionDesc: String

        enum CodingKeys: String, CodingKey {
            case businessShortCode = "BusinessShortCode"
            case password = "Password"
            case timestamp = "Timestamp"
            case transactionType = "TransactionType"
            case amount = "Amount"
            case partyA = "PartyA"
            case partyB = "PartyB"
            case phoneNumber = "PhoneNumber"
            case callBackURL = "CallBackURL"
            case accountReference = "AccountReference"
            case transactionDesc = "TransactionDesc"
        }

        /// Builds a paybill STK push. Daraja takes whole shillings only, so amounts with
        /// cents are rejected here rather than silently truncated.
        public init(credentials: Credentials, amount: Money, phone: PhoneNumber, callback: URL,
                    accountReference: String, description: String, at date: Date = Date()) throws {
            guard amount.currency == .kes else { throw MoneyError.currencyMismatch(amount.currency, .kes) }
            guard amount.isPositive, amount.minorPart == 0 else { throw PaymentError.wholeShillingsOnly }
            let stamp = Daraja.timestamp(date)
            businessShortCode = credentials.shortCode
            password = credentials.password(timestamp: stamp)
            timestamp = stamp
            transactionType = "CustomerPayBillOnline"
            self.amount = amount.majorPart
            partyA = phone.msisdn
            partyB = credentials.shortCode
            phoneNumber = phone.msisdn
            callBackURL = callback.absoluteString
            self.accountReference = String(accountReference.prefix(12))
            transactionDesc = String(description.prefix(13))
        }
    }

    public struct StkPushResponse: Codable, Sendable, Hashable {
        public let merchantRequestID: String
        public let checkoutRequestID: String
        public let responseCode: String
        public let responseDescription: String
        public let customerMessage: String

        public init(merchantRequestID: String, checkoutRequestID: String, responseCode: String,
                    responseDescription: String, customerMessage: String) {
            self.merchantRequestID = merchantRequestID
            self.checkoutRequestID = checkoutRequestID
            self.responseCode = responseCode
            self.responseDescription = responseDescription
            self.customerMessage = customerMessage
        }

        enum CodingKeys: String, CodingKey {
            case merchantRequestID = "MerchantRequestID"
            case checkoutRequestID = "CheckoutRequestID"
            case responseCode = "ResponseCode"
            case responseDescription = "ResponseDescription"
            case customerMessage = "CustomerMessage"
        }

        public var accepted: Bool { responseCode == "0" }
    }

    /// Daraja result codes that matter to a user-facing flow.
    public enum ResultCode: Int, Sendable, Hashable {
        case success = 0
        case insufficientFunds = 1
        case lessThanMinimum = 17
        case moreThanMaximum = 1025
        case cancelledByUser = 1032
        case timeout = 1037
        case wrongPIN = 2001
        case expired = 1019
        case subscriberBusy = 1001

        public var isRetryable: Bool {
            switch self {
            case .timeout, .expired, .subscriberBusy, .cancelledByUser, .wrongPIN: return true
            case .success, .insufficientFunds, .lessThanMinimum, .moreThanMaximum: return false
            }
        }
    }

    /// The POST Daraja sends to `CallBackURL`.
    public struct Callback: Codable, Sendable, Hashable {
        public struct Body: Codable, Sendable, Hashable {
            public let stkCallback: StkCallback
            public init(stkCallback: StkCallback) { self.stkCallback = stkCallback }
        }

        public struct StkCallback: Codable, Sendable, Hashable {
            public let merchantRequestID: String
            public let checkoutRequestID: String
            public let resultCode: Int
            public let resultDesc: String
            public let callbackMetadata: Metadata?

            public init(merchantRequestID: String, checkoutRequestID: String, resultCode: Int, resultDesc: String,
                        callbackMetadata: Metadata?) {
                self.merchantRequestID = merchantRequestID
                self.checkoutRequestID = checkoutRequestID
                self.resultCode = resultCode
                self.resultDesc = resultDesc
                self.callbackMetadata = callbackMetadata
            }

            enum CodingKeys: String, CodingKey {
                case merchantRequestID = "MerchantRequestID"
                case checkoutRequestID = "CheckoutRequestID"
                case resultCode = "ResultCode"
                case resultDesc = "ResultDesc"
                case callbackMetadata = "CallbackMetadata"
            }
        }

        public struct Metadata: Codable, Sendable, Hashable {
            public let item: [Item]
            public init(item: [Item]) { self.item = item }
            enum CodingKeys: String, CodingKey { case item = "Item" }
        }

        /// Items are heterogeneous: Amount is a number, receipt is a string, some have no value.
        public struct Item: Codable, Sendable, Hashable {
            public let name: String
            public let value: Value?

            public init(name: String, value: Value?) {
                self.name = name
                self.value = value
            }

            public enum Value: Codable, Sendable, Hashable {
                case string(String)
                case number(Double)

                public init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let number = try? container.decode(Double.self) {
                        self = .number(number)
                    } else {
                        self = .string(try container.decode(String.self))
                    }
                }

                public func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    switch self {
                    case .string(let text): try container.encode(text)
                    case .number(let number): try container.encode(number)
                    }
                }

                public var text: String {
                    switch self {
                    case .string(let text): return text
                    case .number(let number):
                        return number == number.rounded() ? String(Int64(number)) : String(number)
                    }
                }
            }

            enum CodingKeys: String, CodingKey {
                case name = "Name"
                case value = "Value"
            }
        }

        public let body: Body
        public init(body: Body) { self.body = body }
        enum CodingKeys: String, CodingKey { case body = "Body" }

        public var checkoutRequestID: String { body.stkCallback.checkoutRequestID }
        public var resultCode: Int { body.stkCallback.resultCode }
        public var succeeded: Bool { resultCode == 0 }

        private func metadata(_ name: String) -> String? {
            body.stkCallback.callbackMetadata?.item.first { $0.name == name }?.value?.text
        }

        /// Proof of payment, present only on success.
        public func receipt() -> MpesaReceipt? {
            guard succeeded,
                  let amountText = metadata("Amount"),
                  let amount = Int64(amountText.split(separator: ".").first ?? ""),
                  let receipt = metadata("MpesaReceiptNumber"),
                  let phoneText = metadata("PhoneNumber"),
                  let phone = PhoneNumber(phoneText) else {
                return nil
            }
            return MpesaReceipt(number: receipt, amount: .kes(amount), phone: phone,
                                transactionDate: metadata("TransactionDate") ?? "")
        }
    }
}

public struct MpesaReceipt: Hashable, Sendable, Codable {
    public let number: String
    public let amount: Money
    public let phone: PhoneNumber
    /// Daraja's "yyyyMMddHHmmss" string, kept verbatim for audit.
    public let transactionDate: String

    public init(number: String, amount: Money, phone: PhoneNumber, transactionDate: String) {
        self.number = number
        self.amount = amount
        self.phone = phone
        self.transactionDate = transactionDate
    }

    public var reference: PaymentReference { PaymentReference(mpesaReceipt: number) }
}

public enum PaymentError: Error, Hashable, Sendable {
    case wholeShillingsOnly
    case rejectedByDaraja(code: String, description: String)
    case unknownCheckout(String)
    case invalidTransition
}
