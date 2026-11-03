# Adding taool's milestones to an app (for coding agents)

Follow these steps to add TaoolKit's `TaoolMilestones` product to an iOS or macOS app. It records the moments the app's users reach (finished onboarding, made a first project, tried the demo), and taool keeps the first time each user reached each, so the developer sees, in the taool app, who reached what and when, and where the rest stopped.

You need the developer's **taool key**, which looks like `taool_public_` followed by 31 letters and digits (never the server key, `taool_secret_…`, which belongs only on a server). It's usually in the prompt that sent you here. If not, ask for it: it's on the taool app's TaoolKit page. The key is public, so hard-coding it in the app is correct. Don't put it in a secrets file or the Keychain.

## 1. Add the package

- **Xcode project:** add a package dependency on `https://github.com/taoolcom/taool-swift` (Up to Next Major Version from 1.0.0), with the `TaoolMilestones` product linked to the app target, and to any other app target that ships to the App Store (a separate Mac app). Never to widgets or extensions.
- **SwiftPM:** `.package(url: "https://github.com/taoolcom/taool-swift", from: "1.0.0")` and `.product(name: "TaoolMilestones", package: "taool-swift")`.
- **The project has the package already** (for another TaoolKit product): only link `TaoolMilestones`, never add the package again.

The package needs iOS 17, iPadOS 17, watchOS 10, tvOS 17, macOS 14 or visionOS 1. If the app supports older versions, stop and tell the developer.

## 2. Apply the modifier at the root of every scene

Find the `App` struct (`@main`), and put the modifier on the root view inside each `WindowGroup`, beside any other TaoolKit modifier. In a UIKit app without one, put it on the root SwiftUI view of a `UIHostingController` that stays on screen; if there's none, stop and tell the developer.

```swift
import SwiftUI
import TaoolMilestones

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .taoolMilestones(key: "taool_public_REPLACE_ME")
        }
    }
}
```

- It includes TaoolAnalytics and sends milestones in its check-in, so an app with `.taoolAnalytics` needs no change there: it's still one check-in.
- If the app has accounts, pass who's signed in, as to TaoolKit's other modifiers: `.taoolMilestones(key: "taool_public_REPLACE_ME", userID: …)`, `nil` while no one is, on every render.
- If the app's debug builds use a different bundle ID from the App Store app's, pass the App Store one: `bundleID: "com.example.app"`.

## 3. Record the milestones (ask the developer which)

Ask the developer which moments matter, usually the steps of their onboarding and a first use of each main feature. If they don't know yet, suggest a few from the app's code, such as `onboarding-done`, `paywall-seen` and the first use of the app's main feature (`first-export`), and confirm them before adding any. Then call, where each happens:

```swift
TaoolMilestones.record("onboarding-done")
```

- Call it every time the moment happens, even on every launch: only the first time is kept, and it's sent once, so calling it again costs nothing.
- A name is letters, digits, `.`, `_` and `-`, up to 64, the same whatever its case. Use lowercase words joined by dashes, as flag keys and experiments' goals are, object then verb (`project-created`); underscores work too. Never put anything about the user in a name (no email address, no ID, no free text): it's the same for everyone who reaches it. Keep to the few moments that matter: taool shows only an app's first names, as many as the developer's plan allows.
- Don't rename one that's shipped: taool counts the new name as a new milestone.
- Milestones are apart from TaoolExperiments' goals, even under the same name. If an experiment should count the moment too, call `TaoolExperiments.record(…)` there as well.
- Nothing grants access by a milestone, and nothing should: a user can only ever record their own.

## 4. Privacy (tell the developer)

TaoolMilestones' privacy manifest declares product interaction and a user ID (analytics, not used for tracking), not linked to the user. Tell the developer to add both to their App Store privacy answers, as linked to the user if the app passes its own `userID`. With `analytics: .off` on any TaoolKit modifier, the most private level holding, nothing is sent and milestones aren't kept: if the app sets `.off` anywhere (to stay Data Not Collected), tell the developer milestones need `.minimal` or higher there, since milestones are collected data anyway.

## 5. Check it

1. Build the app, and run a TestFlight or App Store build, which StoreKit signs: a milestone goes with StoreKit's signed record of the app, and builds run from Xcode with a StoreKit configuration aren't signed by Apple, so taool doesn't take theirs.
2. In the taool app, Earn → Users → Milestones lists each name a minute or so after it's first recorded, TestFlight's apart from the App Store's.

## Rules

- Don't add your own network calls, timers or retries around TaoolKit: a milestone goes in TaoolKit's check-in a moment after it's recorded, and what can't go waits on the device for the next time the app comes to the foreground or leaves.
- Don't call it from widgets, extensions or App Clips.
- The key is the same for all of the developer's apps. TaoolKit finds the app from its bundle ID.
