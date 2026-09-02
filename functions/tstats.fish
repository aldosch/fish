# tstats - Typing Stats CPU monitoring: findings + management
#
# Companion to the background monitor (com.aldo.typing-stats-monitor /
# ~/.config/scripts/typing-stats-monitor/monitor.sh) which samples Typing
# Stats' CPU, captures spike stack traces, and periodically runs a headless
# opencode analysis (plan mode) whose findings light up the MOTD
# (conf.d/typing-stats-motd.fish).
#
# Usage:
#   tstats             resume the analysis session in the opencode TUI
#   tstats status      show findings detail (verdict, headline, report preview)
#   tstats dismiss     snooze the MOTD for today
#   tstats analyze     re-run the headless analysis now
#   tstats reset       clear findings and re-arm the auto-analysis (next 24h)
#   tstats log         tail the CPU sample log

function tstats --argument-names subcmd
    _aldo_dracula_apply_palette

    set -l state_dir ~/.local/state/typing-stats
    set -l findings_file $state_dir/findings.json
    set -l report_file $state_dir/report.md
    set -l done_flag $state_dir/analysis-done
    set -l monitor_script ~/.config/scripts/typing-stats-monitor/monitor.sh
    set -l cpu_log ~/Library/Logs/typing-stats-cpu.log

    switch "$subcmd"
        case ""
            # Resume the analysis session in the TUI
            if not test -f "$findings_file"
                gum style --foreground $p_muted "  no analysis findings yet. run: tstats analyze"
                return
            end

            set -l session_id (jq -r '.session_id // ""' "$findings_file" 2>/dev/null)
            if test -n "$session_id" -a "$session_id" != "null"
                opencode -s "$session_id" ~/repos/typing-stats
            else
                gum style --foreground $p_yellow "  analysis session not found (failed run?) — re-running: tstats analyze"
                tstats analyze
            end

        case status
            if not test -f "$findings_file"
                gum style --foreground $p_muted "  no findings yet. the monitor auto-analyzes after 24h of data or 10 spikes."
                gum style --foreground $p_muted "  monitor state:"
                bash "$monitor_script" --status 2>/dev/null | gum style --foreground $p_muted
                return
            end

            set -l verdict (jq -r '.verdict // "unknown"' "$findings_file" 2>/dev/null)
            set -l headline (jq -r '.headline // ""' "$findings_file" 2>/dev/null)
            set -l spikes (jq -r '.spike_count // 0' "$findings_file" 2>/dev/null)
            set -l analyzed (jq -r '.analyzed_at // "?"' "$findings_file" 2>/dev/null)
            set -l session_id (jq -r '.session_id // ""' "$findings_file" 2>/dev/null)

            set -l verdict_color $p_muted
            switch "$verdict"
                case benign
                    set verdict_color $p_green
                case action_needed error
                    set verdict_color $p_yellow
            end

            echo
            gum join --horizontal \
                (gum style --bold --foreground $p_purple "typing stats cpu") \
                (gum style --foreground $p_muted " · $spikes spike(s) · analyzed $analyzed")
            gum join --horizontal \
                (gum style --foreground $verdict_color --bold "  $verdict") \
                (gum style --foreground $p_fg "  $headline")
            echo

            if test -f "$report_file"
                gum style --foreground $p_muted "── report (first 25 lines) ──────────────────────────"
                head -25 "$report_file" | gum style --foreground $p_fg
                set -l total (wc -l < "$report_file" | string trim)
                if test "$total" -gt 25
                    gum style --foreground $p_muted "  … $(math $total - 25) more lines — full report: $report_file"
                end
            end

            echo
            gum join --horizontal \
                (gum style --foreground $p_muted "  → resume session: ") \
                (gum style --foreground $p_cyan --bold "tstats") \
                (gum style --foreground $p_muted "   · re-analyze: ") \
                (gum style --foreground $p_cyan "tstats analyze")
            if test -n "$session_id" -a "$session_id" != "null"
                gum style --foreground $p_muted "    session: $session_id"
            end
            echo

        case dismiss
            if test -f "$findings_file"
                set -l today (date +%Y-%m-%d)
                jq --arg today "$today" '.last_shown = $today' "$findings_file" >"$findings_file.tmp" 2>/dev/null
                and mv "$findings_file.tmp" "$findings_file"
                gum style --foreground $p_muted "  dismissed for today"
            else
                gum style --foreground $p_muted "  nothing to dismiss"
            end

        case analyze
            gum style --foreground $p_muted "  running headless opencode analysis (plan mode) — this takes a minute or two..."
            bash "$monitor_script" --analyze
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " done — run: ") \
                (gum style --foreground $p_cyan --bold "tstats status")

        case reset
            rm -f "$findings_file" "$report_file" "$done_flag" "$state_dir/analysis-raw.jsonl"
            gum style --foreground $p_muted "  findings cleared — monitor will auto-analyze again after 24h (or 10 spikes)"
            gum join --horizontal \
                (gum style --foreground $p_muted "  → impatient? run: ") \
                (gum style --foreground $p_cyan --bold "tstats analyze")

        case log
            if test -f "$cpu_log"
                tail -30 "$cpu_log"
            else
                gum style --foreground $p_muted "  no cpu log yet"
            end

        case '*'
            echo "usage: tstats [status|dismiss|analyze|reset|log]"
            return 1
    end
end
