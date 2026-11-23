import XCTest
@testable import MkobaCore

final class ImportTests: XCTestCase {
    let nairobi = TimeZone(identifier: "Africa/Nairobi")!
    let sms = "TKL3QZ8M2A Confirmed.You have received Ksh2,000.00 from AMINA WANJIKU 0733000222 on 3/11/26 at 7:42 PM New M-PESA balance is Ksh12,340.00. Earn interest daily on Ziidi MMF,Dial *334#"

    // MARK: Parsing

    func testAmountsInTheWaysPeopleWriteThem() {
        XCTAssertEqual(ImportParsing.amount("Ksh2,000.00"), .kes(2_000))
        XCTAssertEqual(ImportParsing.amount("KES 1,250.50"), .kes(1_250, cents: 50))
        XCTAssertEqual(ImportParsing.amount("Sh. 500"), .kes(500))
        XCTAssertEqual(ImportParsing.amount("2000/="), .kes(2_000))
        XCTAssertEqual(ImportParsing.amount("1k"), .kes(1_000))
        XCTAssertEqual(ImportParsing.amount("1.5K"), .kes(1_500))
        XCTAssertNil(ImportParsing.amount("elfu mbili"))
        XCTAssertNil(ImportParsing.amount(""))
    }

    func testDatesAreDayFirst() throws {
        let date = try XCTUnwrap(ImportParsing.date("3/11/26 at 7:42 PM", timeZone: nairobi))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = nairobi
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 11, 3, 19, 42])
        XCTAssertNotNil(ImportParsing.date("03/11/2026", timeZone: nairobi))
        XCTAssertNil(ImportParsing.date("31/2/26", timeZone: nairobi))
        XCTAssertNil(ImportParsing.date("jana jioni", timeZone: nairobi))
    }

    // MARK: Regex reader and splitting

    func testRegexReadsTheStandardMessage() {
        let reading = MpesaSMSReader.read(sms)
        XCTAssertTrue(reading.isIncomingPayment)
        XCTAssertEqual(reading.receipt, "TKL3QZ8M2A")
        XCTAssertEqual(reading.amountText, "Ksh2,000.00")
        XCTAssertEqual(reading.senderName, "AMINA WANJIKU")
        XCTAssertEqual(reading.senderPhone, "0733000222")
        XCTAssertEqual(reading.dateText, "3/11/26 at 7:42 PM")
    }

    func testRegexSkipsMoneySentAndChat() {
        XCTAssertFalse(MpesaSMSReader.read("TKL3QZ8M2B Confirmed. Ksh500.00 sent to BRIAN OTIENO 0744000333 on 3/11/26 at 8:00 PM.").isIncomingPayment)
        XCTAssertFalse(MpesaSMSReader.read("Nimetuma 2k ya chama, code TKL3QZ8M2C").isIncomingPayment)
    }

    func testSplitsBlankLinesAndRunTogetherMessages() {
        let other = sms.replacingOccurrences(of: "TKL3QZ8M2A", with: "TKL3QZ8M2D")
        XCTAssertEqual(MessageSplitter.split("\(sms)\n\n\(other)").count, 2)
        XCTAssertEqual(MessageSplitter.split("\(sms)\(other)"), [sms, other])
        XCTAssertEqual(MessageSplitter.split("  \n\n "), [])
    }

    // MARK: Member matching

    func testPhoneThenName() {
        var chama = ChamaFixture()
        let grace = MemberID()
        chama.log.record(.memberJoined(member: grace, name: "Grace Wanjiku", phone: PhoneNumber("0711222333")!, role: .member),
                         by: chama.chair, on: chama.phone, at: chama.start)
        let members = Array(chama.state.members.values)

        XCTAssertEqual(MemberMatcher.match(name: "SOMEONE ELSE", phone: "0733000222", in: members), .one(chama.amina))
        XCTAssertEqual(MemberMatcher.match(name: "AMINA WANJIKU", phone: "", in: members), .one(chama.amina))
        XCTAssertEqual(MemberMatcher.match(name: "WANJIKU", phone: "07*****333", in: members), .one(grace))
        XCTAssertEqual(MemberMatcher.match(name: "WANJIKU", phone: "", in: members).candidates.count, 1,
                       "Amina in the fixture is just 'Amina', so only Grace has the surname")
        XCTAssertEqual(MemberMatcher.match(name: "PETER KAMAU", phone: "0799000999", in: members), .none)
        // The masked phone says Brian, the name says Grace: a person decides.
        XCTAssertEqual(MemberMatcher.match(name: "GRACE", phone: "0744***333", in: members),
                       .several([chama.brian, grace].sorted()))
    }

    // MARK: Review

    private func reviewOne(_ reading: MessageReading, message: String? = nil, checks: Bool = true,
                           chama: ChamaFixture = ChamaFixture()) -> ImportReview {
        ImportReviewer(checks: checks).review([(message ?? sms, reading)], against: chama.state)[0]
    }

    func testCleanMessageIsReadyToRecord() throws {
        let chama = ChamaFixture()
        let review = reviewOne(MpesaSMSReader.read(sms), chama: chama)
        XCTAssertEqual(review.issues, [])
        XCTAssertEqual(review.decision, .record)
        XCTAssertEqual(review.amount, .kes(2_000))
        XCTAssertEqual(review.cycle, CycleID(10)) // November 2026, group started January 2026
        guard case let .contributionRecorded(member, amount, _, reference) = try XCTUnwrap(review.event) else {
            return XCTFail("expected a contribution")
        }
        XCTAssertEqual(member, chama.amina)
        XCTAssertEqual(amount, .kes(2_000))
        XCTAssertEqual(reference?.mpesaReceipt, "TKL3QZ8M2A")
    }

    func testBalanceTakenForTheAmountIsCaught() {
        var reading = MpesaSMSReader.read(sms)
        reading.amountText = "Ksh12,340.00"
        XCTAssertEqual(reviewOne(reading).issues, [.amountLooksLikeBalance])
        XCTAssertEqual(reviewOne(reading, checks: false).decision, .record, "without checks it would be recorded")
    }

    func testInventedFieldsAreCaught() {
        var reading = MpesaSMSReader.read(sms)
        reading.amountText = "Ksh3,000.00"
        reading.receipt = "TKL3QZ8M2Z"
        reading.senderName = "AMINA ATIENO"
        reading.senderPhone = "0744000333"
        XCTAssertEqual(Set(reviewOne(reading).issues),
                       [.amountNotInMessage, .receiptNotInMessage, .notAConfirmation, .nameNotInMessage,
                        .phoneNotInMessage])
    }

    func testDuplicatesAgainstTheBooksAndWithinThePaste() {
        var chama = ChamaFixture()
        chama.log.record(.contributionRecorded(member: chama.amina, amount: .kes(2_000), cycle: CycleID(10),
                                               reference: PaymentReference(mpesaReceipt: "TKL3QZ8M2A")),
                         by: chama.treasurer, on: chama.phone, at: chama.date(day: 306))
        XCTAssertEqual(reviewOne(MpesaSMSReader.read(sms), chama: chama).issues, [.receiptAlreadyRecorded])

        let reading = MpesaSMSReader.read(sms)
        let reviews = ImportReviewer().review([(sms, reading), (sms, reading)], against: ChamaFixture().state)
        XCTAssertEqual(reviews.map(\.decision), [.record, .check])
        XCTAssertEqual(reviews[1].issues, [.receiptRepeated])
    }

    func testPaidOnSomeoneElsesBehalfMatchesThatMember() {
        let forwarded = "Hii ni ya Amina. TKL3QZ8M2E Confirmed.You have received Ksh2,000.00 from JAMES KARIUKI 0799111222 on 3/11/26 at 7:42 PM New M-PESA balance is Ksh14,340.00."
        let reading = MessageReading(isIncomingPayment: true, receipt: "TKL3QZ8M2E", amountText: "Ksh2,000.00",
                                     senderName: "JAMES KARIUKI", senderPhone: "0799111222", paidForName: "Amina",
                                     dateText: "3/11/26 at 7:42 PM")
        let chama = ChamaFixture()
        let review = reviewOne(reading, message: forwarded, chama: chama)
        XCTAssertEqual(review.member, chama.amina)
        XCTAssertEqual(review.issues, [])
    }

    func testAMembersNoteIsAClaimNotProof() {
        let note = "Nimetuma Ksh 2,000 ya chama. Code TKL3QZ8M2F - Amina"
        let reading = MessageReading(isIncomingPayment: true, receipt: "TKL3QZ8M2F", amountText: "Ksh 2,000",
                                     senderName: "Amina")
        let review = reviewOne(reading, message: note)
        XCTAssertEqual(review.issues, [.notAConfirmation])
        XCTAssertEqual(review.decision, .check)
    }

    func testSwahiliConfirmationAndBalance() {
        let swahili = "TKL3QZ8M2G Imethibitishwa. Umepokea Ksh2,000.00 kutoka AMINA 0733000222 tarehe 3/11/26 saa 7:42 PM. Salio lako jipya la M-PESA ni Ksh9,000.00."
        var reading = MessageReading(isIncomingPayment: true, receipt: "TKL3QZ8M2G", amountText: "Ksh2,000.00",
                                     senderName: "AMINA", senderPhone: "0733000222", dateText: "3/11/26 saa 7:42 PM")
        XCTAssertEqual(reviewOne(reading, message: swahili).issues, [])
        reading.amountText = "Ksh9,000.00"
        XCTAssertEqual(reviewOne(reading, message: swahili).issues, [.amountLooksLikeBalance])
    }

    func testNotAPaymentIsSkipped() {
        XCTAssertEqual(reviewOne(.notAPayment).decision, .skip)
    }
}
