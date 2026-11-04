#!/bin/zsh
# Regression guard for the source/configuration; known-pattern scan, not approval.
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root"
command -v rg > /dev/null || { print -u2 'Required source-audit tool is unavailable: rg'; exit 1; }

reject_matches() {
    local scan_result=0
    rg -n "$@" || scan_result=$?
    case "$scan_result" in
        0) print -u2 'Removed experimental implementation or unsupported entry point found.'; exit 1 ;;
        1) return 0 ;;
        *) print -u2 'Source audit could not read all requested inputs.'; exit 1 ;;
    esac
}
forbidden='COD_PERSONAL|COD_FAST_SHARE|COD_LAUNCH_PROBE|NSSelectorFromString|NSClassFromString|unsafeBitCast|dlsym|LSApplicationWorkspace|BSProcessHandle|_FBSScene|SSEnvironmentDescription|openThroughResponderChain|suspendReturningToLastApp|_systemNavigationAction|setControlsStyle|controlsStyle|FastShareAppLauncher|SourceAppReturn|ShareSourceContext|ShareFloatHandoff|returnAfterFloating|hideFloatingControls'
reject_matches "$forbidden" Cod CodShare CodControls CodTests CodLaunchUITests project.yml Cod.xcodeproj
reject_matches 'UIApplication|extensionContext\??\.open|AVPictureInPicture' CodShare
print 'Supported-only source regression checks passed. App Review is a separate decision.'
