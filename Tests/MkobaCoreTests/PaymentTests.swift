import XCTest
@testable import MkobaCore

final class PaymentTests: XCTestCase {
    let credentials = Daraja.Credentials(consumerKey: "key", consumerSecret: "secret",
                                         shortCode: Daraja.sandboxShortCode, passkey: "passkey")

    func testPhoneNormalisation() {
        XCTAssertEqual(PhoneNumber("0712 345 678")?.msisdn, "254712345678")
        XCTAssertEqual(PhoneNumber("+254712345678")?.msisdn, "254712345678")
        XCTAssertEqual(PhoneNumber("254112345678")?.msisdn, "254112345678")
        XCTAssertEqual(PhoneNumber("712345678")?.msisdn, "254712345678")
        XCTAssertEqual(PhoneNumber("0712345678")?.local, "0712 345 678")
        XCTAssertNil(PhoneNumber("0812345678"))
        XCTAssertNil(PhoneNumber("071234567"))
        XCTAssertNil(PhoneNumber("hello"))
    }

    func testStkPushRequestMatchesDarajaWireFormat() throws {
        let date = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 03:00 Nairobi
        let request = try Daraja.StkPushRequest(
            credentials: credentials, amount: .kes(2_000), phone: PhoneNumber("0712345678")!,
            callback: URL(string: "https://mkoba.example/payments/callback")!,
            accountReference: "UMOJA-CYCLE-0-LONG", description: "Umoja Jan contribution", at: date)

        XCTAssertEqual(request.timestamp, "20260101030000")
        XCTAssertEqual(request.password, Data("174379passkey20260101030000".utf8).base64EncodedString())
        XCTAssertEqual(request.amount, 2_000)
        XCTAssertEqual(request.accountReference, "UMOJA-CYCLE-")
        XCTAssertEqual(request.transactionDesc.count, 13)

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(json?["BusinessShortCode"] as? String, "174379")
        XCTAssertEqual(json?["TransactionType"] as? String, "CustomerPayBillOnline")
        XCTAssertEqual(json?["PhoneNumber"] as? String, "254712345678")
        XCTAssertEqual(json?["Amount"] as? Int, 2_000)
    }

    func testStkPushRejectsCents() {
        XCTAssertThrowsError(try Daraja.StkPushRequest(
            credentials: credentials, amount: .kes(10, cents: 50), phone: PhoneNumber("0712345678")!,
            callback: URL(string: "https://x.example/cb")!, accountReference: "A", description: "B"))
    }

    func testCredentialsBasicAuth() {
        XCTAssertEqual(credentials.basicAuthorization, "Basic a2V5OnNlY3JldA==")
    }

    static let successCallback = """
    {"Body":{"stkCallback":{"MerchantRequestID":"29115-34620561-1","CheckoutRequestID":"ws_CO_191220191020363925",
    "ResultCode":0,"ResultDesc":"The service request is processed successfully.",
    "CallbackMetadata":{"Item":[{"Name":"Amount","Value":2000.00},{"Name":"MpesaReceiptNumber","Value":"NLJ7RT61SV"},
    {"Name":"TransactionDate","Value":20191219102115},{"Name":"PhoneNumber","Value":254712345678}]}}}}
    """

    static let cancelledCallback = """
    {"Body":{"stkCallback":{"MerchantRequestID":"29115-34620561-1","CheckoutRequestID":"ws_CO_191220191020363925",
    "ResultCode":1032,"ResultDesc":"Request cancelled by user"}}}
    """

    func testDecodesSuccessCallbackWithMixedValueTypes() throws {
        let callback = try JSONDecoder().decode(Daraja.Callback.self, from: Data(Self.successCallback.utf8))
        XCTAssertTrue(callback.succeeded)
        let receipt = try XCTUnwrap(callback.receipt())
        XCTAssertEqual(receipt.number, "NLJ7RT61SV")
        XCTAssertEqual(receipt.amount, .kes(2_000))
        XCTAssertEqual(receipt.phone.msisdn, "254712345678")
        XCTAssertEqual(receipt.transactionDate, "20191219102115")
    }

    func testDecodesFailureCallbackWithoutMetadata() throws {
        let callback = try JSONDecoder().decode(Daraja.Callback.self, from: Data(Self.cancelledCallback.utf8))
        XCTAssertFalse(callback.succeeded)
        XCTAssertNil(callback.receipt())
        XCTAssertEqual(Daraja.ResultCode(rawValue: callback.resultCode), .cancelledByUser)
        XCTAssertTrue(Daraja.ResultCode.cancelledByUser.isRetryable)
        XCTAssertFalse(Daraja.ResultCode.insufficientFunds.isRetryable)
    }

    // MARK: - Pending payment state machine

