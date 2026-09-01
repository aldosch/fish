# skills-sync - keep agent skills current, fast
#
# Replaces the old skills-restore / skills-bg-update / skills-smart-update trio
# (and the background LaunchAgent that went with them).
#
# `skills update -g -y` checks all 20+ source repos sequentially (2-4 min).
# This function fetches every repo's `pushed_at` in parallel with bounded
# curl requests (~2s; gh api has no total timeout, so a black-holed
# connection could stall the step until nixx's watchdog kills it),
# compares against a tiny cache, and calls `skills update` only for skills
# whose repo actually has new commits since the last check. The cache stores
# just one timestamp per repo — without it, repos that pushed to unrelated
# paths would be re-flagged forever (skills update doesn't advance updatedAt
# when content hasn't changed).
#
# Usage:
#   skills-sync           - parallel pre-check + targeted update (called by nixx)
#   skills-sync --restore - reinstall all skills from the lockfile (new machine)
#
# Skills with sourceType "local" point to private repos. If the repo is not
# accessible on this machine, the install will fail non-fatally. A notice is
# printed with remediation steps.

function skills-sync
    if not type -q gum
        echo "Error: gum is not installed. add 'gum' to nix/modules/apps.nix then run nixx l"
        return 1
    end

    _aldo_dracula_apply_palette

    set -l do_restore 0
    for arg in $argv
        switch $arg
            case --restore -r
                set do_restore 1
        end
    end

    set -l lockfile "$HOME/.config/agents/.skill-lock.json"
    set -l cache_file "$HOME/.config/agents/.skills-update-cache.json"

    if not test -f "$lockfile"
        gum style --foreground $p_red "  ✗ Lockfile not found: $lockfile"
        return 1
    end

    # --- restore mode: reinstall everything from the lockfile ---
    if test $do_restore -eq 1
        if not type -q skills
            gum style --foreground $p_red "  ✗ skills CLI not found. Run: pnpm add -g skills"
            return 1
        end

        echo
        gum style --bold --foreground $p_purple --border rounded --border-foreground $p_purple \
            --padding "0 2" --align center \
            "skills-sync --restore" \
            (gum style --faint --foreground $p_muted "reinstalling from .skill-lock.json")
        echo

        set -l t_start (date +%s)
        gum spin --spinner dot \
            --spinner.foreground $p_purple \
            --title.foreground $p_muted \
            --title "  Reinstalling skills from lockfile..." \
            -- fish -c "skills experimental_install -g -y" >/dev/null 2>&1
        set -l rc $status
        set -l t_end (date +%s)
        set -l elapsed (__nixx_fmt_time (math "$t_end - $t_start"))

        if test $rc -eq 0
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " Skills restored") \
                (gum style --foreground $p_muted " ($elapsed)")
        else
            gum join --horizontal \
                (gum style --foreground $p_orange "  ▲") \
                (gum style --foreground $p_fg " Skills restore completed with warnings") \
                (gum style --foreground $p_muted " ($elapsed)")
        end

        # one-line notice for private-source skills
        set -l local_count (jq '[.skills | to_entries[] | select(.value.sourceType == "local")] | length' "$lockfile" 2>/dev/null; or echo 0)
        if test "$local_count" -gt 0
            echo
            gum style --foreground $p_orange --bold "  ▸ Private-source skills"
            gum style --foreground $p_muted \
                "  $local_count skill(s) come from private repos and may not have restored"
            gum style --foreground $p_muted \
                "  automatically. Check the output above and reinstall manually if needed."
        end

        echo
        return $rc
    end

    # --- update mode: parallel pre-check + targeted update ---
    if not type -q skills
        gum style --foreground $p_red "  ✗ skills CLI not found. Run: pnpm add -g skills"
        return 1
    end
    if not type -q gh
        gum style --foreground $p_red "  ✗ gh CLI not found (needed for GitHub API). Run: gh auth login"
        return 1
    end

    set -l t_start (date +%s)

    # skill|repo pairs (github skills only)
    set -l rows (jq -r '
        .skills | to_entries[]
        | select(.value.sourceType == "github")
        | [.key, .value.source] | join("|")
    ' "$lockfile" 2>/dev/null)

    if test (count $rows) -eq 0
        gum style --foreground $p_muted "  No GitHub-sourced skills in lockfile"
        return 0
    end

    # unique repos
    set -l repos
    for row in $rows
        set -l repo (string split "|" -- $row)[2]
        if not contains -- $repo $repos
            set -a repos $repo
        end
    end
    set -l n_repos (count $repos)

    # parallel fetch of pushed_at per repo into temp files.
    # curl (not gh api) so each request is bounded by --max-time: gh has no
    # total timeout and a black-holed connection would stall the `wait` until
    # nixx's watchdog kills the whole skills step. Repos that fail or time out
    # end up with no file and are treated as inaccessible (skipped) below.
    set -l tmpdir (mktemp -d /tmp/skills-sync-XXXX)
    set -l gh_token (gh auth token 2>/dev/null)
    for repo in $repos
        set -l key (string replace -a '/' '__' -- $repo)
        curl -fsSL --max-time 15 \
            -H "Authorization: Bearer $gh_token" \
            "https://api.github.com/repos/$repo" 2>/dev/null \
            | jq -r '.pushed_at // empty' >"$tmpdir/$key" 2>/dev/null &
    end
    wait

    # find repos whose pushed_at changed since last check.
    # repos returning error blobs (SAML, 404) are skipped: we can't check or
    # update them without org access, and flagging them would hang skills update.
    set -l changed_repos
    set -l skipped_repos
    set -l cache_pairs
    for repo in $repos
        set -l key (string replace -a '/' '__' -- $repo)
        set -l pushed (string trim (cat "$tmpdir/$key" 2>/dev/null))

        if not string match -qr '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' -- $pushed
            set -a skipped_repos $repo
            continue
        end

        # remember for cache write
        set -a cache_pairs "$repo=$pushed"

        # compare against cache (string equality, no ISO parsing needed)
        set -l cached (jq -r --arg r "$repo" '.repos[$r] // empty' "$cache_file" 2>/dev/null)
        if test -z "$cached"; or test "$pushed" != "$cached"
            set -a changed_repos $repo
        end
    end

    rm -rf $tmpdir

    # collect skills from changed repos
    set -l changed
    for row in $rows
        set -l parts (string split "|" -- $row)
        set -l skill $parts[1]
        set -l repo $parts[2]
        if contains -- $repo $changed_repos
            set -a changed $skill
        end
    end

    set -l n_changed (count $changed)
    set -l n_skipped (count $skipped_repos)
    set -l skip_note ""
    if test $n_skipped -gt 0
        set skip_note ", $n_skipped skipped (inaccessible)"
    end

    if test $n_changed -gt 0
        set -lx GITHUB_TOKEN (gh auth token 2>/dev/null)
        # log to a file (not /dev/null): a hung or failed update is otherwise
        # undebuggable — this exact call was blamed for a silent 5m skills hang
        set -l update_log /tmp/skills-sync-update-(date +%s).log
        skills update -g -y $changed >$update_log 2>&1
        set -l rc $status
        set -l t_end (date +%s)
        set -l elapsed (__nixx_fmt_time (math "$t_end - $t_start"))

        if test $rc -eq 0
            rm -f $update_log
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " $n_changed skill(s) updated ($n_repos repos checked$skip_note)") \
                (gum style --foreground $p_muted " ($elapsed)")
        else
            gum join --horizontal \
                (gum style --foreground $p_orange "  ▲") \
                (gum style --foreground $p_fg " $n_changed skill(s) updated with warnings") \
                (gum style --foreground $p_muted " ($elapsed)")
            if test -s $update_log
                gum style --foreground $p_muted --faint "     log: $update_log"
            else
                rm -f $update_log
            end
        end
    else
        set -l t_end (date +%s)
        set -l elapsed (__nixx_fmt_time (math "$t_end - $t_start"))
        gum join --horizontal \
            (gum style --foreground $p_green "  ✓") \
            (gum style --foreground $p_fg " $n_repos repos checked, all up to date$skip_note") \
            (gum style --foreground $p_muted " ($elapsed)")
    end

    # write cache: {repos: {repo: pushed_at}} for all accessible repos
    if test (count $cache_pairs) -gt 0
        set -l json_objs
        for pair in $cache_pairs
            set -l r (string split -m 1 "=" -- $pair)[1]
            set -l p (string split -m 1 "=" -- $pair)[2]
            set -a json_objs (jq -nc --arg repo "$r" --arg ts "$p" '{($repo): $ts}')
        end
        printf '%s\n' $json_objs | jq -s 'add // {} | {repos: .}' >"$cache_file" 2>/dev/null
    else
        echo '{"repos":{}}' >"$cache_file"
    end

    return 0
end
