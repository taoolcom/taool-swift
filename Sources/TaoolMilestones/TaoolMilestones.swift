// Copyright (c) 2026 Primetic
// SPDX-License-Identifier: MIT
// TaoolKit: https://taool.com/docs

import SwiftUI
@_exported import TaoolAnalytics
import TaoolCore

/// The moments your app's users reach (finished onboarding, made their first project, tried the demo), kept by taool with each
/// user: the first time each reached each, on their page in the taool app, in its Users list's filters and in funnels.
///
/// ```swift
/// ContentView()
///     .taoolMilestones(key: "taool_public_…")   // each scene's root view
///
/// TaoolMilestones.record("onboarding-done")
/// ```
///
/// Call `record` whenever the moment happens: only the first time is kept, and it's sent once, in TaoolKit's check-in with
/// StoreKit's signed AppTransaction, so it lands only on the Apple Account it's from. Milestones have nothing to do with
/// TaoolExperiments' goals, even under the same name: record a goal there too when an experiment should count it. It checks in
/// through TaoolAnalytics, which it includes; with `analytics: .off` on any TaoolKit modifier none is kept, and the console says so.
public enum TaoolMilestones {
    /// Records that this user reached a milestone now. Call it every time it happens: taool keeps the first time, and only that
    /// is sent, once. Name milestones with letters, digits, ".", "_" and "-", up to 64, the same name whatever its case.
    @MainActor
    public static func record(_ name: String) {
        let now = Date.now
        Task { await MilestoneStore.shared.record(name, at: now) }
    }
}

extension View {
    /// Sends your app's milestones to taool: put it on the root view of each scene. A milestone goes in TaoolKit's check-in a
    /// moment after it's first recorded, or as the app next comes to the foreground or leaves while it can't go yet.
    ///
    /// - Parameters:
    ///   - key: The account's key, from the taool app's TaoolKit page. Public: it's fine to ship in the app.
    ///   - userID: Your own ID for the signed-in user, or nil while no one is signed in, so the taool app shows a user's
    ///     milestones on their page by it. Pass the current user each time; with TaoolKit's other modifiers, pass it the same.
    ///   - analytics: How much the device tells taool about itself (`TaoolAnalytics.Level`). `.off` sends nothing and keeps no
    ///     milestones, on this modifier or any other TaoolKit one, since the most private level holds.
    ///   - bundleID: The App Store app's bundle ID, when a debug build uses a different one.
    public func taoolMilestones(key: String, userID: String? = nil, analytics: TaoolAnalytics.Level = .automatic,
                                bundleID: String? = nil) -> some View {
        CheckIns.shared.start(.milestones, key: key, level: analytics, userID: userID, bundleID: bundleID)
        // The check-in carries what waits, and goes at once while anything does.
        CheckIns.shared.attach(milestones: MilestoneStore.shared)
        return modifier(TaoolAnalyticsModifier())
    }
}
