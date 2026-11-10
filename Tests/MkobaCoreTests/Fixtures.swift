import Foundation
@testable import MkobaCore

/// A small chama with a chair, treasurer and two members, built the way the app would.
struct ChamaFixture {
    let group = GroupID()
    let phone = DeviceID("iphone-treasurer")
    let chair = MemberID()
    let treasurer = MemberID()
    let amina = MemberID()
    let brian = MemberID()
    let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 UTC
    var log: EventLog

    init(policy: LoanPolicy = .saccoDefault) {
        log = EventLog(group: group)
        let schedule = ContributionSchedule(frequency: .monthly, amount: .kes(2_000), startDate: start,
                                            lateFee: .kes(200))
        log.record(.groupCreated(name: "Umoja Chama", currency: .kes, schedule: schedule, loanPolicy: policy),
                   by: chair, on: phone, at: start)
        log.record(.memberJoined(member: chair, name: "Wanjiru", phone: PhoneNumber("0712345678")!, role: .chair),
                   by: chair, on: phone, at: start)
        log.record(.memberJoined(member: treasurer, name: "Otieno", phone: PhoneNumber("0722000111")!, role: .treasurer),
                   by: chair, on: phone, at: start)
        log.record(.memberJoined(member: amina, name: "Amina", phone: PhoneNumber("0733000222")!, role: .member),
                   by: chair, on: phone, at: start)
        log.record(.memberJoined(member: brian, name: "Brian", phone: PhoneNumber("0744000333")!, role: .member),
                   by: chair, on: phone, at: start)
    }

    func date(day: Int) -> Date { start.addingTimeInterval(TimeInterval(day) * 86_400) }

    @discardableResult
    mutating func contribute(_ member: MemberID, _ amount: Money, cycle: Int, day: Int = 1) -> LedgerEvent {
        log.record(.contributionRecorded(member: member, amount: amount, cycle: CycleID(cycle), reference: nil),
                   by: treasurer, on: phone, at: date(day: day))
    }

    var state: LedgerState { log.replay() }
}
