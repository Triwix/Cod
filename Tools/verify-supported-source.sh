#!/bin/zsh
# Regression guard for the source/configuration; known-pattern scan, not approval.
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root"
forbidden='COD_PERSONAL|COD_FAST_SHARE|COD_LAUNCH_PROBE|NSSelectorFromString|NSClassFromString|unsafeBitCast|dlsym|suspendReturningToLastApp|_systemNavigationAction|setControlsStyle|controlsStyle|FastShareAppLauncher|SourceAppReturn|ShareSourceContext|ShareFloatHandoff|returnAfterFloating|hideFloatingControls'
if rg -n "$forbidden" Cod CodShare CodControls CodTests CodLaunchUITests project.yml Cod.xcodeproj; then
    print -u2 'Removed experimental implementation or build option found.'
    exit 1
fi
if rg -n 'UIApplication|extensionContext\??\.open|AVPictureInPicture' CodShare; then
    print -u2 'The Share extension must not launch Cod or own PiP.'
    exit 1
fi
print 'Supported-only source regression checks passed. App Review is a separate decision.'
