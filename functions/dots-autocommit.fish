# dots-autocommit - commit + push machine-generated state churn in ~/.config
#
# Lockfiles and app-state files in this repo change themselves: `nix flake
# update`, `skills add` / skills-sync, nvim's Lazy sync, chromium-ext-update
# version pins, pnpm updates. This function commits exactly that churn and
# pushes it, so it never needs manual staging. Called at the end of `nixx`
# and by the daily maintenance job (scripts/maintenance).
#
# Allowlist (the ONLY files it will ever commit):
#   nix/flake.lock            - nixx flake update
#   nvim/lazy-lock.json       - nvim Lazy sync
#   agents/.skill-lock.json   - skills add / skills-sync
#   opencode/pnpm-lock.yaml   - pnpm update --dir ~/.config/opencode
#   chromium/extensions.json  - chromium-ext-update version pins
#   docs/pnpm-lock.yaml       - docs dependency updates
#   pnpm-lock.yaml            - root package.json
#
# TODO.md is committed only when its whole diff consists of added
# `nixx: ... (auto-logged)` lines (written by nixx's failure auto-log);
# manual curation edits are never swept up.
#
# Safety: pathspec-scoped adds only (never -A/.), skipped during a
# rebase/merge, and on push failure it rebases onto the remote (aborting on
# conflict) — a failed push just retries on the next run. Both hosts (min,
# book) run this against the same remote, so benign push races are expected.

function dots-autocommit --description 'Commit + push generated state churn'
    # optional repo override (testing); defaults to this dotfiles repo
    set -l repo ~/.config
    if test (count $argv) -ge 1
        set repo $argv[1]
    end
    if not git -C $repo rev-parse --is-inside-work-tree >/dev/null 2>&1
        return 0
    end

    # never touch a repo mid-rebase/merge
    if test -d "$repo/.git/rebase-merge"; or test -d "$repo/.git/rebase-apply"; or test -f "$repo/.git/MERGE_HEAD"
        return 0
    end

    # --- push helper: rebase over remote races, never force ---
    # (takes the repo as an argument: fish locals aren't visible in callees)
    function __dots_autocommit_push --argument-names repo
        git -C $repo push -q origin HEAD 2>/dev/null; and return 0

        # remote moved ahead (the other machine). Rebasing needs a clean
        # tree: with local edits in flight, defer instead of touching
        # anything (the commit is safe; the next run pushes it).
        set -l dirty (git -C $repo status --porcelain)
        if test -n "$dirty"
            echo "dots-autocommit: push deferred (dirty worktree) — retrying next run"
            return 1
        end
        git -C $repo pull --rebase -q 2>/dev/null
        if test $status -ne 0
            git -C $repo rebase --abort 2>/dev/null
            echo "dots-autocommit: push failed (rebase conflict) — retrying next run"
            return 1
        end
        git -C $repo push -q origin HEAD 2>/dev/null; or begin
            echo "dots-autocommit: push failed — retrying next run"
            return 1
        end
        return 0
    end

    # --- what's dirty among allowlisted files? ---
    set -l allowlist \
        nix/flake.lock \
        nvim/lazy-lock.json \
        agents/.skill-lock.json \
        opencode/pnpm-lock.yaml \
        chromium/extensions.json \
        docs/pnpm-lock.yaml \
        pnpm-lock.yaml

    set -l to_commit (git -C $repo status --porcelain -- $allowlist | string sub --start 4 | string trim)

    # --- TODO.md: only pure auto-logged additions ---
    if git -C $repo status --porcelain -- TODO.md | grep -q .
        set -l diff (git -C $repo diff HEAD -- TODO.md)
        set -l added (string match -r '^\+[^\+].*' -- $diff)
        set -l removed (string match -r '^-[^-].*' -- $diff)
        set -l todo_ok 1
        if test (count $added) -eq 0; or test (count $removed) -ne 0
            set todo_ok 0
        end
        for line in $added
            if not string match -qr '^\+- \[ \] nixx: .+\(auto-logged\)' -- $line
                set todo_ok 0
                break
            end
        end
        if test $todo_ok -eq 1
            set -a to_commit TODO.md
        end
    end

    # --- nothing to commit: still push a previously-failed pending HEAD ---
    if test (count $to_commit) -eq 0
        # fetch first: a stale tracking ref would hide pending commits (e.g.
        # after the other machine force-pushed a history rewrite)
        git -C $repo fetch -q origin 2>/dev/null
        set -l ahead (git -C $repo rev-list --count '@{u}..HEAD' 2>/dev/null)
        if test -n "$ahead"; and test "$ahead" -gt 0
            __dots_autocommit_push $repo
        end
        return 0
    end

    # --- commit ---
    if not git -C $repo add -- $to_commit
        echo "dots-autocommit: git add failed"
        return 1
    end
    set -l names (for f in $to_commit; basename $f; end | string join ", ")
    if not git -C $repo commit -q -m "auto: state churn ($names)"
        # raced with something that already committed — reset the index, stay quiet
        git -C $repo reset -q 2>/dev/null
        return 0
    end

    # --- push ---
    if __dots_autocommit_push $repo
        echo "dots-autocommit: committed + pushed ($names)"
    end
    return 0
end
