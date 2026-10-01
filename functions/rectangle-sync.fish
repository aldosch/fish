# rectangle-sync - back up live Rectangle settings into the dotfiles repo
#
# Rectangle keeps its settings in the macOS defaults domain
# com.knollsoft.Rectangle (~/Library/Preferences/com.knollsoft.Rectangle.plist).
# That plist is the complete source of truth: every setting, every shortcut.
# Rectangle's own File > Export format (the old RectangleConfig.json here) is
# a curated subset that goes stale the moment a setting changes, so the plist
# snapshot replaced it.
#
# The snapshot is host-suffixed (Rectangle.$hostname.plist) because both
# hosts (min, book) share this repo via git and may legitimately diverge.
# dots-autocommit commits + pushes both snapshots when they change.
#
# Transient keys are filtered out so diffs stay meaningful:
#   NS*                     - AppKit UI state (window frames, nav panels)
#   SUHasLaunchedBefore     - Sparkle updater state
#   SULastCheckTime         - Sparkle updater state
#   SUUpdateGroupIdentifier - Sparkle updater state
#
# Functions:
#   rectangle-sync         write rectangle/Rectangle.$hostname.plist from live settings
#   __rect_filtered_plist  filtered live domain as XML plist on stdout
#   __rect_diff_keys       compare snapshot vs live; TSV change lines on stdout
#                          (kind\tkey\told[\tnew]); rc 0 = clean, 1 = drift, 2 = error

function rectangle-sync --description 'Snapshot live Rectangle settings to rectangle/Rectangle.$hostname.plist'
    set -l snapshot ~/.config/rectangle/Rectangle.$hostname.plist
    if not type -q python3
        echo "rectangle-sync: python3 not found" >&2
        return 1
    end
    mkdir -p (dirname $snapshot)
    set -l tmp $snapshot.tmp
    if not __rect_filtered_plist >$tmp
        rm -f $tmp
        echo "rectangle-sync: could not export com.knollsoft.Rectangle (is Rectangle installed?)" >&2
        return 1
    end
    mv $tmp $snapshot
    echo "rectangle-sync: wrote $snapshot"
    return 0
end

function __rect_filtered_plist
    python3 -c '
import plistlib, subprocess, sys
NOISE_PREFIX = ("NS",)
NOISE_KEYS = {"SUHasLaunchedBefore", "SULastCheckTime", "SUUpdateGroupIdentifier"}
raw = subprocess.run(
    ["defaults", "export", "com.knollsoft.Rectangle", "-"],
    capture_output=True, check=True
).stdout
data = plistlib.loads(raw)
out = {k: v for k, v in data.items()
       if not k.startswith(NOISE_PREFIX) and k not in NOISE_KEYS}
plistlib.dump(out, sys.stdout.buffer, sort_keys=True)
'
end

function __rect_diff_keys --argument-names snapshot
    test -f "$snapshot"; or return 2
    set -l out (python3 -c '
import plistlib, subprocess, sys
NOISE_PREFIX = ("NS",)
NOISE_KEYS = {"SUHasLaunchedBefore", "SULastCheckTime", "SUUpdateGroupIdentifier"}
def clean(d):
    return {k: v for k, v in d.items()
            if not k.startswith(NOISE_PREFIX) and k not in NOISE_KEYS}
with open(sys.argv[1], "rb") as f:
    snap = clean(plistlib.load(f))
raw = subprocess.run(
    ["defaults", "export", "com.knollsoft.Rectangle", "-"],
    capture_output=True, check=True
).stdout
live = clean(plistlib.loads(raw))
for k in sorted(set(snap) | set(live)):
    if k not in live:
        print("removed\t" + k + "\t" + repr(snap[k]))
    elif k not in snap:
        print("added\t" + k + "\t" + repr(live[k]))
    elif snap[k] != live[k]:
        print("changed\t" + k + "\t" + repr(snap[k]) + "\t" + repr(live[k]))
' $snapshot)
    if test $status -ne 0
        return 2
    end
    if test (count $out) -gt 0
        printf '%s\n' $out
        return 1
    end
    return 0
end
