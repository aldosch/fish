function pullall
    # ──────────────────────────────────────────────────────
    # USAGE: pullall [directory]
    # Pull all local branches (with upstream) across multiple repos
    # Default: ~/dev
    # Custom: pullall . (current dir) or pullall ~/some/path
    # ──────────────────────────────────────────────────────

    if not type -q gum
        echo "Error: gum is not installed. add 'gum' to nix/modules/apps.nix then run nixx l"
        return 1
    end

    _aldo_dracula_apply_palette

    # Determine directories to scan
    set -l scan_dirs
    if test (count $argv) -eq 0
        # Default: predefined directories
        set scan_dirs "$HOME/dev"
    else
        # Custom directory provided
        set -l target_dir $argv[1]
        if test "$target_dir" = "."
            set target_dir (pwd)
        end
        set scan_dirs (realpath "$target_dir")
    end

    # Validate directories exist
    for dir in $scan_dirs
        if not test -d "$dir"
            gum style --foreground $p_red "Error: Directory $dir does not exist"
            return 1
        end
    end

    # Header
    echo
    gum style --bold --foreground $p_purple --border rounded --border-foreground $p_purple \
        --padding "0 2" --align center \
        "pullall · git sync"
    echo

    # Activity cache for smart ordering
    set -l cache_file "$HOME/.cache/pullall-activity.txt"
    mkdir -p (dirname "$cache_file")
    
    # Load previous activity data (format: repo_path|last_commit_count|last_updated_timestamp)
    set -l activity_cache
    if test -f "$cache_file"
        set activity_cache (cat "$cache_file")
    end

    # Helper: get activity score for a repo (higher = more active)
    function __pullall_activity_score
        set -l repo_path $argv[1]
        
        # Check last commit in the last 30 days
        set -l recent_commits (git -C "$repo_path" rev-list --count --since="30 days ago" HEAD 2>/dev/null; or echo 0)
        
        # Check if we pulled commits last time (from cache)
        set -l historical_activity 0
        for entry in $activity_cache
            set -l parts (string split "|" -- "$entry")
            if test "$parts[1]" = "$repo_path"
                set historical_activity $parts[2]
                break
            end
        end
        
        # Score: recent commits * 2 + historical activity
        echo (math "$recent_commits * 2 + $historical_activity")
    end

    # Tracking
    set -l total_repos 0
    set -l repos_with_changes 0
    set -l total_commits_pulled 0
    set -l repos_with_errors 0
    set -l error_log
    set -l change_log
    set -l new_activity_cache

    # Pre-collect all repos across all scan dirs (needed for total count)
    set -l all_scan_repos  # format: "scan_dir|repo_path"
    for scan_dir in $scan_dirs
        set -l dir_repos
        for repo_path in $scan_dir/*/
            set -l repo_path (string trim --right --chars='/' -- "$repo_path")
            if test -d "$repo_path/.git"
                set -a dir_repos "$repo_path"
            end
        end

        # Sort this dir's repos by activity score (most active first)
        set -l scored
        for repo_path in $dir_repos
            set -l score (__pullall_activity_score "$repo_path")
            set -a scored "$score|$repo_path"
        end
        set scored (printf "%s\n" $scored | sort -t'|' -k1 -rn | cut -d'|' -f2-)

        for repo_path in $scored
            set -a all_scan_repos "$scan_dir|$repo_path"
        end
    end

    set -l grand_total (count $all_scan_repos)
    set -l repo_index 0

    # Process repos in order
    for entry in $all_scan_repos
        set -l parts (string split "|" -- "$entry")
        set -l scan_dir $parts[1]
        set -l repo_path $parts[2]
        set -l repo_name (basename "$repo_path")

        set repo_index (math $repo_index + 1)
        set total_repos (math $total_repos + 1)

        # Shorten the scan dir for display (~-style)
        set -l display_dir (string replace "$HOME" "~" "$scan_dir")

        # Show inline progress (overwrite same line)
        printf "\r\033[2K"
        printf "%s" (gum style --foreground $p_purple --faint "Scanning $display_dir →")" "(gum style --foreground $p_muted "$repo_name")" "(gum style --foreground $p_muted --faint "($repo_index/$grand_total)")

        # Store original branch
        set -l original_branch (git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
        if test $status -ne 0
            set -a error_log "$repo_name|Could not determine current branch"
            set repos_with_errors (math $repos_with_errors + 1)
            continue
        end

        # Check for uncommitted changes
        set -l has_changes (git -C "$repo_path" status --porcelain 2>/dev/null)
        set -l stashed false

        if test -n "$has_changes"
            # Stash changes
            git -C "$repo_path" stash push -m "pullall auto-stash" >/dev/null 2>&1
            if test $status -eq 0
                set stashed true
            else
                set -a error_log "$repo_name|Failed to stash uncommitted changes"
                set repos_with_errors (math $repos_with_errors + 1)
                continue
            end
        end

        # Get all local branches with upstream (and verify upstream exists on remote)
        set -l branches_with_upstream
        for branch in (git -C "$repo_path" for-each-ref --format='%(refname:short)' refs/heads/)
            set -l upstream (git -C "$repo_path" rev-parse --abbrev-ref "$branch@{upstream}" 2>/dev/null)
            if test -n "$upstream"
                # Check if upstream branch still exists on remote
                git -C "$repo_path" rev-parse --verify "$upstream" >/dev/null 2>&1
                if test $status -eq 0
                    set -a branches_with_upstream "$branch"
                end
            end
        end

        if test (count $branches_with_upstream) -eq 0
            # Restore stash if needed
            if test "$stashed" = true
                set -l stash_count (git -C "$repo_path" stash list | wc -l | string trim)
                if test "$stash_count" -gt 0
                    git -C "$repo_path" stash pop >/dev/null 2>&1
                end
            end
            continue
        end

        # Track changes for this repo
        set -l repo_had_changes false
        set -l repo_commits_pulled 0
        set -l repo_errors
        set -l repo_conflicts

        # Pull each branch
        for branch in $branches_with_upstream
            # Checkout branch quietly
            git -C "$repo_path" checkout "$branch" >/dev/null 2>&1
            if test $status -ne 0
                set -a repo_errors "Failed to checkout $branch"
                continue
            end

            # Count commits ahead/behind upstream
            set -l upstream (git -C "$repo_path" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
            set -l commits_behind 0
            set -l commits_ahead 0
            if test -n "$upstream"
                set commits_behind (git -C "$repo_path" rev-list --count 'HEAD..@{upstream}' 2>/dev/null; or echo 0)
                set commits_ahead (git -C "$repo_path" rev-list --count '@{upstream}..HEAD' 2>/dev/null; or echo 0)
            end

            # Skip WIP branches that have local commits on top of their upstream.
            # These are personal draft branches (e.g. tracking origin/main with local work).
            # They can't be fast-forwarded and that's expected — not an error.
            if test "$commits_ahead" -gt 0
                continue
            end

            # Pull with fast-forward only
            set -l pull_output (git -C "$repo_path" pull --ff-only 2>&1)
            set -l pull_status $status

            if test $pull_status -eq 0
                if test $commits_behind -gt 0
                    set repo_had_changes true
                    set repo_commits_pulled (math $repo_commits_pulled + $commits_behind)
                end
            else
                # Check if it's a non-fast-forward issue or deleted upstream
                if string match -qi "*not possible to fast-forward*" "$pull_output"
                    continue
                else if string match -qi "*diverged*" "$pull_output"
                    continue
                else if string match -q "*couldn't find remote ref*" "$pull_output"
                    continue
                else if string match -q "*no such ref was fetched*" "$pull_output"
                    continue
                else
                    set -a repo_errors "Failed to pull $branch"
                end
            end
        end

        # Return to original branch
        git -C "$repo_path" checkout "$original_branch" >/dev/null 2>&1

        # Restore stash if needed
        if test "$stashed" = true
            set -l stash_count (git -C "$repo_path" stash list | wc -l | string trim)
            if test "$stash_count" -gt 0
                set -l stash_output (git -C "$repo_path" stash pop 2>&1)
                set -l stash_status $status
                if test $stash_status -ne 0
                    if not string match -q "*No stash entries found*" "$stash_output"
                        set -a repo_errors "Stash pop failed (conflicts?)"
                    end
                end
            end
        end

        # Update activity cache for this repo
        set -a new_activity_cache "$repo_path|$repo_commits_pulled|"(date +%s)

        # Log results if repo had changes or errors
        if test "$repo_had_changes" = true
            set repos_with_changes (math $repos_with_changes + 1)
            set total_commits_pulled (math $total_commits_pulled + $repo_commits_pulled)

            set -l info_parts
            if test $repo_commits_pulled -gt 0
                set -a info_parts "$repo_commits_pulled commits"
            end
            if test (count $repo_conflicts) -gt 0
                set -a info_parts (string join ", " $repo_conflicts)
            end

            set -l info_str (string join ", " $info_parts)
            set -a change_log "$repo_name|$info_str"
        end

        if test (count $repo_errors) -gt 0
            set repos_with_errors (math $repos_with_errors + 1)
            set -l error_str (string join "; " $repo_errors)
            set -a error_log "$repo_name|$error_str"
        end
    end

    # Clear the progress line and move to a new line before results
    printf "\r\033[2K"

    # Display changes
    if test (count $change_log) -gt 0
        gum style --foreground $p_green --bold "✅ updated repos:"
        for item in $change_log
            set -l parts (string split "|" -- "$item")
            set -l name $parts[1]
            set -l info $parts[2]
            echo "  "(gum style --foreground $p_green2 "$name")" "(gum style --foreground $p_muted "($info)")
        end
        echo
    end

    # Display errors
    if test (count $error_log) -gt 0
        gum style --foreground $p_red --bold "⚠️  errors:"
        for item in $error_log
            set -l parts (string split "|" -- "$item")
            set -l name $parts[1]
            set -l error $parts[2]
            echo "  "(gum style --foreground $p_red2 "$name")" "(gum style --foreground $p_muted "$error")
        end
        echo
    end

    # Summary
    if test $repos_with_changes -eq 0 -a $repos_with_errors -eq 0
        gum style --foreground $p_green "✨ All $total_repos repos up to date"
    else
        set -l summary_parts
        if test $repos_with_changes -gt 0
            set -a summary_parts (gum style --foreground $p_green "$repos_with_changes updated")
        end
        if test $total_commits_pulled -gt 0
            set -a summary_parts (gum style --foreground $p_muted "($total_commits_pulled commits)")
        end
        if test $repos_with_errors -gt 0
            set -a summary_parts (gum style --foreground $p_red "$repos_with_errors errors")
        end
        
        set -l summary_line (gum style --foreground $p_muted "$total_repos repos checked: ")
        for part in $summary_parts
            set summary_line "$summary_line$part "
        end
        echo $summary_line
    end

    echo

    # Save activity cache for next run
    printf "%s\n" $new_activity_cache > "$cache_file"

    # Cleanup helper function
    functions -e __pullall_activity_score

    if test $repos_with_errors -gt 0
        return 1
    end
end
