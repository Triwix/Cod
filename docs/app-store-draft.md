# Cod 1.0 — App Store submission draft

Draft for build 32. Nothing here has been published or entered in App Store
Connect. The account owner must approve every answer and fill in the marked
fields. Whether the name is available is only known once the App Store Connect
record is created.

## Listing

Character limits: name and subtitle 30 each, promotional text 170, keywords
100 bytes, description 4,000.

**App Store name (29):** Cod: Crop & Float Screenshots
(The Home Screen name stays "Cod".)

**Subtitle (28):** Snip, OCR & pin over any app

**Promotional text (152):**
Take a screenshot, crop the part you need and float it over any app. Copy or
translate its text, run it from Back Tap or Shortcuts. No ads, no tracking.

**Keywords (97):**
`pip,picture in picture,overlay,reference,copy text,scan,qr,barcode,shortcut,back tap,teleprompter`
(The name and subtitle are already indexed, so their words aren't repeated.
Don't use other apps' names.)

**Category:** Utilities (primary), Productivity (secondary).

**Description:**

> Take a screenshot, crop the part you need, and keep it floating over any app.
>
> Cod turns a slice of your screen into a floating window you can move and
> resize while you work: a recipe step, a map, a few lines of code, a reference
> photo, the list you're copying from.
>
> CROP AND FLOAT
> • Draw a box around what matters, then double-tap it to float.
> • Tap a detected block of content to select it instantly.
> • Zoom in and fine-tune each edge for an exact crop.
> • Move and resize the floating window like any Picture in Picture video.
>
> RUN IT FROM SHORTCUTS
> • Back Tap: add "Screenshot and Crop with Cod", tap the back of your
>   iPhone, draw a box, and it floats. Prefer the whole screen? "Screenshot
>   and Float with Cod" skips the crop.
> • Share Sheet: add "Float with Cod" once, then float any photo straight from
>   Photos.
> • Say "Crop my latest screenshot with Cod" to jump straight to cropping.
> • Build your own: Crop With Cod, Float With Cod, Float Text With Cod and
>   Float PDF Page With Cod work in any Shortcut.
> • Control Center, Lock Screen and Action Button controls float your latest
>   screenshot (iOS 18 or later).
>
> COPY THE TEXT, SCAN THE CODE
> • Copy Text reads the words in your crop on your device and puts them on the
>   clipboard.
> • Translate turns the text in your crop into another language.
> • Scan Code reads QR codes and barcodes inside the selection.
> • Copy, save or share any crop. Everything you float lands in Recents; star
>   what you use most.
>
> MORE THINGS TO FLOAT WITH COD PRO
> Notes and teleprompter scripts, PDFs you can flip through page by page, image
> sets, videos and GIFs. A timer, stopwatch, Pomodoro, a countdown to any date,
> a clock and a world clock. A system monitor with the readings you pick:
> battery, thermal state, network speed, storage, memory and CPU. A speedometer.
> Make the floating window wide, square or tall, and save setups for widgets
> and Control Center.
>
> Try Cod Pro free for 7 days with a monthly or yearly subscription, or buy it
> once with Lifetime. Cropping, floating images, Shortcuts, Copy Text,
> Translate and Scan Code are always free. Float web videos from Safari with
> the free Float Video extension.
>
> PRIVATE BY DESIGN
> Everything happens on your device. No account, no ads, no analytics.
>
> Good to know: iOS shows one Picture in Picture window at a time. Cod opens
> briefly to start floating; then switch to any app.
>
> Subscriptions renew automatically until canceled. Cancel anytime in
> Settings at least 24 hours before the end of the current period.
> Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
> Privacy Policy: [HOSTED POLICY URL]

**Support URL:** [OWNER MUST PROVIDE]

**Privacy policy URL:** [OWNER MUST HOST `PRIVACY_POLICY.md`]; also set
`COD_PRIVACY_POLICY_URL` so the Pro screen links to it.

**Copyright / publisher name:** [OWNER MUST PROVIDE]

**App price:** Free, with in-app purchases.

## In-app purchases

Create these with exactly these product IDs. Family Sharing is on for all three.

| Product ID | Type | Display name | Price | Offer |
|---|---|---|---|---|
| `cod.pro.yearly` | Auto-renewable, group "Cod Pro", level 1 | Cod Pro Yearly | $11.99 / year | 1-week free trial |
| `cod.pro.monthly` | Auto-renewable, group "Cod Pro", level 2 | Cod Pro Monthly | $1.99 / month | 1-week free trial |
| `cod.pro.lifetime` | Non-consumable | Cod Pro Lifetime | $19.99 | — |

Each product needs:
- a review screenshot of the Pro screen
- a short description: "Unlock everything in Cod: live tools, text and teleprompter, videos, PDFs, image sets and saved cards."

Submit the products together with the app version.

**Free:**
- crop and float images and screenshots
- the Share and Back Tap Shortcuts
- Copy Text, Translate and Scan Code
- Recents with stars
- Safari Video

**Pro:**
- live tools and window shapes
- Teleprompter and text cards
- videos and GIFs
- PDFs
- image sets
- saved cards and presets, including their widgets, controls and Shortcut action

Setting up a Pro tool is free; only floating it asks for Pro.

## Reviewer notes (for the App Review field)

No login is needed. Floating needs a physical iPhone: Picture in Picture doesn't
show content in the Simulator.

