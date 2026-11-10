# Mkoba

[![CI](https://github.com/tmjoris/mkoba/actions/workflows/ci.yml/badge.svg)](https://github.com/tmjoris/mkoba/actions/workflows/ci.yml)

Offline-first chama (group savings) app for iOS, with M-Pesa contributions and SACCO-style lending.

A chama is a Kenyan savings group: members contribute on a schedule, the pot funds loans
guaranteed by other members, and the treasurer keeps the books. Mkoba replaces the exercise
book. It is built the way a bank would build it: every shilling is an integer, every change
is an immutable event, and the phone works in a village with no signal.

```
Sources/MkobaCore     Pure Swift 6. Money, event-sourced ledger, sync, Daraja types. Builds on Linux.
Server/               Vapor API: sync endpoint, M-Pesa STK push, callback, reconciliation.
iOS/                  SwiftUI app (MVVM), Core Data event store, Swift Charts, XCTest + XCUITest.
```

## What is interesting about it

**Money is never a `Double`.** `Money` is `Int64` minor units plus a currency. Adding,
multiplying by a rate in basis points, and splitting into instalments are all exact, and a
split of KES 100 three ways gives 33.34, 33.33, 33.33 that sums back to 100.00.

**The ledger is an append-only event log.** Nothing is edited or deleted. State is a fold
over events, so the app can answer "what did the books say on 3 March" and an auditor can
see every refused entry with the reason it was refused.

**Two treasurers can both be offline and still agree.** Each event carries a Lamport
timestamp and a device id, giving a total order every device agrees on. Replay is
deterministic: the test suite shuffles events 50 ways, injects duplicates, and asserts the
identical state each time. Validation runs at replay time, not at write time, because an
offline phone cannot know the latest state. A payout recorded on a phone that saw KES 2,000
in the pot is accepted after sync if the merged pot covers it, and rejected otherwise, on
every device the same way.

**Sync is a vector-clock diff.** A phone sends "here is what I have seen and here is what is
new"; the server merges and answers with only what the phone lacks. No timestamps compared
across devices, no last-write-wins.

**M-Pesa payments cannot double-charge.** A contribution goes `requested -> promptSent ->
completed | failed`, and if Daraja's callback never arrives it becomes `unknown`, never
`failed`. No second STK prompt can be sent until a transaction status query says the first
one is dead. Duplicate callbacks (Daraja retries them) are no-ops. Only a completed payment
writes to the ledger, and it writes exactly once. The server test suite drives all of these
through a Daraja simulator where the phone number's last two digits choose the outcome
(`..11` cancel, `..22` insufficient funds, `..33` lost callback then paid, `..44` lost
callback and never seen).

**The receipt is the authority.** Cash contributions need an official's signature. An M-Pesa
receipt is its own proof, so a member may record their own paid contribution.

## Running the core and server on Linux or macOS

```sh
swift test                         # 36 tests: money, ledger, schedule, Daraja, state machine
cd Server && swift test            # end-to-end payment flows against the simulator
cd Server && swift run             # http://127.0.0.1:8080, data in Server/data/store.json
```

Point it at the real Daraja sandbox with:

```sh
export DARAJA_CONSUMER_KEY=... DARAJA_CONSUMER_SECRET=... DARAJA_PASSKEY=...
export PUBLIC_BASE_URL=https://<your-tunnel>   # Daraja must be able to POST the callback
swift run
```

## Running the iOS app

Requires Xcode 16 on macOS.

```sh
brew install xcodegen
cd iOS && xcodegen generate && open Mkoba.xcodeproj
```

The `Mkoba` scheme runs the unit tests (Core Data store, session) and the UI tests, which
create a group, add a member and record a contribution entirely offline against an in-memory
store. CI does the same on a macOS runner.

## Architecture

```
 SwiftUI views ──▶ GroupSession (@Observable)  ──▶ EventLog + LedgerState (MkobaCore)
                        │  record()  │ sync()
                        ▼            ▼
              CoreDataEventStore   APIClient ──HTTPS──▶ Vapor /v1/groups/:id/sync
              (events as JSON,                              │
               unique by id)                                ▼
                                                      Store (actor) ──▶ EventLog.serve()
 ContributeView ──▶ ContributeViewModel ──▶ /v1/payments ──▶ PaymentService
                                                               │ STK push
                                                               ▼
                                                   DarajaGateway (live | simulator)
                                                               │ callback / status query
                                                               ▼
                                                   PendingPayment state machine ──▶ ledger (once)
```

- **Pattern:** MVVM. Views are dumb; `GroupSession` and `ContributeViewModel` hold state.
- **Persistence:** Core Data with a uniqueness constraint on event id, file protection
  `completeUntilFirstUserAuthentication`, `NSMergeByPropertyObjectTrumpMergePolicy` so a
  duplicate insert is a no-op.
- **Keychain:** the device identity that stamps events lives in the Keychain,
  `AfterFirstUnlockThisDeviceOnly`, never in iCloud.
- **Networking:** `URLSession` with App Transport Security at its default (no exceptions).
- **Concurrency:** Swift 6 strict concurrency; the server store is an actor.
- **Tests:** XCTest for the core and server, XCUITest for the three main flows.

## Status

- [x] Core ledger, money, sync, Daraja types, payment state machine (Linux CI)
- [x] Vapor server with simulator and sandbox support
- [x] iOS app: groups, dashboard, members, contribute, cash, loans; unit and UI tests green on a macOS runner
- [ ] Screenshots
- [ ] TestFlight
