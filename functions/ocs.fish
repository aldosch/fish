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

    # ── Ensure the expression index exists (additive, non-destructive) ──
    # Without this the correlated subquery in ocs-list.sql scans all part
    # rows and takes ~3s. With the index it uses the index and takes ~0.1s.
    # IF NOT EXISTS makes this a no-op on subsequent runs.
    sqlite3 "$db" \
        "CREATE INDEX IF NOT EXISTS part_text_expr_idx ON part(session_id, json_extract(data, '\$.text')) WHERE json_extract(data, '\$.type') = 'text' AND json_extract(data, '\$.text') IS NOT NULL AND json_extract(data, '\$.text') != '';" 2>/dev/null &

    # ── Two-layer cache ──────────────────────────────────────────────────
    # Layer 1 (raw):   raw SQL TSV — mode-independent, invalidated by DB mtime
    # Layer 2 (render): colored TSV ready for fzf — mode-specific, invalidated
    #                   by raw file mtime. Background-refreshed if >30s old.
    set -l cache_dir "$HOME/.cache/ocs"
    set -l raw_cache "$cache_dir/sessions.raw.tsv"
    set -l mode (defaults read -g AppleInterfaceStyle 2>/dev/null)
    if test "$mode" = Dark
        set mode "dark"
    else
        set mode "light"
    end
    set -l render_cache "$cache_dir/sessions.$mode.tsv"

    mkdir -p "$cache_dir"

    set -l db_mtime (stat -f %m "$db" 2>/dev/null; or echo 0)
    set -l raw_mtime (stat -f %m "$raw_cache" 2>/dev/null; or echo 0)
    set -l now_epoch (date +%s)
    set -l today_date (date +%Y-%m-%d)

    # Layer 1: regenerate raw cache if DB is newer (or cache doesn't exist)
    if test "$raw_mtime" -lt "$db_mtime"
        sqlite3 -batch "$db" < "$sql_dir/ocs-list.sql" > "$raw_cache" 2>/dev/null
        set raw_mtime (stat -f %m "$raw_cache" 2>/dev/null; or echo 0)
    end

    # Layer 2: render (color + relative dates) from raw cache
    set -l render_mtime (stat -f %m "$render_cache" 2>/dev/null; or echo 0)
    set -l render_age (math $now_epoch - $render_mtime)

    # Colors for the displayed columns (title, date, path)
    set -l c_date (set_color $p_muted)
    set -l c_path (set_color $p_cyan)
    set -l c_title (set_color $p_fg)
    set -l c_reset (set_color normal)

    # fzf color scheme built from the adaptive palette — ensures the selected
    # line (bg+) and match highlights (hl/hl+) have good contrast in both
    # light and dark mode. Without this, fzf uses the terminal default which
    # makes colored text unreadable on the selection background in light mode.
    set -l fzf_colors \
        "bg+:$p_element,fg+:$p_fg,hl:$p_purple,hl+:$p_purple,"\
"pointer:$p_purple,prompt:$p_cyan,header:$p_muted,"\
"info:$p_muted,border:$p_element,gutter:$p_bg"

    # Render: raw TSV → colored fzf-ready TSV via awk script
    # Render in foreground if render cache is stale (missing, or raw was just regenerated)
    if test "$render_mtime" -lt "$raw_mtime"
        awk -F'\t' -v OFS='\t' \
            -v home="$HOME" -v now="$now_epoch" -v today="$today_date" \
            -v dc="$c_date" -v cp="$c_path" -v ct="$c_title" -v cr="$c_reset" \
            -f "$sql_dir/ocs-render.awk" \
            < "$raw_cache" > "$render_cache"
        set render_mtime (stat -f %m "$render_cache" 2>/dev/null; or echo 0)
        set render_age (math $now_epoch - $render_mtime)
    end

    # Background refresh: if render is >30s old but raw is still current (DB
    # unchanged), re-render relative dates from raw. Non-blocking, atomic mv.
    # No lock file — worst case is a redundant 0.3s awk if two launches race.
    if test "$render_age" -gt 30 -a "$raw_mtime" -ge "$db_mtime"
        set -l tmp_render "$render_cache.tmp"
        fish -c "awk -F'\t' -v OFS='\t' \
                    -v home='$HOME' -v now='$now_epoch' -v today='$today_date' \
                    -v dc='$c_date' -v cp='$c_path' -v ct='$c_title' -v cr='$c_reset' \
                    -f '$sql_dir/ocs-render.awk' \
                    < '$raw_cache' > '$tmp_render' \
                 && mv '$tmp_render' '$render_cache'" >/dev/null 2>&1 &
    end

    # Pre-seed fzf query from args
    set -l fzf_query ""
    if test (count $argv) -gt 0
        set fzf_query (string join " " -- $argv)
    end

    # Set BAT_THEME for the preview subshell so syntax highlighting matches
    # the current mode. Without this, bat defaults to a dark theme which is
    # washed out in light mode.
    set -lx BAT_THEME (test "$mode" = dark; and echo Dracula; or echo "Catppuccin Latte")

    # Pipe the rendered cache directly to fzf
    set -l selected (cat "$render_cache" | \
        fzf \
            --ansi \
            --color="$fzf_colors" \
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
