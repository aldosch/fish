# _nixx_heal - self-heal errors using opencode in plan mode
#
# When nixx or a sub-command (scripts-restore, publish-dots, etc.) hits an
# error, this function runs opencode headlessly in plan mode to diagnose the
# root cause and suggest a fix. The user sees a concise TLDR (root cause +
# fix + diff) and chooses: apply, skip, or document for later.
#
# Pre-flight gates (all must pass, else silently skip):
#   - opencode is installed
#   - AI Gateway key is available (env or Keychain)
#   - interactive TTY (not backgrounded/piped)
#
# Apply flow: a second `opencode run --agent build --auto` invocation makes
# the actual edit. The build agent runs in ~/.config, reads AGENTS.md, and
# follows all repo conventions (including doc updates). The fix is committed
# locally with a `self-heal:` prefix (staging only the files the agent
# touched); nothing is pushed. A fish-side fallback commits newly-dirty
# files if the agent skipped the commit.
#
# Usage:
#   _nixx_heal <context> <error_text> [source_file1] [source_file2] ...
#
# Returns:
#   0 = fix applied (or skipped after apply)
#   1 = skipped / pre-flight failed / diagnosis failed
#   2 = documented for later

function _nixx_heal --description 'Self-heal an error using opencode in plan mode'
    if test (count $argv) -lt 2
        return 1
    end

    set -l context $argv[1]
    set -l error_text $argv[2]
    set -l source_files $argv[3..-1]

    # --- pre-flight gate ---
    if not type -q opencode
        return 1
    end

    set -l gw_key $AI_GATEWAY_API_KEY
    if test -z "$gw_key"
        set gw_key (secret-get AI_GATEWAY_API_KEY 2>/dev/null)
    end
    if test -z "$gw_key"
        return 1
    end

    if not test -t 0; or not test -t 1
        return 1
    end

    if not type -q gum
        return 1
    end

    _aldo_dracula_apply_palette

    # --- build prompt ---
    set -l file_list
    if test (count $source_files) -gt 0
        set file_list (string join ", " -- $source_files)
    else
        set file_list "(none provided; read files from the repo as needed)"
    end

    set -l prompt_file (mktemp)
    printf '%s\n' \
        "An error occurred during a nixx system update in this dotfiles repo (~/.config)." \
        "" \
        "Error context: $context" \
        "" \
        "Error output:" \
        "$error_text" \
        "" \
        "Relevant source files (read them from the repo): $file_list" \
        "" \
        "Read AGENTS.md for repo conventions." \
        "" \
        "Diagnose the root cause and suggest a fix. Output ONLY these three sections:" \
        "ROOT CAUSE: <one sentence>" \
        "FIX: <file:line> - <what to change and why>" \
        "DIFF: <unified diff>" \
        "" \
        "No preamble. No explanation beyond the three sections." >$prompt_file

    # --- run opencode headlessly in plan mode ---
    set -l stamp (date +%s)
    set -l heal_log /tmp/nixx-heal-$stamp.log
    set -l heal_exit /tmp/nixx-heal-$stamp.exit
    # opencode plan runs commonly take 60-120s+; 60s killed healthy diagnoses
    set -l heal_timeout 180

    # Read prompt as a single string (string collect preserves newlines)
    set -l prompt_text (cat $prompt_file | string collect)
    rm -f $prompt_file

    # Background run with watchdog (same pattern as __nixx_step)
    fish -c "opencode run --agent plan --format json --auto \$argv[1] >$heal_log 2>&1; echo \$status >$heal_exit" -- "$prompt_text" &
    set -l job_pid $last_pid

    # Watchdog: kill after timeout
    fish -c "
        sleep $heal_timeout
        if test -f $heal_exit
            exit 0
        end
        __nixx_kill_tree $job_pid TERM
        sleep 2
        __nixx_kill_tree $job_pid KILL
        test -f $heal_exit; or echo 124 >$heal_exit
    " &
    set -l watchdog_pid $last_pid

    gum spin --spinner dot \
        --spinner.foreground $p_purple \
        --title.foreground $p_muted \
        --title "  ⚡ self-heal, analyzing..." \
        -- fish -c "while not test -f $heal_exit; sleep 0.2; end"

    __nixx_kill_tree $watchdog_pid KILL 2>/dev/null
    kill $watchdog_pid 2>/dev/null
    wait $job_pid 2>/dev/null

    set -l rc 1
    if test -f $heal_exit
        set rc (string trim (cat $heal_exit))
    end
    rm -f $heal_exit

    if test $rc -ne 0
        if test -s $heal_log
            gum style --foreground $p_muted --faint "  ⚡ self-heal skipped (diagnosis failed or timed out) — log: $heal_log"
        else
            rm -f $heal_log
            gum style --foreground $p_muted --faint "  ⚡ self-heal skipped (diagnosis failed or timed out)"
        end
        return 1
    end

    # --- parse JSON output for text response ---
    set -l diagnosis (jq -r 'select(.type=="text") | .part.text // empty' $heal_log 2>/dev/null)
    rm -f $heal_log

    if test -z "$diagnosis"
        gum style --foreground $p_muted --faint "  ⚡ self-heal skipped (no response from agent)"
        return 1
    end

    # Join diagnosis lines into a single string for parsing
    set -l full_text (string join \n -- $diagnosis | string collect)

    # --- extract sections ---
    # Try to parse ROOT CAUSE, FIX, DIFF sections
    set -l root_cause ""
    set -l fix_text ""
    set -l diff_text ""

    # Split into lines for section parsing
    set -l lines (string split \n -- $full_text)
    set -l current_section ""
    set -l rc_lines
    set -l fix_lines
    set -l diff_lines

    for line in $lines
        # Detect section headers (case-insensitive, flexible format)
        set -l upper (string upper -- $line)
        if string match -q 'ROOT CAUSE*' -- $upper
            set current_section rc
            # Capture inline text after the header if any
            set -l inline (string replace -ri '^ROOT CAUSE:?\s*' '' -- $line 2>/dev/null)
            if test -n "$inline" -a "$inline" != "$line"
                set rc_lines $rc_lines $inline
            end
            continue
        else if string match -q 'FIX*' -- $upper; and not string match -q 'FIXED*' -- $upper
            set current_section fix
            set -l inline (string replace -ri '^FIX:?\s*' '' -- $line 2>/dev/null)
            if test -n "$inline" -a "$inline" != "$line"
                set fix_lines $fix_lines $inline
            end
            continue
        else if string match -q 'DIFF*' -- $upper
            set current_section diff
            continue
        end

        switch $current_section
            case rc
                set rc_lines $rc_lines $line
            case fix
                set fix_lines $fix_lines $line
            case diff
                # Skip markdown code fence lines
                if test "$line" = "```diff"; or test "$line" = "```"
                    continue
                end
                set diff_lines $diff_lines $line
        end
    end

    set root_cause (string join \n -- $rc_lines | string trim | string collect)
    set fix_text (string join \n -- $fix_lines | string trim | string collect)
    set diff_text (string join \n -- $diff_lines | string trim | string collect)

    # Fallback: if sections weren't found, show raw text
    set -l parsed_ok 1
    if test -z "$root_cause" -a -z "$fix_text" -a -z "$diff_text"
        set parsed_ok 0
        set root_cause $full_text
    end

    # --- present TLDR ---
    echo
    gum style --bold --foreground $p_purple "  ⚡ self-heal · $context"
    echo

    if test -n "$root_cause"
        gum join --horizontal \
            (gum style --foreground $p_orange "  ▸ root cause:") \
            (gum style --foreground $p_fg " $root_cause")
    end

    if test -n "$fix_text"
        echo
        gum join --horizontal \
            (gum style --foreground $p_cyan "  ▸ fix:") \
            (gum style --foreground $p_fg " $fix_text")
    end

    if test -n "$diff_text" -a "$parsed_ok" -eq 1
        echo
        set -l diff_file (mktemp)
        printf '%s\n' -- $diff_text >$diff_file
        if type -q bat
            bat --style=plain --color=always --language=diff --paging=never $diff_file 2>/dev/null
            or cat $diff_file
        else
            cat $diff_file
        end
        rm -f $diff_file
    end

    echo

    # --- approval ---
    set -l choices "Apply fix" "Skip" "Document for later"
    if test "$parsed_ok" -eq 0
        set choices "Skip" "Document for later"
    end

    set -l choice (gum choose \
        --cursor.foreground $p_purple \
        --selected.foreground $p_purple \
        --header "    What should happen?" \
        --header.foreground $p_muted \
        $choices)

    switch "$choice"
        case "Apply*"
            # --- apply via second opencode build invocation ---
            # The build agent is asked to commit its own edit (staging ONLY
            # the files it touched, message prefixed "self-heal:", no push).
            # A post-run check verifies the commit and falls back to a
            # fish-side commit of newly-dirty files if the agent skipped it.
            set -l repo ~/.config
            set -l head_before (git -C $repo rev-parse HEAD 2>/dev/null)
            set -l dirty_before (git -C $repo status --porcelain 2>/dev/null | string cut -c4- | sort)

            set -l apply_prompt "Fix this issue in the dotfiles repo ($repo): $root_cause. The fix: $fix_text. Read AGENTS.md for conventions. Make the edit, update docs if needed, then verify with any relevant lint/build commands. When the edit is done, commit it: stage ONLY the files you modified (git add <specific files>, never git add . or git add -A; the repo may contain unrelated dirty files) and commit with the message 'self-heal: <one line summary>'. Do not push."

            set -l apply_stamp (date +%s)
            set -l apply_log /tmp/nixx-heal-apply-$apply_stamp.log
            set -l apply_exit /tmp/nixx-heal-apply-$apply_stamp.exit
            set -l apply_timeout 180

            fish -c "opencode run --agent build --auto \$argv[1] >$apply_log 2>&1; echo \$status >$apply_exit" -- "$apply_prompt" &
            set -l apply_pid $last_pid

            fish -c "
                sleep $apply_timeout
                if test -f $apply_exit
                    exit 0
                end
                __nixx_kill_tree $apply_pid TERM
                sleep 2
                __nixx_kill_tree $apply_pid KILL
                test -f $apply_exit; or echo 124 >$apply_exit
            " &
            set -l apply_watchdog $last_pid

            gum spin --spinner dot \
                --spinner.foreground $p_purple \
                --title.foreground $p_muted \
                --title "  ⚡ applying fix..." \
                -- fish -c "while not test -f $apply_exit; sleep 0.2; end"

            __nixx_kill_tree $apply_watchdog KILL 2>/dev/null
            kill $apply_watchdog 2>/dev/null
            wait $apply_pid 2>/dev/null

            set -l apply_rc 1
            if test -f $apply_exit
                set apply_rc (string trim (cat $apply_exit))
            end
            rm -f $apply_exit

            if test $apply_rc -eq 0
                set -l head_after (git -C $repo rev-parse HEAD 2>/dev/null)
                set -l subject (git -C $repo log -1 --format=%s 2>/dev/null)

                if test "$head_after" != "$head_before"
                    if string match -q 'self-heal:*' -- $subject
                        gum join --horizontal \
                            (gum style --foreground $p_green "  ✓") \
                            (gum style --foreground $p_fg " fix applied") \
                            (gum style --foreground $p_muted --faint " ($subject)")
                    else
                        # committed, but without the requested prefix: leave
                        # the agent's commit alone, just surface it
                        gum join --horizontal \
                            (gum style --foreground $p_green "  ✓") \
                            (gum style --foreground $p_fg " fix applied") \
                            (gum style --foreground $p_yellow --faint " (committed as: $subject)")
                    end
                else
                    # no new commit: fall back to committing whatever the
                    # apply step left newly-dirty (pathspec commit, so any
                    # pre-existing staged/dirty files are not swept up)
                    set -l dirty_after (git -C $repo status --porcelain 2>/dev/null | string cut -c4- | sort)
                    set -l new_dirty
                    for f in $dirty_after
                        if not contains -- $f $dirty_before
                            set -a new_dirty $f
                        end
                    end

                    if test (count $new_dirty) -gt 0
                        git -C $repo add -- $new_dirty 2>/dev/null
                        git -C $repo commit --quiet -m "self-heal: $context" -- $new_dirty 2>/dev/null
                        if test $status -eq 0
                            gum join --horizontal \
                                (gum style --foreground $p_green "  ✓") \
                                (gum style --foreground $p_fg " fix applied") \
                                (gum style --foreground $p_muted --faint " (committed: self-heal: $context)")
                        else
                            gum join --horizontal \
                                (gum style --foreground $p_green "  ✓") \
                                (gum style --foreground $p_fg " fix applied") \
                                (gum style --foreground $p_yellow --faint " (uncommitted, staged; commit manually)")
                        end
                    else
                        gum join --horizontal \
                            (gum style --foreground $p_green "  ✓") \
                            (gum style --foreground $p_fg " fix applied") \
                            (gum style --foreground $p_muted --faint " (nothing to commit)")
                    end
                end
            else
                gum join --horizontal \
                    (gum style --foreground $p_red "  ✗") \
                    (gum style --foreground $p_fg " apply failed (rc=$apply_rc)")
                if test -s "$apply_log"
                    gum style --foreground $p_muted --faint "    log: $apply_log"
                else
                    rm -f $apply_log
                end
            end
            echo
            return 0

        case "Document*"
            set -l backlog_dir ~/.local/state/dotfiles
            mkdir -p $backlog_dir
            set -l backlog $backlog_dir/heal-backlog.md

            # Create file with header if it doesn't exist
            if not test -f "$backlog"
                printf '# heal backlog\n\n' >$backlog
            end

            printf '## %s - %s\n' (date +%Y-%m-%d) $context >>$backlog
            printf -- '- root cause: %s\n' $root_cause >>$backlog
            if test -n "$fix_text"
                printf -- '- fix: %s\n' $fix_text >>$backlog
            end
            printf -- '- status: documented\n\n' >>$backlog

            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " documented") \
                (gum style --foreground $p_muted --faint " (dot heal to view)")
            echo
            return 2

        case '*'
            gum style --foreground $p_muted --faint "  → skipped"
            echo
            return 1
    end
end
