function opencode-sync --description 'Keep the locally-patched opencode current: merge upstream mainline into aldo/patches, rebuild, reinstall'
    # opencode runs from a local build of ~/repos/opencode (branch aldo/patches)
    # that abbreviates the home dir in the prompt footer cwd (~/.config instead
    # of /Users/you/.config). The binary installs to ~/.local/bin where it
    # shadows the brew opencode (kept in apps.nix as fallback). This function:
    #
    #   1. merges origin/dev (the mainline releases are cut from) into the branch
    #   2. rebuilds (bun) and reinstalls to ~/.local/bin when HEAD changed
    #
    # 1.x releases carry no git tags, so the sync tracks origin/dev rather than
    # tags (unlike kew-sync/ghostty-sync). No fork: the branch is local-only;
    # the upstream PR comes later (see Things "Create upstream PR: opencode").
    #
    # Requires bun. On merge conflict or build failure: aborts, leaves the
    # installed binary untouched, prints a warning (nixx surfaces it;
    # maintenance logs it).
    #
    # Called by:
    #   - scripts/maintenance/maintenance.sh (daily, 10:00)
    #   - `nixx` full update (opencode step in the DAG)
    #   - `opencode-sync` (manual)

    set -l repo ~/repos/opencode
    set -l branch aldo/patches
    set -l bin ~/.local/bin/opencode
    set -l stamp_dir ~/.local/state/opencode
    set -l stamp $stamp_dir/build-head

    # --- repo present and clean? ---
    if not test -d $repo/.git
        echo "opencode-sync: ~/repos/opencode not found (clone anomalyco/opencode there first)"
        return 1
    end

    if not test -x (command -v bun)
        echo "opencode-sync: bun not found (required to build)"
        return 1
    end

    if not git -C $repo diff --quiet 2>/dev/null; or not git -C $repo diff --cached --quiet 2>/dev/null
        echo "opencode-sync: ~/repos/opencode has uncommitted changes, skipping"
        return 1
    end

    git -C $repo checkout $branch --quiet 2>/dev/null

    # --- newest upstream mainline already merged? ---
    git -C $repo fetch origin dev --quiet 2>/dev/null

    set -l reason ""

    if not git -C $repo merge-base --is-ancestor origin/dev $branch 2>/dev/null
        echo "opencode-sync: merging origin/dev into $branch"
        if not git -C $repo merge --no-edit origin/dev --quiet
            git -C $repo merge --abort 2>/dev/null
            echo "opencode-sync: merge conflict with origin/dev — resolve manually in ~/repos/opencode, then run opencode-sync again"
            return 1
        end
        set reason "merged origin/dev"
    end

    # --- rebuild when the installed binary is behind HEAD (also covers a
    # deleted binary or fresh clones) ---
    set -l head (git -C $repo rev-parse HEAD)
    set -l built (cat $stamp 2>/dev/null)

    if test "$built" = "$head" -a -x "$bin"
        echo "opencode-sync: opencode is current ("(git -C $repo describe --always)")"
        return 0
    end

    if test -z "$reason"
        set reason "rebuild (binary is behind "(git -C $repo describe --always)")"
    end

    # --- build: root deps + single darwin-arm64 binary (~1 min) ---
    echo "opencode-sync: building ("$reason")"
    # not --frozen-lockfile: the committed bun.lock needs one non-frozen
    # resolve (legacy pnpm-lock.yaml migration); bun.lock is restored after
    # the build below, so the dirty-check stays reliable
    if not bun install --cwd $repo --quiet 2>$repo/.opencode-sync-install.log
        echo "opencode-sync: bun install failed — see ~/repos/opencode/.opencode-sync-install.log (installed binary untouched)"
        return 1
    end

    if not bun run --cwd $repo/packages/opencode build --single >/dev/null 2>$repo/.opencode-sync-build.log
        echo "opencode-sync: build failed — see ~/repos/opencode/.opencode-sync-build.log (installed binary untouched)"
        return 1
    end

    # build.ts re-resolves cross-platform deps into bun.lock every run; restore
    # it so the dirty-check above stays reliable on the next sync
    git -C $repo checkout -- bun.lock 2>/dev/null

    # --- install (rm first so a running opencode keeps its old inode) ---
    if not test -x "$repo/packages/opencode/dist/opencode-darwin-arm64/bin/opencode"
        echo "opencode-sync: build succeeded but binary missing at packages/opencode/dist/opencode-darwin-arm64/bin/opencode"
        return 1
    end

    rm -f $bin
    if not cp "$repo/packages/opencode/dist/opencode-darwin-arm64/bin/opencode" $bin
        echo "opencode-sync: install to ~/.local/bin failed"
        return 1
    end

    mkdir -p $stamp_dir
    git -C $repo rev-parse HEAD >$stamp
    rm -f $repo/.opencode-sync-install.log $repo/.opencode-sync-build.log

    echo "opencode-sync: installed "(git -C $repo describe --always)" at "(date '+%H:%M')" — restart opencode to pick it up"
    return 0
end