    func makePayment() -> PendingPayment {
        PendingPayment(group: GroupID(), member: MemberID(), amount: .kes(2_000), cycle: CycleID(0),
                       phone: PhoneNumber("0712345678")!, createdAt: Date(timeIntervalSince1970: 0))
    }

    func testHappyPathProducesExactlyOneLedgerEvent() throws {
        var payment = makePayment()
        XCTAssertNil(payment.ledgerEventKind())
        XCTAssertTrue(payment.canSendPrompt)

        payment = try payment.promptSent(checkoutRequestID: "ws_CO_191220191020363925", at: Date(timeIntervalSince1970: 1))
        XCTAssertFalse(payment.canSendPrompt, "never fire a second prompt while one is live")
        XCTAssertThrowsError(try payment.promptSent(checkoutRequestID: "again", at: Date()))

        let callback = try JSONDecoder().decode(Daraja.Callback.self, from: Data(Self.successCallback.utf8))
        payment = try payment.callbackReceived(callback, at: Date(timeIntervalSince1970: 20))
        guard case .completed(let receipt) = payment.status else { return XCTFail("expected completed") }
        XCTAssertEqual(receipt.number, "NLJ7RT61SV")
        XCTAssertEqual(payment.attempts, 1)

        guard case .contributionRecorded(_, let amount, _, let reference)? = payment.ledgerEventKind() else {
            return XCTFail("expected contribution event")
        }
        XCTAssertEqual(amount, .kes(2_000))
        XCTAssertEqual(reference?.mpesaReceipt, "NLJ7RT61SV")
    }

    func testCallbackForDifferentCheckoutIsIgnored() throws {
        var payment = makePayment()
        payment = try payment.promptSent(checkoutRequestID: "ws_CO_other", at: Date())
        let callback = try JSONDecoder().decode(Daraja.Callback.self, from: Data(Self.successCallback.utf8))
        XCTAssertThrowsError(try payment.callbackReceived(callback, at: Date())) { error in
            XCTAssertEqual(error as? PaymentError, .unknownCheckout("ws_CO_191220191020363925"))
        }
    }

    func testSilenceBecomesUnknownNotFailed() throws {
        var payment = makePayment()
        payment = try payment.promptSent(checkoutRequestID: "ws_CO_1", at: Date(timeIntervalSince1970: 0))
        payment = payment.tick(now: Date(timeIntervalSince1970: 60))
        XCTAssertEqual(payment.status, .promptSent(checkoutRequestID: "ws_CO_1"), "still within timeout")
        payment = payment.tick(now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(payment.status, .unknown(checkoutRequestID: "ws_CO_1"))
        XCTAssertFalse(payment.canSendPrompt, "unknown must be resolved before retry")
        XCTAssertTrue(payment.needsStatusQuery)
        XCTAssertNil(payment.ledgerEventKind())
    }

    func testUnknownResolvesInAllThreeWays() throws {
        let unknown = try makePayment()
            .promptSent(checkoutRequestID: "ws_CO_1", at: Date(timeIntervalSince1970: 0))
            .tick(now: Date(timeIntervalSince1970: 1_000))

        let paid = try unknown.resolved(.paid(MpesaReceipt(number: "ABC", amount: .kes(2_000),
                                                           phone: PhoneNumber("0712345678")!, transactionDate: "")),
                                        at: Date())
        XCTAssertNotNil(paid.ledgerEventKind())
        XCTAssertFalse(paid.canSendPrompt)

        let failed = try unknown.resolved(.failed(code: 1, description: "Insufficient funds"), at: Date())
        XCTAssertFalse(failed.canSendPrompt)

        let lost = try unknown.resolved(.notFound, at: Date())
        XCTAssertEqual(lost.status, .requested)
        XCTAssertTrue(lost.canSendPrompt, "a push Daraja never saw is safe to resend")
        XCTAssertEqual(lost.attempts, 1)

        XCTAssertThrowsError(try paid.resolved(.notFound, at: Date()))
    }

    func testRetryableFailureAllowsNewPrompt() throws {
        var payment = try makePayment().promptSent(checkoutRequestID: "ws_CO_191220191020363925", at: Date())
        let cancelled = try JSONDecoder().decode(Daraja.Callback.self, from: Data(Self.cancelledCallback.utf8))
        payment = try payment.callbackReceived(cancelled, at: Date())
        XCTAssertTrue(payment.canSendPrompt)
        payment = try payment.promptSent(checkoutRequestID: "ws_CO_2", at: Date())
        XCTAssertEqual(payment.attempts, 2)
    }

    func testPendingPaymentCodableRoundTrip() throws {
        let payment = try makePayment().promptSent(checkoutRequestID: "ws_CO_1", at: Date(timeIntervalSince1970: 5))
        let data = try JSONEncoder().encode(payment)
        XCTAssertEqual(try JSONDecoder().decode(PendingPayment.self, from: data), payment)
    }
}
