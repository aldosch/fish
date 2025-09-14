function git-status-pretty
    # ──────────────────────────────────────────────────────
    # USAGE: git-status-pretty
    # FLOW:  1. Checks for gum
    #        2. Runs git status --short and parses output
    #        3. Groups by type: staged, modified, deleted, etc.
    #        4. Pretty-prints with colors, icons, and alignment
    # ──────────────────────────────────────────────────────

    if not type -q gum
        echo "Error: gum is not installed. Install with 'brew install gum'"
        return 1
    end

    set -l git_status (git status --short)
    if test -z "$git_status"
        gum style --foreground 46 "✅ Working tree clean"
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
        gum style --foreground 196 --bold "💥 conflicted:"
        _print_aligned $conflicted 203
        echo
    end

    if test -n "$staged"
        gum style --foreground 40 --bold "📦 staged:"
        _print_aligned $staged 48
        echo
    end

    if test -n "$modified"
        gum style --foreground 220 --bold "📝 modified:"
        _print_aligned $modified 226
        echo
    end

    if test -n "$deleted"
        gum style --foreground 203 --bold "🗑 deleted:"
        _print_aligned $deleted 210
        echo
    end

    if test -n "$untracked"
        gum style --foreground 45 --bold "✨ untracked:"
        _print_aligned $untracked 51
        echo
    end
end
