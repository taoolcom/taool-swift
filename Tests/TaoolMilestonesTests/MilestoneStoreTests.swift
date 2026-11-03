// Copyright (c) 2026 Primetic
// SPDX-License-Identifier: MIT
// TaoolKit: https://taool.com/docs

import Foundation
import TaoolCore
import Testing
@testable import TaoolMilestones

@MainActor
struct MilestoneStoreTests {
    private let url = FileManager.default.temporaryDirectory.appending(path: "taoolkit-\(UUID())/milestones.json")
    private static let app = AppTransactionFacts(signed: "app.jws.sig", id: "7001", environment: .production, downloadedAt: nil)

    /// A store keeping its state at `url`, on `account` (nil while StoreKit can't say), the check-in counted in `sends`.
    private func store(account: AppTransactionFacts? = app, checksIn: Bool = true, sends: Sends = Sends()) -> MilestoneStore {
        MilestoneStore(file: StateFile(url: url), appTransaction: { account }, checksIn: { checksIn },
                       send: { sends.count += 1 }, delay: .milliseconds(10))
    }

    @MainActor final class Sends { var count = 0 }

    @Test func aMilestone_isKeptOnce_thenSentSoon() async throws {
        let sends = Sends()
        let store = store(sends: sends)
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(await store.record("onboarding-done", at: first))
        #expect(await store.record("onboarding-done", at: first.addingTimeInterval(60)) == false, "only the first time is kept")
        #expect(store.hasPending)
        // Waited for rather than slept past, since another suite can hold the main actor the send runs on.
        for _ in 0..<200 where sends.count == 0 { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(sends.count == 1, "the check-in asked for once, a moment after")

        let next = store.nextMilestones(for: "7001")
        #expect(next == [.init(name: "onboarding-done", at: first)])
        store.checkedIn(next, account: "7001")
        #expect(!store.hasPending && store.nextMilestones(for: "7001").isEmpty)
        // Kept across launches: never again.
        #expect(await self.store().record("onboarding-done", at: .now) == false)
    }

    @Test func aName_isOneWhateverItsCase() async {
        let store = store()
        #expect(await store.record("onboarding-done", at: .now))
        #expect(await store.record("Onboarding-Done", at: .now) == false)
        #expect(await store.record("first_export", at: .now), "underscores too, as goals' names take them")
    }

    @Test func onlyTheAppleAccountStoreKitSays_waits() async {
        let store = store()
        await store.record("onboarding-done", at: .now)
        #expect(store.hasPending)
        // The App Store build installed over TestFlight's: another Apple Account, which has nothing to send.
        #expect(store.nextMilestones(for: "7002").isEmpty)
        #expect(!store.hasPending, "the other's never makes every launch check in")
        // Before StoreKit has said anything, nothing waits either.
        let fresh = MilestoneStore(file: StateFile(url: FileManager.default.temporaryDirectory.appending(path: "taoolkit-\(UUID())/m.json")),
                                   appTransaction: { nil }, checksIn: { true }, send: {}, delay: .seconds(60))
        #expect(await fresh.record("demo-used", at: .now))
        #expect(!fresh.hasPending)
    }

    @Test func eachAppleAccount_hasItsOwn() async {
        let store = store()
        await store.record("onboarding-done", at: .now)
        store.checkedIn(store.nextMilestones(for: "7001"), account: "7001")
        let other = AppTransactionFacts(signed: "other.jws.sig", id: "7002", environment: .production, downloadedAt: nil)
        #expect(await self.store(account: other).record("onboarding-done", at: .now), "another Apple Account on the device reached it too")
    }

    @Test func beforeStoreKitSays_theFirstAppleAccountItSaysGetsThem() async {
        let early = store(account: nil)
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(await early.record("demo-used", at: at))
        #expect(!early.hasPending, "nothing proves whose they are yet, so nothing makes a check-in go")
        let later = store()
        #expect(later.nextMilestones(for: "7001") == [.init(name: "demo-used", at: at)])
        #expect(later.saved.unclaimed.isEmpty)
    }

    @Test func notANameOrAnalyticsOff_keepsNothing() async {
        #expect(await store().record("not a name!", at: .now) == false)
        #expect(await store(checksIn: false).record("onboarding-done", at: .now) == false)
        #expect(!store().hasPending)
    }

    @Test func aCheckInCarriesFifty_theOldestFirst_theRestNext() async {
        let store = store()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<60 { await store.record("step_\(i)", at: start.addingTimeInterval(Double(i))) }
        let first = store.nextMilestones(for: "7001")
        #expect(first.count == MilestoneStore.maxPerCheckIn && first.first?.name == "step_0" && first.last?.name == "step_49")
        store.checkedIn(first, account: "7001")
        let rest = store.nextMilestones(for: "7001")
        #expect(rest.count == 10 && rest.first?.name == "step_50", "taool's limit is the server's, never the device's")
        store.checkedIn(rest, account: "7001")
        #expect(store.nextMilestones(for: "7001").isEmpty)
    }

    @Test func namesMadeUpPerUserStopAtTheGuard() async {
        let full = (0..<MilestoneStore.maxPerAccount).map { ("user-\($0)", MilestoneStore.Reached(at: .now)) }
        StateFile<MilestoneStore.Saved>(url: url).write(.init(accounts: ["7001": Dictionary(uniqueKeysWithValues: full)],
                                                              unclaimed: ["offline-new": .now, "user-0": .distantPast], account: "7001"))
        let store = store()
        #expect(await store.record("user-new", at: .now) == false)
        // What was reached offline joins within the guard too: an earlier time for a kept name, never a new one past it.
        _ = store.nextMilestones(for: "7001")
        #expect(store.saved.accounts["7001"]?.count == MilestoneStore.maxPerAccount)
        #expect(store.saved.accounts["7001"]?["user-0"]?.at == .distantPast && store.saved.accounts["7001"]?["offline-new"] == nil)
    }
}
