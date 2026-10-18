# Bundled Shortcut files

`Tools/MakeFloatShortcuts.swift` generates the two workflows for com.josh.cod.store.
Only Apple-signed `.shortcut` files belong in the `Store` folder.
Both workflows are included, signed on October 18, 2026 with the user's approval.
The obsolete personal-identity copies and build configurations have been removed.
Generate to a temporary directory, then sign using `shortcuts sign --mode anyone`.
Signing sends the workflow definition to Apple's service, so obtain approval
before running it. It contains bundle/team identifiers, not images or user data.

The image-sharing workflow accepts only images, enables the Share Sheet, stops
when input is missing, and wires the Image parameter to Shortcut Input explicitly.
The Back Tap workflow captures a screenshot and wires that action's output to
the same `FloatWithCodIntent`. Neither reads the clipboard or chooses a latest
photo. Users still approve installation and assign Back Tap in iPhone Settings.

If signed files are absent, the guide shows manual setup instead of offering
an unusable installer. Do not replace them with unsigned placeholders.
