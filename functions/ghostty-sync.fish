function ghostty-sync --description 'Keep the locally-patched Ghostty current: merge upstream tags into aldo/patches, rebuild, reinstall'
    # Ghostty runs from a local build of ~/repos/ghostty (branch aldo/patches)
    # that hides the tab bar UI (tabs stay functional; gt is the switcher).
    # The brew cask was removed from apps.nix — zap would uninstall the local
    # app. This function:
    #
    #   1. fast-forwards the patch branch to origin (no fork: local-only)
    #   2. merges the newest upstream (ghostty-org/ghostty) tag into the branch
    #   3. rebuilds libghostty (zig, xcframework) + the macOS app (xcodebuild)
    #      and reinstalls to /Applications when HEAD changed
    #
    # Requires full Xcode (xcodebuild); DEVELOPER_DIR is set explicitly so the
    # global xcode-select (currently CommandLineTools) is left untouched.
    #
    # Called by:
    #   - scripts/maintenance/maintenance.sh (daily, 10:00)
    #   - `nixx` full update (ghostty step in the DAG)
    #   - `ghostty-sync` (manual)

    set -l repo ~/repos/ghostty
    set -l branch aldo/patches
    set -l app /Applications/Ghostty.app
    set -l stamp_dir ~/.local/state/ghostty
    set -l stamp $stamp_dir/build-head
    set -l xcode /Applications/Xcode.app/Contents/Developer

    _aldo_dracula_apply_palette

    # --- repo present and clean? ---
    if not test -d $repo/.git
        echo "ghostty-sync: ~/repos/ghostty not found (clone ghostty-org/ghostty there first)"
        return 1
    end

    if not test -d $xcode
        echo "ghostty-sync: Xcode not installed ($xcode required to build the macOS app)"
        return 1
    end

    if not git -C $repo diff --quiet 2>/dev/null; or not git -C $repo diff --cached --quiet 2>/dev/null
        echo "ghostty-sync: ~/repos/ghostty has uncommitted changes, skipping"
        return 1
    end

    git -C $repo checkout $branch --quiet 2>/dev/null

    # --- newest upstream tag already merged? ---
    git -C $repo fetch origin --tags --quiet 2>/dev/null
    set -l latest (git -C $repo tag -l 'v[0-9]*' --sort=-v:refname | head -1)

    if test -z "$latest"
        echo "ghostty-sync: no upstream tags found"
        return 1
    end

    set -l reason ""

    if not git -C $repo merge-base --is-ancestor $latest $branch 2>/dev/null
        echo "ghostty-sync: merging $latest into $branch"
        if not git -C $repo merge --no-edit $latest --quiet
            git -C $repo merge --abort 2>/dev/null
            echo "ghostty-sync: merge conflict for $latest — resolve manually in ~/repos/ghostty, then run ghostty-sync again"
            return 1
        end
        set reason "merged $latest"
    end

    # --- rebuild when the installed app is behind HEAD (also covers a deleted
    # app or fresh clones) ---
    set -l head (git -C $repo rev-parse HEAD)
    set -l built (cat $stamp 2>/dev/null)

    if test "$built" = "$head" -a -d "$app"
        echo "ghostty-sync: ghostty is current ("(git -C $repo describe --tags --always)")"
        return 0
    end

    if test -z "$reason"
        set reason "rebuild (app is behind "(git -C $repo describe --tags --always)")"
    end

    # --- 1. libghostty: zig builds GhosttyKit.xcframework + resources ---
    echo "ghostty-sync: building libghostty ("$reason")"
    if not env DEVELOPER_DIR=$xcode zig build -Doptimize=ReleaseFast -Demit-xcframework=true --build-file $repo/build.zig >/dev/null 2>$repo/.zig-build.log
        echo "ghostty-sync: zig build failed — see ~/repos/ghostty/.zig-build.log (installed app untouched)"
        return 1
    end

    # --- 2. macOS app: xcodebuild with a clean env (mirrors macos/build.nu,
    # which we don't use because nushell isn't installed) ---
    echo "ghostty-sync: building Ghostty.app"
    set -l conf ReleaseLocal
    if not env -i HOME="$HOME" DEVELOPER_DIR=$xcode PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        xcodebuild -project $repo/macos/Ghostty.xcodeproj -scheme Ghostty \
        -configuration $conf SYMROOT=$repo/macos/build -quiet build >/dev/null 2>$repo/.xcodebuild.log
        # ReleaseLocal may not exist on older checkouts; fall back to Release
        set conf Release
        if not env -i HOME="$HOME" DEVELOPER_DIR=$xcode PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
            xcodebuild -project $repo/macos/Ghostty.xcodeproj -scheme Ghostty \
            -configuration $conf SYMROOT=$repo/macos/build -quiet build >/dev/null 2>$repo/.xcodebuild.log
            echo "ghostty-sync: xcodebuild failed — see ~/repos/ghostty/.xcodebuild.log (installed app untouched)"
            return 1
        end
    end

    # --- 3. install ---
    if not test -d "$repo/macos/build/$conf/Ghostty.app"
        echo "ghostty-sync: build succeeded but app bundle missing at macos/build/$conf/Ghostty.app"
        return 1
    end

    if test -d $app
        # Quit the running app so the bundle can be replaced cleanly
        osascript -e 'tell application "Ghostty" to quit' >/dev/null 2>&1
        sleep 1
        rm -rf $app
    end

    if not cp -R "$repo/macos/build/$conf/Ghostty.app" $app
        echo "ghostty-sync: install to /Applications failed"
        return 1
    end

    mkdir -p $stamp_dir
    git -C $repo rev-parse HEAD >$stamp

    echo "ghostty-sync: installed "(git -C $repo describe --tags --always)" at "(date '+%H:%M')" — restart Ghostty to pick it up"
    return 0
end