**Free features:**
1. Float tab → Choose Photo → pick a photo. Keep Cod open until the floating window appears, then switch apps yourself.
2. Crop: take a screenshot, open Cod and choose Crop, draw a box, then double-tap it to float. The action bar also has Copy Text, Translate and Scan Code.
3. Shortcuts: Float → Floating guide & setup offers three ready-made Shortcuts. "Float with Cod" appears in Photos' share sheet under the app icons. "Screenshot and Crop with Cod" can be assigned to Back Tap in Settings → Accessibility → Touch.

**Cod Pro:**
- Tap Float on any tool (for example Float → Timer) to open the Pro screen.
- It also opens from Settings → Cod Pro.
- Use the sandbox account to start the 7-day trial or buy Lifetime.
- Restore Purchases is on the Pro screen and in Settings.

**How floating works:**
- **Still images:** Cod encodes them into a short looping video played with AVPlayerLayer and the public AVPictureInPictureController.
- **Live tools, scrolling text and PDF pages:** Cod draws timestamped frames into AVSampleBufferDisplayLayer and uses AVKit's documented sample-buffer playback delegate. Play/pause and skip control the tool (for example, skip turns PDF pages).
- **Imported videos:** ordinary AVPlayer playback.
- **Controls:** Cod adds no custom buttons to the window and hides no system controls.
- **Host view:** AVKit needs the player layer in Cod's view hierarchy before Picture in Picture can start, so Cod adds a small, nearly transparent view behind its content to hold it. The view has no controls and isn't used to hide anything.
- **No private APIs:** no private APIs, automatic app switching or app suspension.

**Background modes:**
- **Audio:** keeps an active floating window playing.
- **Location:** used only by the Speedometer tool while it's open or floating, because floating means Cod is in the background. Cod asks for When In Use permission only, shows the background location indicator, and stops updates when the Speedometer closes. Speed is shown and discarded; locations are never stored or sent.

**Extensions:**
- **Share extension:** it saves the image to an App Group. Then the user opens Cod or taps an optional local notification. It never launches Cod itself.
- **Safari extension, Float Video with Cod:** it adds a Float button to web videos and starts Safari's own Picture in Picture. It doesn't read, store or send page content.

**Optional system features:**
- Timer alarms use AlarmKit (iOS 26 or later). They're off by default and ask for permission when turned on.
- Screenshot controls need iOS 18 or later and Photos access.

Apple decides whether these uses meet App Review requirements. This note
describes the implementation; it isn't a claim of approval.

## Internal pre-submission checks (not for the reviewer field)

On the signed release build, on a physical iPhone:

1. **Floating:**
   - a photo, a crop, text, a PDF in Flip Pages, a timer, System Monitor, Speedometer and a video
   - each window shape
   - restoring into Cod
   - closing the window
2. **Shortcuts:**
   - all three ready-made Shortcuts install
   - Back Tap crop works
   - Share Sheet float works
3. **Pro, in the sandbox:**
   - start the trial
   - Pro badges disappear
   - Manage Subscription works
   - buying Lifetime while subscribed shows the cancel warning
   - Restore works
   - after a refund or expiry, Pro locks again
4. **Free tier:** Pro tools preview, then show the Pro screen instead of floating.
5. **Store checks:** run `Tools/verify-store-build.sh <Cod.app> --submission` and `Tools/verify-supported-source.sh` (with zsh).
6. **Launch checks:** iOS 17 and 18 launch checks, and VoiceOver on the crop editor.

## Privacy, export and rating answers to review

- **App Privacy:**
  - No developer collection, tracking, advertising, analytics or accounts.
  - Images, recognized text, Recents and saved cards stay on the device (and in device backups).
  - Apple processes purchases; Cod receives only StoreKit's signed transaction status.
  - Location for the Speedometer is read on the device and never stored or sent.
  - Confirm the final answers against the signed build and the hosted policy.
- **Notifications:** optional, local only, carrying an ID and no image.
- **Third-party code:** no third-party SDKs and no custom encryption. The owner answers the export-compliance questions (`ITSAppUsesNonExemptEncryption` is false).
- **Age rating:** complete the questionnaire. There's no user-generated feed, chat, ads or unrestricted web browser; content comes from the user.
- **Accessibility:** don't claim full VoiceOver or Voice Control support until the gesture-based crop editor has been checked.

## Screenshots

Required: the 6.9" iPhone set, 1320 × 2868 portrait. There's no iPad set
because 1.0 is iPhone-only. Up to 10 screenshots; the first three carry the
pitch. Use only content the owner has rights to.

| # | Caption | Shows | Capture on |
|---|---------|-------|---------|
| 1 | **Crop any screen. Float it on top.** | A cropped snippet floating over another app | Phone |
| 2 | **Snip just the part you need.** | Crop editor with a selection and the action bar | Simulator |
| 3 | **Copy text from any snip.** | Copy Text result | Simulator |
| 4 | **Back Tap to snip. Share to float.** | Floating Guide with the ready-made Shortcuts | Simulator |
| 5 | **Built for Shortcuts.** | Cod's actions in the Shortcuts editor | Phone |
| 6 | **Scan QR codes and barcodes.** | Scan Code result | Phone |
| 7 | **Timers, PDFs, teleprompter and more.** | A Pro tool floating over an app | Phone |
| 8 | **Everything you float, one tap away.** | Recents with starred items | Simulator |

Optional: a 15–30 second preview video of Back Tap → crop → float. It also helps
App Review see real floating.

Apple references:

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (3.1.1 and 3.1.2 for in-app purchase and subscriptions)
- [Offering a free trial](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Version information and keyword limits](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)
