#!/bin/zsh
# Read-only artifact check. Run with zsh Tools/verify-store-build.sh /path/Cod.app
# Add --submission to require the hosted policy URL before store submission.
set -euo pipefail

# This verifier must work on a stock Mac and distinguish "no match" from a
# failed scan. An if-pipeline would otherwise hide missing tools/read errors.
for audit_tool in /usr/bin/grep /usr/bin/otool /usr/bin/awk /usr/bin/plutil /usr/bin/mktemp /usr/libexec/PlistBuddy; do
    [[ -x "$audit_tool" ]] || { print -u2 "Required audit tool is unavailable: $audit_tool"; exit 1; }
done
scratch_directory=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/cod-store-audit.XXXXXX")
trap '/bin/rm -f -- "$scratch_directory/load-commands"; /bin/rmdir -- "$scratch_directory"' EXIT

has_pattern() {
    local scan_pattern="$1" scan_file="$2" match_result=0
    # Scan all bytes, including Mach-O sections/trailing data that strings can
    # skip. Byte-oriented matching also avoids locale-dependent binary errors.
    LC_ALL=C /usr/bin/grep -aE -- "$scan_pattern" "$scan_file" > /dev/null || match_result=$?
    case "$match_result" in
        0) return 0 ;;
        1) return 1 ;;
        *) print -u2 "Couldn't search audit input: $scan_file"; exit 1 ;;
    esac
}

app_path="${1:?Pass the absolute path to the built Cod.app}"
extension_path="$app_path/PlugIns/CodShare.appex"
check_mode="${2:-}"
[[ -z "$check_mode" || "$check_mode" == --submission ]] || {
    print -u2 'Only the documented-only audit is available; optional flag: --submission.'
    exit 1
}
package_info="$app_path/Shortcuts/Store/InstallerInfo.plist"
package_bundle=$(/usr/libexec/PlistBuddy -c 'Print :BundleIdentifier' "$package_info")
package_team=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier' "$package_info")
app_team=$(/usr/libexec/PlistBuddy -c 'Print :CodShortcutTeamIdentifier' "$app_path/Info.plist")
[[ "$package_bundle" == com.josh.cod.store && -n "$app_team" && "$package_team" == "$app_team" ]] || {
    print -u2 'Shortcut installers do not match this app/team. Regenerate and sign them before shipping.'
    exit 1
}
for workflow in 'Float with Cod' 'Screenshot and Float with Cod'; do
    [[ -s "$app_path/Shortcuts/Store/$workflow.shortcut" ]] || { print -u2 "Missing Shortcut installer: $workflow"; exit 1; }
done
private_patterns='LSApplicationWorkspace|suspendReturningToLastApp|_systemNavigationAction|setControlsStyle:|controlsStyle|ShareSourceContext|SourceAppReturn|BSProcessHandle|_FBSScene|SSEnvironmentDescription|com\.josh\.cod\.float-image|openThroughResponderChain|responder-chain|api\.imgur\.com'

