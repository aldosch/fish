# chromium-ext-update - install/update unpacked Chromium extensions from GitHub
#
# Reads chromium/extensions.json (tracked) and, for each entry, installs or
# updates an unpacked extension, so nothing depends on the Chrome Web Store
# (which removed all MV2 extensions on 2026-08-31, killing the
# chromium-web-store install/update path for uBlock Origin).
#
# Two modes per entry:
#   release (default) - downloads the repo's latest GitHub release zip and
#                       rsyncs the extracted contents over the existing dir.
#                       The install path never changes, so the unpacked
#                       extension ID and all stored settings survive updates.
#                       The version pin in extensions.json advances and is
#                       left for the next commit.
#   source            - the install dir IS a git checkout where source ==
#                       build (no build step). Updates are `git pull --ff-only`
#                       into the checkout, so local dev commits are preserved
#                       (diverged/dirty trees are skipped, never reset).
#                       Used for chrome-blank-new-tab, which is tracked as a
#                       gitlink here and has no release pipeline.
#
# Usage:
#   chromium-ext-update      - install/update all pinned extensions (called by
#                              nixx full update; safe to run manually)
#
# Extensions load unpacked from ~/.config/chromium/<dir>; after an update,
# restart Chromium (or reload in chrome://extensions) to pick it up.
#
# Not every extension can live here: release entries must ship a browser-ready
# zip in their GitHub releases (source-only repos like Kagi would need a build
# step; closed-source extensions stay on the CWS via chromium-web-store).
# Migrating an existing CWS install to unpacked gives it a new extension ID:
# export its settings from the dashboard first, restore after loading.

function chromium-ext-update
    set -l manifest "$HOME/.config/chromium/extensions.json"

    if not test -f "$manifest"
        echo "  ✗ chromium-ext-update: manifest not found: $manifest"
        return 1
    end

    set -l count (jq '.extensions | length' $manifest)
    set -l failures 0
    set -l updated 0

    for i in (seq 0 (math $count - 1))
        set -l name (jq -r ".extensions[$i].name" $manifest)
        set -l repo (jq -r ".extensions[$i].repo" $manifest)
        set -l dir (jq -r ".extensions[$i].dir" $manifest)
        set -l mode (jq -r ".extensions[$i].mode // \"release\"" $manifest)
        set -l ext_dir "$HOME/.config/chromium/$dir"

        # --- source mode: the checkout IS the install; fast-forward pull ---
        if test "$mode" = "source"
            if not test -d "$ext_dir/.git"
                git clone --quiet https://github.com/$repo.git $ext_dir
                if test $status -ne 0
                    echo "  ✗ $name: could not clone github.com/$repo"
                    set failures (math $failures + 1)
                else
                    echo "  ✓ $name cloned to $ext_dir (load unpacked to activate)"
                    set updated (math $updated + 1)
                end
                continue
            end

            set -l before (git -C $ext_dir rev-parse --short HEAD 2>/dev/null)
            git -C $ext_dir pull --quiet --ff-only 2>/dev/null
            if test $status -ne 0
                echo "  ✗ $name: git pull failed (diverged, uncommitted, or no ff path) - resolve in $ext_dir"
                set failures (math $failures + 1)
                continue
            end

            set -l after (git -C $ext_dir rev-parse --short HEAD 2>/dev/null)
            if test "$before" = "$after"
                echo "  ✓ $name up to date ($after)"
            else
                echo "  ✓ $name updated $before -> $after"
                set updated (math $updated + 1)
            end
            continue
        end

        # --- release mode: download the latest GitHub release zip ---
        set -l asset (jq -r ".extensions[$i].asset" $manifest)
        set -l pin (jq -r ".extensions[$i].version" $manifest)

        set -l latest (curl -fsSL https://api.github.com/repos/$repo/releases/latest \
            | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])' 2>/dev/null)

        if test -z "$latest"
            echo "  ✗ $name: could not fetch latest release from github.com/$repo"
            set failures (math $failures + 1)
            continue
        end

        # Already at the pinned/latest version with the extension on disk
        if test "$pin" = "$latest"; and test -f "$ext_dir/manifest.json"
            echo "  ✓ $name $pin (up to date)"
            continue
        end

        set -l url "https://github.com/$repo/releases/download/$latest/"(string replace '{version}' $latest $asset)
        set -l tmp (mktemp -d)
        or begin
            echo "  ✗ $name: mktemp failed"
            set failures (math $failures + 1)
            continue
        end

        curl -fsSL -o "$tmp/ext.zip" "$url"
        if test $status -ne 0
            echo "  ✗ $name: download failed: $url"
            rm -rf $tmp
            set failures (math $failures + 1)
            continue
        end

        unzip -q "$tmp/ext.zip" -d "$tmp/unpacked"
        set -l ext_src (find "$tmp/unpacked" -name manifest.json -maxdepth 2 -exec dirname {} \; | head -1)
        if test -z "$ext_src" -o ! -f "$ext_src/manifest.json"
            echo "  ✗ $name: no manifest.json in release zip"
            rm -rf $tmp
            set failures (math $failures + 1)
            continue
        end

        mkdir -p $ext_dir
        rsync -a --delete "$ext_src/" "$ext_dir/"
        rm -rf $tmp

        # sanity check the result
        set -l installed (python3 -c "import json;print(json.load(open('$ext_dir/manifest.json'))['version'])" 2>/dev/null)
        if test -z "$installed"
            echo "  ✗ $name: installed manifest unreadable"
            set failures (math $failures + 1)
            continue
        end

        # advance the pin
        jq --arg v "$latest" '.extensions['$i'].version = $v' $manifest >"$manifest.tmp"
        and mv "$manifest.tmp" $manifest

        echo "  ✓ $name updated to $latest"
        set updated (math $updated + 1)
    end

    if test $updated -gt 0
        echo "    restart Chromium (or reload in chrome://extensions) to pick up updates"
        echo "  ℹ remember to commit chromium/extensions.json"
    end

    return $failures
end
