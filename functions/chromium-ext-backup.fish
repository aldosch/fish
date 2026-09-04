# chromium-ext-backup - snapshot all Chromium extension storage
#
# Chromium stores every extension's settings in per-profile LevelDB dirs:
#   <profile>/Local Extension Settings/<extension-id>/
# This snapshots all of them, for every profile, including Chrome Web Store
# extensions that have no export button (Kagi, Unhook, ModHeader, ...), so
# settings survive profile corruption or a new-machine restore without
# touching any extension UI. Safe to run while Chromium is open: a LevelDB
# copy caught mid-write only drops the in-flight records, never corrupts.
#
# Snapshots land in ~/.config/chromium/backups/storage/snap-<timestamp>/
# (gitignored: extension storage carries identity tokens and per-site data,
# and publish-dots must never ship it). rsync --link-dest hardlinks
# unchanged files against the previous snapshot; snapshots with zero new
# data are dropped. Keeps the last 7.
#
# Restore (manual, with Chromium closed):
#   rsync -a --delete "$HOME/.config/chromium/backups/storage/<snap>/<profile>/" \
#     "$HOME/.config/chromium/profile/<profile>/Local Extension Settings/"
# Extension IDs are stable across machines because unpacked extensions are
# keyed to their (identical) install paths.
#
# Usage:
#   chromium-ext-backup      - snapshot if anything changed (called by the
#                              daily maintenance LaunchAgent; safe to run
#                              manually)

function chromium-ext-backup
    set -l profiles_dir "$HOME/.config/chromium/profile"
    set -l backups_dir "$HOME/.config/chromium/backups/storage"
    set -l keep 7

    if not test -d "$profiles_dir"
        echo "  ✗ chromium-ext-backup: no profile dir at $profiles_dir"
        return 1
    end
    mkdir -p $backups_dir

    set -l stamp (date +%Y-%m-%dT%H%M%S)
    set -l snap "$backups_dir/snap-$stamp"
    set -l prev ""
    for d in (find $backups_dir -maxdepth 1 -name 'snap-*' -type d 2>/dev/null | sort)
        set prev $d
    end

    set -l changed 0
    for prof_dir in $profiles_dir/*/
        set -l les "$prof_dir/Local Extension Settings"
        if not test -d "$les"
            continue
        end
        set -l prof (string replace -r -- '.*/(.*)/$' '$1' $prof_dir)
        set -l dest "$snap/$prof"
        mkdir -p $dest

        set -l out (rsync -ai --link-dest="$prev/$prof" "$les" "$dest/" 2>/dev/null)
        or begin
            echo "  ✗ chromium-ext-backup: rsync failed for $prof"
            rm -rf $dest
            return 1
        end
        set -l new (count (string match -r '^>' -- $out) 2>/dev/null)
        if test "$new" -gt 0
            echo "    $prof: $new file(s) changed"
            set changed (math $changed + $new)
        else
            rm -rf $dest
        end
    end

    if test "$changed" -eq 0
        rm -rf $snap
        echo "  ✓ chromium-ext-backup: nothing changed since the last snapshot"
        return 0
    end

    # manifest: profile -> extension id -> size, names resolved for known unpacked ids
    python3 -c '
import hashlib, json, os, sys
snap = sys.argv[1]
manifest_path = sys.argv[2]

def unpacked_id(path):
    h = hashlib.sha256(path.encode()).hexdigest()[:32]
    return "".join(chr(ord("a") + int(c, 16)) for c in h)

names = {}
if os.path.exists(manifest_path):
    for e in json.load(open(manifest_path))["extensions"]:
        d = os.path.expanduser("~/.config/chromium/" + e["dir"])
        names[unpacked_id(d)] = e["name"]

def dirsize(p):
    t = 0
    for root, _, files in os.walk(p):
        for f in files:
            t += os.path.getsize(os.path.join(root, f))
    return t

out = {"snapshot": os.path.basename(snap), "profiles": {}}
for prof in sorted(os.listdir(snap)):
    pdir = os.path.join(snap, prof)
    if not os.path.isdir(pdir):
        continue
    exts = {}
    for eid in sorted(os.listdir(os.path.join(pdir, "Local Extension Settings"))):
        exts[names.get(eid, eid)] = dirsize(os.path.join(pdir, "Local Extension Settings", eid))
    out["profiles"][prof] = exts
json.dump(out, open(os.path.join(snap, "manifest.json"), "w"), indent=2)
' "$snap" "$HOME/.config/chromium/extensions.json"

    # prune beyond the last $keep snapshots
    set -l snaps (ls -d $backups_dir/snap-* 2>/dev/null | sort)
    set -l prune_count (math (count $snaps) - $keep)
    if test "$prune_count" -gt 0
        for old in $snaps[1..$prune_count]
            rm -rf $old
            echo "    pruned "(basename $old)
        end
    end

    echo "  ✓ chromium-ext-backup: snapshot "(basename $snap)" ($changed file(s) new, "(count $snaps)" retained)"
end
