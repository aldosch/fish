function git-status-pretty
    # ──────────────────────────────────────────────────────
    # USAGE: git-status-pretty
    # FLOW:  1. Checks for gum
    #        2. Runs git status --short and parses output
    #        3. Groups by type: staged, modified, deleted, etc.
    #        4. Pretty-prints with colors, icons, and alignment
    # ──────────────────────────────────────────────────────

    if not type -q gum
        echo "Error: gum is not installed. add 'gum' to nix/modules/apps.nix then run nixx l"
        return 1
    end

    # Re-detect palette in case mode changed since shell start
    _aldo_dracula_apply_palette

    set -l git_status (git status --short)
    if test -z "$git_status"
        gum style --foreground $p_green "nice"
        return 0
    end

    set -l staged
    set -l modified
    set -l deleted
    set -l untracked
    set -l conflicted
    set -l staged_files

    for line in $git_status
        set -l index_status (string sub -s 1 -l 1 -- "$line")
        set -l worktree_status (string sub -s 2 -l 1 -- "$line")
        set -l file_path (string trim (string sub -s 4 -- "$line"))

        # --- Staged Files (first column) ---
        switch $index_status
            case M A D R C
                set -a staged $file_path
                set -a staged_files $file_path
        end

        # --- Unstaged Files (second column) ---
        switch $worktree_status
            case M
                set -a modified $file_path
            case D
                set -a deleted $file_path
        end

        # --- Special Cases (two-character codes) ---
        if string match -q '??*' -- "$line"
            # Only add to untracked if not already staged
            if not contains $file_path $staged_files
                set -a untracked $file_path
            end
        end
        if string match -q 'UU*' -- "$line"
            set -a conflicted $file_path
        end
    end

    # Helper to print a list of files with alignment
    function _print_aligned
        set -l color $argv[-1]
        set -l files $argv[1..-2]

        if not set -q files[1]
            return
        end

        set -l max_length (string length -- $files | string replace ' ' \n | sort -nr | head -n1)

        for f in $files
            set -l padded_file (string pad --right -w $max_length -- "  $f")
            gum style --foreground $color $padded_file
        end
    end

    # --- Print Sections ---
    if test -n "$conflicted"
        gum style --foreground $p_red --bold "💥 conflicted:"
        _print_aligned $conflicted $p_red2
        echo
    end

    if test -n "$staged"
        gum style --foreground $p_green --bold "📦 staged:"
        _print_aligned $staged $p_green2
        echo
    end

    if test -n "$modified"
        gum style --foreground $p_orange --bold "📝 modified:"
        _print_aligned $modified $p_orange2
        echo
    end

    if test -n "$deleted"
        gum style --foreground $p_pink --bold "🗑 deleted:"
        _print_aligned $deleted $p_pink2
        echo
    end

    if test -n "$untracked"
        gum style --foreground $p_cyan --bold "✨ untracked:"
        _print_aligned $untracked $p_cyan2
        echo
    end

    functions -e _print_aligned
end
