#!/bin/zsh
# Read-only artifact check. Run with zsh Tools/verify-store-build.sh /path/Cod.app
# Add --submission to require the hosted policy URL before store submission.
set -euo pipefail

app_path="${1:?Pass the absolute path to the built Cod.app}"
extension_path="$app_path/PlugIns/CodShare.appex"
check_mode="${2:-}"
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
        if [[ "$check_mode" == --fast-candidate ]]; then
            [[ "$launch_policy" == responder-chain ]] || { print -u2 'Not the fast-share candidate'; exit 1; }
        else
            [[ "$launch_policy" == manual-open ]] || {
                print -u2 'Fast-share uses an unsupported launch workaround. Use --fast-candidate for its audit, not the documented-only check.'
                exit 1
            }
        fi
    fi
    for binary_path in "$bundle_path/$executable_name" "$bundle_path/$executable_name.debug.dylib"; do
        [[ -f "$binary_path" ]] || continue
        if /usr/bin/strings "$binary_path" | rg "$private_patterns"; then
            print -u2 "Personal-only code found in $bundle_id"
            exit 1
        fi
        if /usr/bin/strings "$binary_path" | rg 'FloatPendingWithCodIntent|Public launch experiment|Test system Float'; then
            print -u2 "Simulator launch-probe code found in $bundle_id"
            exit 1
        fi
        if [[ "$check_mode" != --fast-candidate ]] && /usr/bin/strings "$binary_path" | rg 'FastShareAppLauncher|FastShareLaunchAttempt'; then
            print -u2 "Fast-share workaround unexpectedly present in $bundle_id"
            exit 1
        fi
    done
    /usr/bin/plutil -lint "$bundle_path/PrivacyInfo.xcprivacy"
    if [[ "$bundle_id" != com.josh.cod.store.controls ]]; then
        reason=$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPITypeReasons:0' "$bundle_path/PrivacyInfo.xcprivacy")
        [[ "$reason" == CA92.1 ]] || { print -u2 'Missing own-preferences declaration'; exit 1; }
        group_id=$(/usr/libexec/PlistBuddy -c 'Print :CodAppGroup' "$bundle_path/Info.plist")
        [[ "$group_id" == group.com.josh.cod.store ]] || { print -u2 'Incorrect App Group configuration'; exit 1; }
    fi
    print "Checked $bundle_id: privacy resource present; known private methods absent."
done

if [[ "$check_mode" == --fast-candidate ]]; then
    print 'Fast-share audit passed: known private code absent, unsupported launch explicitly declared. This is NOT App Review approval or a supported extension launch contract.'
    exit 0
fi

if [[ "${2:-}" == --submission ]]; then
    policy_url=$(/usr/libexec/PlistBuddy -c 'Print :CodPrivacyPolicyURL' "$app_path/Info.plist")
    [[ "$policy_url" == https://* && "$policy_url" != *'$('* ]] || {
        print -u2 'A real hosted HTTPS privacy policy must be configured before submission.'
        exit 1
    }
fi
print 'Local checks passed. This does not validate distribution signing, App Groups provisioning, review acceptance, or the hosted policy contents.'
