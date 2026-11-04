// Copyright (c) 2026 Primetic
// SPDX-License-Identifier: MIT
// TaoolKit: https://taool.com/docs

import Foundation
import os
import TaoolAnalytics
import TaoolCore

/// The milestones this device recorded, kept in a file, each Apple Account's apart (by its appTransactionID): when it first
/// reached each, and whether taool has it. Each goes once, in the check-in (`CheckIns`), which carries them only beside the signed
/// AppTransaction that proves the Apple Account, goes at once while one waits, and keeps them on the device while it fails.
@MainActor
final class MilestoneStore: MilestonesCheckInPart {
    static let shared = MilestoneStore()

    struct Reached: Codable, Equatable, Sendable {
        var at: Date
        var sent = false
    }

    struct Saved: FileState {
        /// Each Apple Account's milestones on this device, by its appTransactionID.
        var accounts: [String: [String: Reached]] = [:]
        /// Reached before StoreKit said which Apple Account this is (offline at a first launch): the first it says gets them.
        var unclaimed: [String: Date] = [:]
        /// The Apple Account StoreKit last said this is: only its milestones wait to be sent, never another's left from before.
        var account: String?
    }

    /// The most milestones one check-in carries, as taool takes them; more go in the check-ins that follow.
    static let maxPerCheckIn = 50
    /// Only a guard against names made up per user (an ID, a date), past what taool keeps of an app's, never its limit, with room
    /// for taool to raise that without a TaoolKit release.
    static let maxPerAccount = 100

    private let file: StateFile<Saved>
    private(set) var saved: Saved
    private let appTransaction: @MainActor () async -> AppTransactionFacts?
    private let checksIn: @MainActor () -> Bool
    private let send: @MainActor () async -> Void
    private let delay: Duration
    private let log = Logger(subsystem: "TaoolKit", category: "milestones")
    private var sendScheduled = false

    /// `appTransaction`, `checksIn` and `send`: StoreKit's, and the check-in's say and its sending, unless a test says otherwise.
    /// `delay`: how long a new milestone waits, so a screen's few go in one check-in.
    init(file: StateFile<Saved> = .inAppSupport("milestones.json"),
         appTransaction: @escaping @MainActor () async -> AppTransactionFacts? = { await AppTransactionFacts.read() },
         checksIn: @escaping @MainActor () -> Bool = { CheckIns.shared.checksIn },
         send: @escaping @MainActor () async -> Void = { await CheckIns.shared.checkIn(.milestone) },
         delay: Duration = .seconds(2)) {
        self.file = file
        self.appTransaction = appTransaction
        self.checksIn = checksIn
        self.send = send
        self.delay = delay
        saved = file.read() ?? Saved()
    }

    /// A milestone reached at `at`: kept for this Apple Account the first time, then sent soon. False when it isn't kept: a name
    /// that isn't one, one this Apple Account reached before, or the app's code turning analytics off.
    @discardableResult
    func record(_ name: String, at: Date) async -> Bool {
        guard Kit.isCodeName(name) else {
            Notice.once("Milestone \(name) isn't kept: a milestone's name needs letters, digits, \".\", \"_\" or \"-\" (up to 64).",
                        log: log, level: .error)
            return false
        }
        // Nothing would ever send it, so it isn't kept, and the developer hears why once: the most private `analytics:` of the
        // app's modifiers holds, so `.off` on another product's silences milestones too.
        guard checksIn() else {
            Notice.once("Milestones aren't kept: analytics: .off on a TaoolKit modifier stops the check-in they go in. The most private level of the app's TaoolKit modifiers holds; use .minimal or higher to send milestones.",
                        log: log, level: .error)
            return false
        }
        // StoreKit's answer is read once a launch (`AppTransactionFacts`), so asking for each call costs nothing.
        if let account = await appTransaction()?.id {
            saved.account = account
            let kept = saved.accounts[account] ?? [:]
            guard Self.named(name, in: kept) == nil else { return false }
            guard kept.count < Self.maxPerAccount else { return tooMany(name) }
            saved.accounts[account, default: [:]][name] = Reached(at: at)
        } else {
            if let named = Self.named(name, in: saved.unclaimed), saved.unclaimed[named]! <= at { return false }
            guard saved.unclaimed.count < Self.maxPerAccount else { return tooMany(name) }
            saved.unclaimed[Self.named(name, in: saved.unclaimed) ?? name] = at
        }
        file.write(saved)
        sendSoon()
        return true
    }

    /// The key the name is kept under, whatever its case, as taool keeps names; nil when it isn't.
    private static func named<Value>(_ name: String, in kept: [String: Value]?) -> String? {
        guard let kept else { return nil }
        if kept[name] != nil { return name }
        return kept.keys.first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func tooMany(_ name: String) -> Bool {
        Notice.once("Milestone \(name) isn't kept: this user already has \(Self.maxPerAccount), as many as TaoolKit keeps. A name is the same for everyone who reaches it, never an ID or a date.",
                    log: log, level: .error)
        return false
    }

    /// Calls while one waits join it.
    private func sendSoon() {
        guard !sendScheduled else { return }
        sendScheduled = true
        Task {
            try? await Task.sleep(for: delay)
            sendScheduled = false
            await send()
        }
    }

    // MARK: MilestonesCheckInPart

    /// The Apple Account StoreKit last said this is has some to send: never another's left on the device (a build installed
    /// over another), nor any before StoreKit has said, so what can't go never makes every launch check in.
    var hasPending: Bool {
        guard let account = saved.account else { return false }
        return !saved.unclaimed.isEmpty || saved.accounts[account]?.values.contains { !$0.sent } == true
    }

    func nextMilestones(for account: String) -> [CheckInReport.Milestone] {
        if saved.account != account {
            saved.account = account
            file.write(saved)
        }
        claim(for: account)
        return (saved.accounts[account] ?? [:]).filter { !$0.value.sent }.sorted { $0.value.at < $1.value.at }.prefix(Self.maxPerCheckIn)
            .map { CheckInReport.Milestone(name: $0.key, at: $0.value.at) }
    }

    func reached(for account: String?) -> Set<String> {
        var names = Array(saved.unclaimed.keys)
        if let account, let kept = saved.accounts[account] { names += kept.keys }
        return Set(names.map { $0.lowercased() })
    }

    func checkedIn(_ sent: [CheckInReport.Milestone], account: String) {
        for milestone in sent { saved.accounts[account]?[milestone.name]?.sent = true }
        file.write(saved)
    }

    /// What was reached before StoreKit said which Apple Account this is, now this one's: the earlier time where both have one.
    private func claim(for account: String) {
        guard !saved.unclaimed.isEmpty else { return }
        var kept = saved.accounts[account] ?? [:]
        for (name, at) in saved.unclaimed.sorted(by: { $0.value < $1.value }) {
            if let known = Self.named(name, in: kept) {
                if at < kept[known]!.at { kept[known] = Reached(at: at) }
            } else if kept.count < Self.maxPerAccount {
                // A new name only within the guard, the earliest first, as `record` keeps them.
                kept[name] = Reached(at: at)
            }
        }
        saved.accounts[account] = kept
        saved.unclaimed = [:]
        file.write(saved)
    }
}
