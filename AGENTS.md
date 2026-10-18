# Cod development policy

Use only documented Apple APIs for their intended purposes. Do not add private
selectors, runtime framework lookups, responder-chain extension launch tricks,
programmatic app suspension, or hidden AVKit control settings—even behind flags.

The Share extension must not launch the containing app directly. Supported entry
points are App Intents/Shortcuts, WidgetKit controls, user-tapped notifications,
explicit document opening, and opening Cod manually. Never promise App Review
approval based only on use of public APIs.

Build the Cod scheme (Debug/Release). Run unit tests, relevant simulator UI tests,
and Tools/verify-store-build.sh on the release artifact after entry-point changes.
Keep the original installed Cod app/data untouched; device testing uses
com.josh.cod.store (Cod Test).
