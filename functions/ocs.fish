function ocs --description 'Fuzzy-find opencode sessions globally by transcript content'
    # Resolve the opencode database
    set -l db (opencode db path 2>/dev/null)
    if test -z "$db"
        set db "$HOME/.local/share/opencode/opencode.db"
    end
    if not test -f "$db"
        gum style --foreground $p_red "Error: opencode database not found at $db"
        return 1
    end

    set -l sql_dir "$HOME/.config/fish/sql"

    # Colors for the left column (date, path, title)
    set -l c_date (set_color $p_muted)
    set -l c_path (set_color $p_cyan)
    set -l c_title (set_color $p_fg)
    set -l c_reset (set_color normal)

    # Pre-seed fzf query from args
    set -l fzf_query ""
    if test (count $argv) -gt 0
        set fzf_query (string join " " -- $argv)
    end

    # Pipe session list through awk for date formatting, ~ substitution, ANSI coloring, and padding.
    # TSV in:  id(1) \t epoch(2) \t path(3) \t title(4) \t content(5)
    # TSV out: id(1) \t title(2) \t date(3) \t path(4) \t content(5)
    # date: relative ("5mins", "2hrs", "just now") if today, YYYY-MM-DD if older.
    # title padded to 55 chars (truncated with … if longer), path to 30 chars,
    # so columns align. BSD awk lacks systime()/strftime(), epoch/today passed from fish.
    set -l now_epoch (date +%s)
    set -l today_date (date +%Y-%m-%d)
    set -l selected (sqlite3 -batch "$db" < "$sql_dir/ocs-list.sql" 2>/dev/null | \
        awk -F'\t' -v OFS='\t' \
            -v home="$HOME" \
            -v now="$now_epoch" \
            -v today="$today_date" \
            -v dc="$c_date" \
            -v cp="$c_path" \
            -v ct="$c_title" \
            -v cr="$c_reset" \
            '{ gsub(home, "~", $3);
               # BSD awk has no strftime — use date -r for epoch formatting
               cmd = "date -r " $2 " +%Y-%m-%d";
               cmd | getline sdate;
               close(cmd);
               if (today == sdate) {
                   diff = now - $2;
                   if (diff < 60) label = "just now";
                   else if (diff < 3600) label = int(diff/60) "mins";
                   else label = int(diff/3600) "hrs";
               } else {
                   label = sdate;
               }
               d = sprintf("%-12s", label);
               t = $4;
               if (length(t) > 55) t = substr(t, 1, 54) "\xe2\x80\xa6";
               t = sprintf("%-55s", t);
               p = $3;
               if (length(p) > 30) p = substr(p, 1, 29) "\xe2\x80\xa6";
               p = sprintf("%-30s", p);
               printf "%s\t%s%s%s\t%s%s%s\t%s%s%s\t%s\n", \
                      $1, ct, t, cr, dc, d, cr, cp, p, cr, $5 }' | \
        fzf \
            --ansi \
            --delimiter='\t' \
            --with-nth=2,3,4 \
            --layout=reverse \
            --height=90% \
            --prompt='opencode sessions❯ ' \
            --preview-window='right:60%:wrap' \
            --preview="sed 's|:sid|{1}|g' $sql_dir/ocs-preview.sql | sqlite3 -batch $db | bat --plain --language=md --color=always" \
            --bind='ctrl-y:execute-silent(echo -n {1} | pbcopy)' \
            --query="$fzf_query")

    if test -z "$selected"
        return 0
    end

    # Strip ANSI codes from the selected line and parse fields
    # Fields: id(1), title(2), date(3), path(4), content(5)
    set -l esc (printf '\033')
    set -l clean (string replace -ra "$esc\[[0-9;]*m" '' -- $selected)
    set -l fields (string split \t -- $clean)
    set -l sid $fields[1]
    set -l title (string trim -- $fields[2])
    set -l worktree (string replace -r '^~' "$HOME" -- (string trim -- $fields[4]))

    # Action menu
    set -l action (gum choose \
        --cursor.foreground $p_purple \
        --selected.foreground $p_purple \
        --header "    $title" \
        --header.foreground $p_muted \
        "Copy session id" \
        "Copy transcript (text only)" \
        "Copy full transcript (with tool calls)" \
        "Resume session in $worktree")

    if test -z "$action"
        return 0
    end

    switch "$action"
        case "Copy session id"
            echo -n "$sid" | pbcopy
            gum style --foreground $p_green "✓ Copied $sid to clipboard"
        case "Copy transcript*"
            sed "s|:sid|$sid|g" "$sql_dir/ocs-preview.sql" | sqlite3 -batch "$db" | pbcopy
            gum style --foreground $p_green "✓ Transcript copied to clipboard"
        case "Copy full*"
            sed "s|:sid|$sid|g" "$sql_dir/ocs-preview-full.sql" | sqlite3 -batch "$db" | pbcopy
            gum style --foreground $p_green "✓ Full transcript copied to clipboard"
        case "Resume*"
            if not test -d "$worktree"
                gum style --foreground $p_red "Error: directory $worktree does not exist"
                return 1
            end
            cd "$worktree" && opencode -s "$sid"
    end
end
