function kew-sync --description 'Keep the locally-patched kew current: merge new upstream tags into aldo/patches, rebuild, reinstall'
    # kew runs from a personal fork (aldosch/kew, branch aldo/patches) that
    # carries the hideMetadata + title-wrap patch, installed to ~/.local/bin
    # where it shadows the brew kew. This function:
    #
    #   1. fast-forwards the local patch branch from the fork (other machines)
    #   2. merges the newest upstream (ravachol/kew) tag into the patch branch
    #   3. rebuilds and installs to ~/.local when HEAD changed
    #   4. pushes the updated branch back to the fork
    #
    # Syncs on upstream *tags* (release cadence), not every commit to main.
    # On merge conflict or build failure: aborts, leaves the running binary
    # untouched, prints a warning (nixx surfaces it; maintenance logs it).
    #
    # Called by:
    #   - scripts/maintenance/maintenance.sh (daily, 10:00)
    #   - `nixx` full update (kew step in the DAG)
    #   - `kew-sync` (manual)

    set -l repo ~/repos/kew
    set -l branch aldo/patches
    set -l stamp_dir ~/.local/state/kew
    set -l stamp $stamp_dir/build-head

    _aldo_dracula_apply_palette

    # --- repo present and clean? ---
    if not test -d $repo/.git
        echo "kew-sync: ~/repos/kew not found (clone aldosch/kew there first)"
        return 1
    end

    if not git -C $repo diff --quiet 2>/dev/null; or not git -C $repo diff --cached --quiet 2>/dev/null
        echo "kew-sync: ~/repos/kew has uncommitted changes, skipping"
        return 1
    end

    git -C $repo checkout $branch --quiet 2>/dev/null

    # --- pull fork updates (multi-machine: the other Mac may have pushed) ---
    git -C $repo fetch origin --quiet 2>/dev/null
    if not git -C $repo merge-base --is-ancestor $branch origin/$branch 2>/dev/null
        if not git -C $repo merge --ff-only origin/$branch --quiet 2>/dev/null
            echo "kew-sync: ~/repos/kew diverged from the fork, reconcile manually"
            return 1
        end
    end

    # --- newest upstream tag already merged? ---
    git -C $repo fetch upstream --tags --quiet 2>/dev/null
    set -l latest (git -C $repo tag -l 'v[0-9]*' --sort=-v:refname | head -1)

    if test -z "$latest"
        echo "kew-sync: no upstream tags found"
        return 1
    end

    set -l reason ""

    if not git -C $repo merge-base --is-ancestor $latest $branch 2>/dev/null
        echo "kew-sync: merging $latest into $branch"
        if not git -C $repo merge --no-edit $latest --quiet
            git -C $repo merge --abort 2>/dev/null
            echo "kew-sync: merge conflict for $latest — resolve manually in ~/repos/kew, then run kew-sync again"
            return 1
        end
        set reason "merged $latest"
    end

    # --- rebuild when the installed binary is behind HEAD (also covers a
    # deleted binary or fresh clones) ---
    set -l head (git -C $repo rev-parse HEAD)
    set -l built (cat $stamp 2>/dev/null)

    if test "$built" = "$head" -a -x "$HOME/.local/bin/kew"
        echo "kew-sync: kew is current ("(git -C $repo describe --tags --always)")"
        return 0
    end

    if test -z "$reason"
        set reason "rebuild (binary is behind "(git -C $repo describe --tags --always)")"
    end

    echo "kew-sync: building ("$reason")"
    # PREFIX must be passed at build time too: it's compiled in as the
    # data dir (layouts live in $PREFIX/share/kew/layouts).
    if not make -C $repo PREFIX="$HOME/.local" -j (sysctl -n hw.ncpu 2>/dev/null; or echo 4) >/dev/null 2>&1
        echo "kew-sync: build failed — run 'make -C $repo' to see the error (brew kew still works)"
        return 1
    end

    if not make -C $repo install PREFIX="$HOME/.local" >/dev/null 2>&1
        echo "kew-sync: install failed"
        return 1
    end

    mkdir -p $stamp_dir
    git -C $repo rev-parse HEAD >$stamp

    git -C $repo push origin $branch --quiet 2>/dev/null; or echo "kew-sync: warning: could not push $branch to origin"

    echo "kew-sync: installed "(git -C $repo describe --tags --always)" at "(date '+%H:%M')
    return 0
end
