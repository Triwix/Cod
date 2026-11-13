# Build 32: Cod Pro

November 13, 2026. This build follows the owner's pricing direction:
- one week of Pro free
- then monthly, yearly or lifetime
- Pro has everything; the free tier has the basics

## Plans

| Product ID | Type | Local test price | Free trial |
|---|---|---|---|
| `cod.pro.yearly` | Auto-renewable, group "Cod Pro", level 1 | $11.99/year | 7 days |
| `cod.pro.monthly` | Auto-renewable, group "Cod Pro", level 2 | $1.99/month | 7 days |
| `cod.pro.lifetime` | Non-consumable | $19.99 | none (not possible) |

- **Trial:** the trial is an introductory offer, so it's given once per subscription group.
- **Family Sharing:** on for all three.
- **Real prices:** set in App Store Connect. The app shows whatever the App Store returns (`displayPrice`); nothing is hard-coded.

## Free and Pro

**Free:**
- crop and float images and screenshots
- the Share and Back Tap Shortcuts
- Copy Text, Translate and Scan Code
- Recents with stars (starred images also float from widgets)
- Safari Video

**Pro:**
- live tools (timers, clocks, world clock, Pomodoro, Countdown To, System Monitor, Speedometer) and their window shapes
- Teleprompter and text cards
- videos and GIFs
- PDFs (one page, Flip Pages, auto-scroll)
- image sets
- saved cards and tool presets, including from widgets, controls and the Shortcut action

**Where the gate sits:**
- Setting up and previewing a Pro tool is free; only floating asks for Pro.
- The check runs in `CaptureCoordinator.unlocks(_:)`, called by:
  - `floatTool`
  - `floatVideo`
  - Recents videos
  - saved cards
  - the text card, PDF page and Flip Pages buttons
  - the Float Text, Float PDF and animated-GIF Shortcut routes
- A Shortcut or widget that reaches a Pro feature on the free tier opens Cod and shows the Pro screen. It doesn't fail silently.

## The Pro screen (`ProView`)

**When it appears:**
- when someone floats a Pro feature
- from Settings → Cod Pro
- never at launch or during onboarding, and there are no ads

**What it shows:**
- The feature that was tapped comes first, then the rest of Pro.
- A line saying what's always free.
- Three plan cards. Yearly is selected first and shows its price per month.
- **Subscription disclosure (App Review 3.1.2):**
  - the price after the trial
  - that it renews automatically, and how to cancel
- **Lifetime:**
  - Lifetime says it's a one-time payment.
  - A current subscriber or trial user sees only Lifetime, plus a warning that buying it doesn't cancel the subscription and a Manage Subscription button.
- Restore Purchases.
- Apple's standard Terms of Use link.
- A Privacy Policy link, once `COD_PRIVACY_POLICY_URL` is set.
- Ask to Buy shows "Waiting for approval".

**Elsewhere in the app:**
- **Settings:** Cod Pro sits at the top with its status (trial end, plan, or Lifetime), Manage Subscription, Upgrade to Lifetime, and Restore Purchases.
- **Home:** Pro tool tiles show a small "Pro" badge until Pro is on.

## How it works

- **StoreKit 2:** `ProStore` handles:
  - `Product.products`
  - SwiftUI's `purchase` action
  - `Transaction.currentEntitlements` (refunds removed; Lifetime wins)
  - `Transaction.updates` for renewals, refunds, Ask to Buy and other devices
  - `AppStore.sync` for Restore Purchases
- **Last answer cached:** the last state is cached so a Pro user doesn't see a lock while StoreKit loads at launch.
- **Local products:** `StoreKit/CodPro.storekit` holds them. The Cod scheme's Run and Test actions use it, so Debug runs from Xcode show the Pro screen with working purchases before App Store Connect has the products. It isn't copied into the app.
- **UI tests:** in Debug simulator builds only, `--launch-ui-test` floats as Pro and `--free-tier-ui-test` checks the free tier. The choice is remembered so Launch Lab cold launches behave the same.
  - Unit tests always see the real StoreKit answer.
  - `verify-store-build.sh` now fails if either switch reaches a Release binary.

## Verification

Xcode 27.2, iPhone 17 Pro Max simulator, iOS 26.3.

- **Unit tests:** 286 run, 0 failures, 3 skipped. `ProTests` covers:
  - the access rules (Lifetime over subscriptions, refunds, the newest subscription wins)
  - product IDs
  - which tool needs which feature
  - the cached last answer
  - that the free tier asks for Pro instead of floating and shows the app
  - that invalid tools report their problem before asking for Pro
- **Skipped StoreKit tests (3):**
  - Products and trial, starting the trial, and Lifetime plus refund.
  - They skip here because this simulator can't reach the StoreKit test service (`SKInternalErrorDomain` 3). That happens even with a one-product file, and on iOS 26.5 too.
  - They run on an iPhone, or a newer simulator runtime, without changes.
  - A device run wasn't possible because Xcode has no signed-in account (no development profile for the Safari extension).
- **UI tests:**
  - `Build32UITests`: a free-tier timer previews, then shows the Pro screen with "live tools" first instead of floating. Settings offers Cod Pro and Restore Purchases.
  - `Build31UITests` still passes with the Pro test tier.
- **Release build (unsigned):** `verify-store-build.sh` and `verify-supported-source.sh` pass. No `.storekit` file or test switch is in the app.

## Still to do

1. **Phone test:** in Xcode, sign in, then Run Cod Test on the phone. The Cod scheme uses the local products. Then:
   - start the trial
   - check the Pro badge, the gate and Settings
   - Manage Subscription
   - buy Lifetime while subscribed and check the warning
   - Restore
   - Then run `ProTests` on the phone.
2. **App Store Connect,** after Developer Program enrollment:
   - Create the "Cod Pro" subscription group with Yearly (level 1) and Monthly (level 2), each with a 1-week free introductory offer.
   - Create the Lifetime non-consumable.
   - Use the same product IDs. Turn on Family Sharing.
   - Add the review screenshot of the Pro screen.
   - Submit the in-app purchases with the app version.
3. **Listing:**
   - Add the Terms of Use (EULA) link to the App Store description, or a custom EULA.
   - Fill in the privacy policy URL field.
4. **Sandbox:** check a renewal, an expiry and a refund before release.
