# Returning beneath a screenshot preview

> Historical research. All private automatic-return and origin-probing code
> was removed in build 6. Cod now leaves app switching to the user; this record
> is retained as evidence, not an implementation guide.

## Outcome

Research and physical tests on October 6, 2026 did **not** establish reliable
automatic return to the app beneath an immediate screenshot preview. Photos
sharing and image PiP still work. Screenshot-preview shares retain the safe
Home fallback, avoiding the black, iconless Screenshots service.

This is not a claim that every possible iOS technique is impossible. It is the
limit of the tested paths on this non-jailbroken, personally signed iPhone
running iOS 26.7.1. Published disassembly below is from iOS 26.1; observations
on the actual phone, not the older implementation alone, determine the results.

## Tests

Times are October 6 in America/Los_Angeles.

| Candidate | Actual observation | Result |
| --- | --- | --- |
| Share host / existing provider metadata | Screenshot shares identify `com.apple.ScreenshotServicesService`; no screenshot environment reaches Cod. Photos shares identify Photos. | Host is not the app beneath the preview. |
| Foreground-app query in Cod | At 22:10:09, nil in 1 ms while Cod was active. Simulator also returned nil. | No usable identifier. |
| Same query before leaving the screenshot share extension | At 22:12:15 and 22:17:12, nil before Cod opened. | Share context supplies no different access on this phone. |
| Raw image representation / container fields | At 22:17:11, only `public.png`. ImageIO field names included dimensions, color, resolution, EXIF/PNG/TIFF descriptions and dates, but no explicit application-ID field. No values or captions logged. | No reliable origin field found. Descriptions are not used to guess app identity. |
| A return token arriving later | Observer armed before leaving Cod. Through the warm screenshot-share launch, activation, capture, return request and backgrounding, the navigation token remained nil. | No delayed token in this run. Not a separate cold-launch test. |

The final run received the actual 947×2048 image and started PiP in about 1.2
seconds. No attempt activated Spotify, reopened Screenshots, enumerated apps,
read app contents, or changed permissions. Home return remained intentional.

## Research findings

Apple's screenshot process holds the captured app's ID internally in
`SSEnvironmentDescription`. Its
[image-share implementation](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/main/Applications/ScreenshotServicesService.app/SSSScreenshotItemProviderImage.mm)
exports rendered PNG/HEIC and image link metadata, not that environment. The
[default image-properties implementation](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/main/System/Library/PrivateFrameworks/ScreenshotServices.framework/ScreenshotServices/UIImage%28SSImageSurface%29.mm)
adds image properties, a Screenshot label and a date, without fetching the
captured app's identity.

The foreground query theoretically has the useful information, but its
[server implementation](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/main/System/Library/PrivateFrameworks/SpringBoard.framework/SpringBoard/SpringBoard_02.mm)
uses a system-client authenticator. The
[authentication rules](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/main/System/Library/PrivateFrameworks/FrontBoard.framework/FrontBoard/FBServiceClientAuthenticator.mm)
exclude ordinary user apps/extensions. Device nil results are consistent with
this restriction; the query did not return an explicit authorization-error
explanation. No authentication bypass or privileged entitlement was attempted.

Modern status-bar Back-to is not independent: its
[implementation](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/main/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore/UIStatusBarSystemNavigationAction.mm)
uses the same UIApplication navigation token. The historical status-bar
experiment now skips when that token is absent. No lazy status-bar getter is
invoked; those caused a prior phone crash.

Screenshot dismissal uses its own
[remote-alert controller and proxy](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/main/Applications/ScreenshotServicesService.app/SSSDittoRemoteAlertViewController.mm).
Cod owns its share extension, not that screenshot controller. Extension
completion exposes no generic “dismiss screenshot and resume original app”
token to Cod. Destroying Cod's own scene offers no previous-app destination
and risks PiP, so it was not tried as a supposed fix.

The public
[scene sourceApplication property](https://developer.apple.com/documentation/uikit/uiscene/connectionoptions/sourceapplication)
only identifies origins signed by the same team. It does not solve arbitrary
third-party screenshot origins.

## Preserved behavior and next decisions

- Preserve Photos return and native PiP controls. The user confirmed turning
  Open without controls off fixes early tapping; new settings default off.
- Preserve the screenshot Home fallback until a trustworthy origin identifier
  or verified return action exists. Do not infer source from music, image
  contents/descriptions, a previous share or an old destination.
- A selected return app or Shortcut with an explicit Open App action would be
  a different workflow to investigate, not automatic universal return. Neither
  was implemented or verified as a substitute in this sweep.
- Treat universal screenshot-origin return as an unresolved MVP limitation,
  separate from successful image floating. Revisit if a new supported source
  or dismissal capability becomes available.

Automatic foreground and raw-image probes were removed from the share path
after testing. Main-app diagnostics remain behind explicit DEBUG arguments
`--foreground-identity-probe` and `--return-context-probe`, excluded from
Release. Tests cover bounded field-name inspection and newline rejection.
No routing was changed based on an unverified diagnostic result.

The clean build passed all 52 simulator tests with no failures or skips, built
for the device, and was installed wirelessly after the experiments. The
unsigned Release build also passed; its binary contains none of the explicit
foreground/navigation probe strings or launch arguments. These checks are
not App Store approval, nor a claim that screenshot return was solved.

## Local evidence

Retrieved logs are in `/tmp`: `cod-foreground-query-device-20261006.log`,
`cod-screenshot-context-query-20261006.log`,
`cod-final-return-metadata-20261006.log`, and
`cod-final-return-token-20261006.log`. They establish pipeline/identifier
observations, not independent visual proof of the exact return screen.

The user performed both screenshot-share attempts. No simulator visual pass
is claimed: native UI control timed out, and real PiP is not supported there.
