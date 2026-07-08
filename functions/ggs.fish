function ggs
    # ──────────────────────────────────────────────────────
    # USAGE: ggs [directory]
    # Global Git Status - shows state of all repos in a directory
    # Default directory: ~/dev
    # ──────────────────────────────────────────────────────

    if not type -q gum
        echo "Error: gum is not installed. Install with 'brew install gum'"
        return 1
    end

    _aldo_dracula_apply_palette

    set -l repos_dir $argv[1]
    if test -z "$repos_dir"
        set repos_dir "$HOME/dev"
    end

    if not test -d "$repos_dir"
        gum style --foreground $p_red "Error: Directory $repos_dir does not exist"
        return 1
    end

    # Arrays for categorizing repos
    set -l clean_repos
    set -l dirty_repos
    set -l unpushed_repos
    set -l non_main_repos
    set -l not_git_repos

    # Iterate through directories
    for dir in $repos_dir/*/
        set -l dir (string trim --right --chars='/' -- "$dir")
        set -l repo_name (basename "$dir")

        # Skip if not a directory
        if not test -d "$dir"
            continue
        end

        # Skip if not a git repo
        if not test -d "$dir/.git"
            set -a not_git_repos $repo_name
            continue
        end

        # Get repo info
        set -l branch (git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
        set -l status_output (git -C "$dir" status --porcelain 2>/dev/null)
        
        # Check for unpushed commits
        set -l unpushed_count 0
        set -l upstream (git -C "$dir" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
        if test -n "$upstream"
            set unpushed_count (git -C "$dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null; or echo 0)
        else
            # No upstream, check if there are any commits at all
            set -l has_commits (git -C "$dir" rev-parse HEAD 2>/dev/null)
            if test -n "$has_commits"
                set unpushed_count "?"
            end
        end

        # Categorize
        set -l is_dirty false
        set -l is_unpushed false
        set -l is_non_main false

        if test -n "$status_output"
            set is_dirty true
        end

        if test "$unpushed_count" != "0"
            set is_unpushed true
        end

        if test "$branch" != "main"
            set is_non_main true
        end

        # Build status string
        if test "$is_dirty" = true -o "$is_unpushed" = true -o "$is_non_main" = true
            set -l info_parts

            if test "$is_non_main" = true
                set -a info_parts "on $branch"
            end

            if test "$is_dirty" = true
                set -l changed_count (echo "$status_output" | wc -l | string trim)
                set -a info_parts "$changed_count changed"
            end

            if test "$is_unpushed" = true
                if test "$unpushed_count" = "?"
                    set -a info_parts "no upstream"
                else
                    set -a info_parts "$unpushed_count unpushed"
                end
            end

            set -l info_str (string join ", " $info_parts)
            
            if test "$is_dirty" = true
                set -a dirty_repos "$repo_name|$info_str"
            else if test "$is_unpushed" = true
                set -a unpushed_repos "$repo_name|$info_str"
            else
                set -a non_main_repos "$repo_name|$info_str"
            end
        else
            set -a clean_repos $repo_name
        end
    end

    # Print header
    gum style --bold --foreground $p_purple "Global Git Status: $repos_dir"
    echo

    # Print dirty repos (highest priority)
    if test (count $dirty_repos) -gt 0
        gum style --foreground $p_orange --bold "uncommitted changes:"
        for item in $dirty_repos
            set -l parts (string split "|" -- "$item")
            set -l name $parts[1]
            set -l info $parts[2]
            echo "  "(gum style --foreground $p_orange2 "$name")" "(gum style --foreground $p_muted "($info)")
        end
        echo
    end

    # Print unpushed repos
    if test (count $unpushed_repos) -gt 0
        gum style --foreground $p_yellow --bold "unpushed commits:"
        for item in $unpushed_repos
            set -l parts (string split "|" -- "$item")
            set -l name $parts[1]
            set -l info $parts[2]
            echo "  "(gum style --foreground $p_yellow2 "$name")" "(gum style --foreground $p_muted "($info)")
        end
        echo
    end

    # Print non-main branches (clean but on different branch)
    if test (count $non_main_repos) -gt 0
        gum style --foreground $p_purple --bold "on other branches:"
        for item in $non_main_repos
            set -l parts (string split "|" -- "$item")
            set -l name $parts[1]
            set -l info $parts[2]
            echo "  "(gum style --foreground $p_purple2 "$name")" "(gum style --foreground $p_muted "($info)")
        end
        echo
    end

    # Print summary
    set -l total (math (count $clean_repos) + (count $dirty_repos) + (count $unpushed_repos) + (count $non_main_repos))
    set -l needs_attention (math (count $dirty_repos) + (count $unpushed_repos))

    if test $needs_attention -eq 0
        gum style --foreground $p_green "all $total repos clean"
    else
        gum style --foreground $p_muted "$total repos: "(gum style --foreground $p_green (count $clean_repos)" clean")", "(gum style --foreground $p_orange "$needs_attention need attention")
    end
end