for bundle_path in "$app_path" "$extension_path" "$app_path/PlugIns/CodControls.appex"; do
    executable_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle_path/Info.plist")
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle_path/Info.plist")
    if [[ "$bundle_id" != com.josh.cod.store && "$bundle_id" != com.josh.cod.store.share && "$bundle_id" != com.josh.cod.store.controls ]]; then
        print -u2 "Not the store configuration: $bundle_id"
        exit 1
    fi
    if [[ "$bundle_id" != com.josh.cod.store.controls ]]; then
        launch_policy=$(/usr/libexec/PlistBuddy -c 'Print :CodShareLaunchPolicy' "$bundle_path/Info.plist")
        [[ "$launch_policy" == manual-open ]] || {
            print -u2 'The Share extension must use user-mediated app opening.'
            exit 1
        }
    fi
    [[ -n "$executable_name" && "$executable_name" != */* && -s "$bundle_path/$executable_name" && -r "$bundle_path/$executable_name" ]] || {
        print -u2 "Missing or unreadable executable in $bundle_id"
        exit 1
    }
    for binary_path in "$bundle_path/$executable_name" "$bundle_path/$executable_name.debug.dylib"; do
        # The main executable is mandatory; a separate debug dylib is optional.
        [[ "$binary_path" == "$bundle_path/$executable_name" || -e "$binary_path" ]] || continue
        [[ -f "$binary_path" && -s "$binary_path" && -r "$binary_path" ]] || {
            print -u2 "Missing or unreadable binary: $binary_path"
            exit 1
        }
        /usr/bin/otool -l "$binary_path" > "$scratch_directory/load-commands" || {
            print -u2 "Couldn't inspect load commands in $binary_path"; exit 1
        }
        has_pattern '^[[:space:]]*cmd LC_(BUILD_VERSION|VERSION_MIN_IPHONEOS)[[:space:]]*$' "$scratch_directory/load-commands" || {
            print -u2 "Not a supported iOS Mach-O binary: $binary_path"; exit 1
        }
        if has_pattern "$private_patterns" "$binary_path"; then
            print -u2 "Removed implementation found in $bundle_id"
            exit 1
        fi
        if has_pattern 'FloatPendingWithCodIntent|Public launch experiment|Test system Float' "$binary_path"; then
            print -u2 "Simulator launch-probe code found in $bundle_id"
            exit 1
        fi
        if has_pattern 'SimulatorQATraits|--large-text-ui-test|--dark-ui-test|--landscape-ui-test|--show-float-setup|--show-introduction' "$binary_path"; then
            print -u2 "Debug-only UI testing code found in $bundle_id. Audit a Release build."
            exit 1
        fi
        if has_pattern 'FastShareAppLauncher|FastShareLaunchAttempt' "$binary_path"; then
            print -u2 "Fast-share workaround unexpectedly present in $bundle_id"
            exit 1
        fi
        if has_pattern 'cod-diagnostics\.log|share-diagnostics\.log|\[CodPiP\]|\[CodShare\]' "$binary_path"; then
            print -u2 "Debug diagnostic logging found in $bundle_id. Audit a Release build."
            exit 1
        fi
        alarm_link=$(/usr/bin/awk '
            $1 == "cmd" { kind = $2 }
            $1 == "name" && $2 ~ /\/AlarmKit.framework\// { print kind }
        ' "$scratch_directory/load-commands")
        [[ -z "$alarm_link" || "$alarm_link" == LC_LOAD_WEAK_DYLIB ]] || {
            print -u2 "AlarmKit must be weak-linked for older iOS versions: $bundle_id"
            exit 1
        }
    done
    /usr/bin/plutil -lint "$bundle_path/PrivacyInfo.xcprivacy"
    if [[ "$bundle_id" != com.josh.cod.store.controls ]]; then
        reason=$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPITypeReasons:0' "$bundle_path/PrivacyInfo.xcprivacy")
        [[ "$reason" == CA92.1 ]] || { print -u2 'Missing own-preferences declaration'; exit 1; }
    fi
    group_id=$(/usr/libexec/PlistBuddy -c 'Print :CodAppGroup' "$bundle_path/Info.plist")
    [[ "$group_id" == group.com.josh.cod.store ]] || { print -u2 'Incorrect App Group configuration'; exit 1; }
    if [[ "$bundle_id" != com.josh.cod.store.share ]]; then
        metadata_path="$bundle_path/Metadata.appintents/extract.actionsdata"
        [[ -f "$metadata_path" && -s "$metadata_path" ]] && has_pattern 'FloatSavedReferenceIntent' "$metadata_path" || {
            print -u2 "Saved-reference intent metadata is missing from $bundle_id"
            exit 1
        }
    fi
    print "Checked $bundle_id: privacy resource present; known private methods absent."
done

if [[ "${2:-}" == --submission ]]; then
    display_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$app_path/Info.plist")
    [[ "$display_name" == Cod ]] || { print -u2 'Do not submit the Cod Test display name.'; exit 1; }
    policy_url=$(/usr/libexec/PlistBuddy -c 'Print :CodPrivacyPolicyURL' "$app_path/Info.plist")
    [[ "$policy_url" == https://* && "$policy_url" != *'$('* ]] || {
        print -u2 'A real hosted HTTPS privacy policy must be configured before submission.'
        exit 1
    }
fi
print 'Local checks passed. This does not validate distribution signing, App Groups provisioning, review acceptance, or the hosted policy contents.'
