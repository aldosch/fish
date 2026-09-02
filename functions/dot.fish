# dot - dotfiles health status and management
#
# Usage:
#   dot             show current notices (alias for `dot status`)
#   dot status      show current notices with details
#   dot refresh     run health check now (headless, updates notices)
#   dot dismiss     snooze all notices for today (MOTD won't show again today)
#   dot log         tail the health check log
#   dot fix         alias for dotfix (interactive remediation)

function dot --argument-names subcmd
    _aldo_dracula_apply_palette

    set -l notices_file ~/.local/state/dotfiles/notices.json

    switch "$subcmd"
        case "" status
            if not test -f "$notices_file"
                gum style --foreground $p_muted "  no health state yet. run: dot refresh"
                return
            end

            set -l data (cat "$notices_file" 2>/dev/null)
            set -l count (echo $data | jq -r '.count // 0' 2>/dev/null)
            set -l message (echo $data | jq -r '.message // ""' 2>/dev/null)
            set -l auto_fixed (echo $data | jq -r '.auto_fixed_count // 0' 2>/dev/null)
            set -l generated (echo $data | jq -r '.generated_at // "?"' 2>/dev/null)

            echo
            if test "$count" -eq 0 2>/dev/null
                gum join --horizontal \
                    (gum style --foreground $p_green "  ✓") \
                    (gum style --foreground $p_fg " all good, no drift") \
                    (gum style --foreground $p_muted " · checked $generated")
                echo
                return
            end

            # Header
            set -l header_parts
            set header_parts $header_parts (gum style --bold --foreground $p_purple "dotfiles health")
            set header_parts $header_parts (gum style --foreground $p_muted " · $count notice(s)")
            if test "$auto_fixed" -gt 0 2>/dev/null
                set header_parts $header_parts (gum style --foreground $p_green " ($auto_fixed auto-fixed)")
            end
            gum join --horizontal $header_parts
            echo

            # Items
            set -l items (echo $data | jq -r '.items[] | "\(.surface)\t\(.kind)\t\(.name)\t\(.summary)\t\(.auto_fixed)"' 2>/dev/null)
            for item in $items
                set -l parts (string split \t -- $item)
                set -l surface $parts[1]
                set -l kind $parts[2]
                set -l name $parts[3]
                set -l summary $parts[4]
                set -l fixed $parts[5]

                set -l icon
                set -l color
                if test "$fixed" = true
                    set icon "✓"
                    set color $p_green
                else if test "$kind" = modified
                    set icon "▸"
                    set color $p_orange
                else if test "$kind" = missing
                    set icon "▸"
                    set color $p_yellow
                else if test "$kind" = extra
                    set icon "▸"
                    set color $p_orange
                else
                    set icon "▸"
                    set color $p_yellow
                end

                gum join --horizontal \
                    (gum style --foreground $color "  $icon") \
                    (gum style --foreground $p_fg " $name") \
                    (gum style --foreground $p_muted "  $surface")
                gum style --foreground $p_muted "    $summary"
            end

            # Message + action
            echo
            if test -n "$message"
                gum join --horizontal \
                    (gum style --foreground $p_muted "  · ") \
                    (gum style --foreground $p_fg "$message")
            end
            gum join --horizontal \
                (gum style --foreground $p_muted "  → run: ") \
                (gum style --foreground $p_cyan --bold "dotfix")
            echo

        case refresh
            gum style --foreground $p_muted "  running health check..."
            dotfiles-health

        case dismiss
            if test -f "$notices_file"
                set -l today (date +%Y-%m-%d)
                jq --arg today "$today" '.last_shown = $today' "$notices_file" >"$notices_file.tmp" 2>/dev/null
                and mv "$notices_file.tmp" "$notices_file"
                gum style --foreground $p_muted "  dismissed for today"
            else
                gum style --foreground $p_muted "  nothing to dismiss"
            end

        case log
            set -l log_file ~/Library/Logs/dotfiles-health.log
            if test -f "$log_file"
                tail -20 "$log_file"
            else
                gum style --foreground $p_muted "  no log yet"
            end

        case fix
            dotfix

        case heal
            set -l backlog ~/.local/state/dotfiles/heal-backlog.md
            if not test -f "$backlog"; or not test -s "$backlog"
                gum style --foreground $p_muted "  no documented heal issues"
                return
            end
            if type -q bat
                bat --style=plain --color=always --paging=never "$backlog" 2>/dev/null
                or cat "$backlog"
            else
                cat "$backlog"
            end
            echo
            gum style --foreground $p_muted "  → edit with: nvim $backlog"

        case '*'
            echo "usage: dot [status|refresh|dismiss|log|fix|heal]"
            return 1
    end
end
