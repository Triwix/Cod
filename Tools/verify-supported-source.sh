#!/bin/zsh
# Regression guard for the source/configuration; known-pattern scan, not approval.
# Uses the stock /usr/bin/grep so it runs on any Mac without extra tools.
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root"
[[ -x /usr/bin/grep ]] || { print -u2 'Required source-audit tool is unavailable: /usr/bin/grep'; exit 1; }

reject_matches() {
    local pattern="$1" scan_result=0
    shift
    # Recursive, text files only (like rg's default), extended regex. Exit 1
    # means no match; 2 means a missing or unreadable input, which must fail.
    LC_ALL=C /usr/bin/grep -rnIE -- "$pattern" "$@" || scan_result=$?
    case "$scan_result" in
        0) print -u2 'Removed experimental implementation or unsupported entry point found.'; exit 1 ;;
        1) return 0 ;;
        *) print -u2 'Source audit could not read all requested inputs.'; exit 1 ;;
    esac
}
forbidden='COD_PERSONAL|COD_FAST_SHARE|COD_LAUNCH_PROBE|NSSelectorFromString|NSClassFromString|unsafeBitCast|dlsym|LSApplicationWorkspace|BSProcessHandle|_FBSScene|SSEnvironmentDescription|openThroughResponderChain|suspendReturningToLastApp|_systemNavigationAction|setControlsStyle|controlsStyle|FastShareAppLauncher|SourceAppReturn|ShareSourceContext|ShareFloatHandoff|returnAfterFloating|hideFloatingControls'
reject_matches "$forbidden" Cod CodShare CodControls CodSafari CodTests CodLaunchUITests project.yml Cod.xcodeproj/project.pbxproj Cod.xcodeproj/xcshareddata
# Extensions never open the app or run Picture in Picture themselves.
reject_matches 'UIApplication|extensionContext\??\.open|AVPictureInPicture' CodShare CodSafari
print 'Supported-only source regression checks passed. App Review is a separate decision.'
