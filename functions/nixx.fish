# nixx - system update and build tool
#
#  - nixx        - full update: nix, pnpm globals, brew, neovim, skills, etc.
#                  Independent tasks run in parallel via a DAG scheduler.
#                  Sudo is authenticated once; a background keep-alive refreshes
#                  the timestamp every 60 s so it never expires mid-run.
#                  The skills step uses skills-sync, which fetches all repo
#                  pushed_at timestamps in parallel and only updates changed skills.
#  - nixx l      - build and apply using current lock file (no updates)
#  - nixx locked - same as nixx l
#  - nixx b      - build only (no apply, no updates)
#  - nixx a      - apply only (assumes already built)
#
# Flags:
#  -v / --verbose  - sequential execution with full command output (no parallelism)


function nixx
    # --- gum guard ---
    if not type -q gum
        echo "Error: gum is not installed. add 'gum' to nix/modules/apps.nix then run nixx l"
        return 1
    end

    _aldo_dracula_apply_palette

    # --- parse flags ---
    set -g __nixx_verbose 0
    set -l mode ""
    set -l extra_args

    for arg in $argv
        switch $arg
            case -v --verbose
                set -g __nixx_verbose 1
            case '*'
                if test -z "$mode"
                    set mode $arg
                else
                    set -a extra_args $arg
                end
        end
    end

    # --- helper: run a step with timeout and log capture ---
    # Used by b/a/l modes and verbose full-update. The non-verbose full-update
    # path uses __nixx_run_dag (parallel) instead.
    # Usage: __nixx_step <label> [--timeout <seconds>] <command string...>
    # Default timeout: 300s. Output is captured; log shown on failure, deleted on success.
    function __nixx_step
        set -l label $argv[1]
        set -l timeout_secs 300
        set -l cmd_parts

        # parse optional --timeout N after label
        set -l i 2
        while test $i -le (count $argv)
            if test "$argv[$i]" = --timeout
                set i (math $i + 1)
                set timeout_secs $argv[$i]
            else
                set -a cmd_parts $argv[$i]
            end
            set i (math $i + 1)
        end
        set -l cmd (string join " " $cmd_parts)

        set -l logfile /tmp/nixx-(string replace -ra '[^a-zA-Z0-9]' '-' $label)-(date +%s).log
        set -l t_start (date +%s)
        set -l status_code 0

        if test "$__nixx_verbose" -eq 1
            echo
            gum style --foreground $p_muted --bold "  $label"
            echo
            eval $cmd
            set status_code $status
        else
            # Run command in background, capturing output to logfile.
            # Single-shell pattern: `begin; $cmd; end` ensures the redirection
            # captures ALL output (including compound commands with ; and ||),
            # and single quotes in $cmd are parsed correctly by fish -c.
            # A watchdog kills the whole process tree if timeout is exceeded and
            # always writes the exitfile so the spinner loop below can never hang.
            set -l exitfile {$logfile}.exit
            set -l timedoutfile {$logfile}.timedout
            fish -c "begin; $cmd; end >$logfile 2>&1; echo \$status >$exitfile" &
            set -l job_pid $last_pid

            # Watchdog: after timeout_secs, kill the job's entire descendant tree
            # (job control is often off under `fish -c`, so a process-group kill is
            # unreliable — we walk the tree via pgrep instead). Crucially it also
            # marks the timeout and writes the exitfile so the spinner unblocks.
            fish -c "
                sleep $timeout_secs
                if test -f $exitfile
                    exit 0
                end
                touch $timedoutfile
                __nixx_kill_tree $job_pid TERM
                sleep 2
                __nixx_kill_tree $job_pid KILL
                # ensure spinner unblocks even if the killed child never wrote it
                test -f $exitfile; or echo 124 >$exitfile
            " &
            set -l watchdog_pid $last_pid

            gum spin --spinner dot \
                --spinner.foreground $p_purple \
                --title.foreground $p_muted \
                --title "  $label" \
                -- fish -c "while not test -f $exitfile; sleep 0.2; end"

            # kill watchdog if still running (job finished on its own)
            __nixx_kill_tree $watchdog_pid KILL 2>/dev/null
            kill $watchdog_pid 2>/dev/null

            wait $job_pid 2>/dev/null
            if test -f $timedoutfile
                set status_code 124
                echo "[nixx] killed after {$timeout_secs}s timeout" >> $logfile
            else if test -f $exitfile
                set status_code (string trim (cat $exitfile))
            else
                set status_code 1
            end
            rm -f $exitfile $timedoutfile
        end

        set -l t_end (date +%s)
        set -l elapsed (math "$t_end - $t_start")
        set -l elapsed_str (__nixx_fmt_time $elapsed)

        if test $status_code -eq 0
            if test "$__nixx_verbose" -eq 1
                echo
                gum join --horizontal \
                    (gum style --foreground $p_green --bold "  ✓ Done") \
                    (gum style --foreground $p_muted " ($elapsed_str)")
            else
                gum join --horizontal \
                    (gum style --foreground $p_green "  ✓") \
                    (gum style --foreground $p_fg " $label") \
                    (gum style --foreground $p_muted " ($elapsed_str)")
            end
            set -g __nixx_results $__nixx_results "$label|ok|$elapsed_str|"
            rm -f $logfile
        else
            set -l reason
            if test $status_code -eq 124
                set reason " (timed out after {$timeout_secs}s)"
            end
            if test "$__nixx_verbose" -eq 1
                echo
                gum join --horizontal \
                    (gum style --foreground $p_red --bold "  ✗ Failed") \
                    (gum style --foreground $p_muted " ($elapsed_str$reason)")
            else
                gum join --horizontal \
                    (gum style --foreground $p_red "  ✗") \
                    (gum style --foreground $p_fg " $label") \
                    (gum style --foreground $p_muted " ($elapsed_str$reason)")
                gum style --foreground $p_muted "     log: $logfile"
            end
            set -g __nixx_results $__nixx_results "$label|fail|$elapsed_str|$logfile"
        end
    end

    # --- init tracking ---
    set -g __nixx_results
    set -g __nixx_brew_upgraded_count 0
    set -g __nixx_sudo_keep_pid 0
    set -l total_start (date +%s)

    # --- drift-check-only shortcut ---
    switch "$mode"
        case check d
            nixx-drift
            return $status
    end

    # --- resolve mode label ---
    set -l mode_label
    switch "$mode"
        case b
            set mode_label "build"
        case a
            set mode_label "apply"
        case l locked
            set mode_label "locked"
        case '*'
            set mode_label "full update"
    end

    # --- header ---
    echo
    gum style --bold --foreground $p_purple --border rounded --border-foreground $p_purple \
        --padding "0 2" --align center \
        "nixx · $mode_label" \
        (gum style --faint --foreground $p_muted "$hostname")

    # --- sudo pre-auth + keep-alive for modes that need it ---
    switch "$mode"
        case a l locked '' '*'
            sudo -v 2>/dev/null
            if test $status -ne 0
                gum style --foreground $p_red "  ✗ sudo authentication failed"
                set -e __nixx_verbose
                set -e __nixx_results
                set -e __nixx_brew_upgraded_count
                set -e __nixx_sudo_keep_pid
                functions -e __nixx_step
                return 1
            end
            # Keep sudo timestamp alive for the entire run (macOS default
            # timestamp_timeout is 5 min; refresh every 60 s).
            fish -c "while true; sudo -v 2>/dev/null; or exit; sleep 60; end" &
            set __nixx_sudo_keep_pid $last_pid
    end

    # --- pre-expand hostname and extra_args for command strings ---
    set -l hn $hostname
    set -l ea (string join " " $extra_args)

    # --- execute based on mode ---
    switch "$mode"
        case b
            echo
            gum style --foreground $p_cyan --bold "⚙  nix build"
            __nixx_step "Building nix configuration" \
                "cd ~/.config/nix && nix build '.#darwinConfigurations.$hn.system' --extra-experimental-features 'nix-command flakes' $ea"

        case a
            echo
            gum style --foreground $p_cyan --bold "⚙  nix apply"
            __nixx_step "Applying nix configuration" \
                "cd ~/.config/nix && sudo -E ./result/sw/bin/darwin-rebuild switch --flake '.#$hn'"
            __nixx_step "Collecting nix garbage" \
                "nix-collect-garbage -d"
            __nixx_step "Cleaning up homebrew" \
                "brew cleanup"

        case l locked
            echo
            gum style --foreground $p_cyan --bold "⚙  nix build + apply (locked)"
            __nixx_step "Building nix configuration" \
                "cd ~/.config/nix && nix build '.#darwinConfigurations.$hn.system' --extra-experimental-features 'nix-command flakes' $ea"
            __nixx_step "Applying nix configuration" \
                "cd ~/.config/nix && sudo -E ./result/sw/bin/darwin-rebuild switch --flake '.#$hn'"
            __nixx_step "Collecting nix garbage" \
                "nix-collect-garbage -d"
            __nixx_step "Cleaning up homebrew" \
                "brew cleanup"

        case '*'
            # Full update: parallel DAG (non-verbose) or sequential (verbose)
            #
            # Single task table in DAG format: section|task_id|label|timeout|dep_ids|hint|command
            # The verbose path iterates it sequentially; the DAG path passes it to __nixx_run_dag.
            set -l tasks
            set -a tasks "nix|nix-flake|Updating nix flake|300|||cd ~/.config/nix && nix flake update"
            set -a tasks "nix|nix-build|Building nix configuration|300|nix-flake||cd ~/.config/nix && nix build '.#darwinConfigurations.$hn.system' --extra-experimental-features 'nix-command flakes' $ea"
            set -a tasks "nix|nix-apply|Applying nix configuration|300|nix-build||cd ~/.config/nix && sudo -E ./result/sw/bin/darwin-rebuild switch --flake '.#$hn'"
            set -a tasks "nix|nix-gc|Collecting nix garbage|300|nix-apply||nix-collect-garbage -d"
            set -a tasks "brew|brew-update|Updating homebrew|60|nix-apply||brew update"
            set -a tasks "brew|brew-upgrade|Upgrading homebrew packages|600|brew-update|==> Upgrading |opencode-upgrade-check; and brew upgrade"
            set -a tasks "brew|brew-cleanup|Cleaning up homebrew|300|brew-upgrade||brew cleanup"
            set -a tasks "nvim|nvim|Updating neovim plugins|600|||nvim --headless '+Lazy! sync' '+qa!'"
            set -a tasks "skills|skills|Updating agent skills|300|||skills-sync"
            set -a tasks "claude|claude|Installing/updating claude|60|||curl -fsSL https://claude.ai/install.sh | sh"
            set -a tasks "node|node-fnm|Installing latest node (fnm)|300|||fnm install --lts && fnm default lts-latest"
            set -a tasks "node|node-corepack-enable|Enabling corepack shims|60|node-fnm||corepack enable"
            set -a tasks "node|node-corepack-prepare|Updating pnpm (corepack)|60|node-corepack-enable||corepack prepare pnpm@latest --activate"
            set -a tasks "node|node-pnpm-globals|Updating pnpm globals|120|node-corepack-prepare||pnpm update -g"
            set -a tasks "uv|uv-tools|Updating uv tools|120|||uv tool upgrade --all"
            set -a tasks "opencode|opencode-plugin|Updating opencode plugin|120|node-pnpm-globals||pnpm update --dir ~/.config/opencode; or begin; rm -rf ~/.config/opencode/node_modules; and pnpm update --dir ~/.config/opencode; end"

            if test "$__nixx_verbose" -eq 1
                # --- verbose: sequential with full output ---
                set -l cur_section ""
                for task in $tasks
                    set -l parts (string split "|" $task -m 6)
                    set -l section $parts[1]
                    set -l label $parts[3]
                    set -l timeout $parts[4]
                    set -l cmd $parts[7]
                    if test "$section" != "$cur_section"
                        echo
                        gum style --foreground $p_cyan --bold "⚙  $section"
                        set cur_section $section
                    end
                    __nixx_step "$label" --timeout $timeout "$cmd"
                end
            else
                # --- parallel: DAG scheduler ---
                echo
                __nixx_run_dag $tasks
                echo

                # Clean up success logfiles (keep failure logs for the summary)
                for r in $__nixx_results
                    set -l parts (string split "|" $r)
                    if test "$parts[2]" = ok -a -n "$parts[4]" -a -f "$parts[4]"
                        rm -f "$parts[4]"
                    end
                end
            end
    end

    # --- summary ---
    # (printed before drift check so the full-update summary is visible, then
    #  drift check runs interactively below it)
    set -l total_end (date +%s)
    set -l total_elapsed (math "$total_end - $total_start")
    set -l total_elapsed_str (__nixx_fmt_time $total_elapsed)

    set -l fail_count 0
    set -l pass_count 0
    set -l blocked_count 0
    set -l failed_logs
    for r in $__nixx_results
        set -l parts (string split "|" $r)
        if test "$parts[2]" = ok
            set pass_count (math $pass_count + 1)
        else if test "$parts[2]" = blocked
            set blocked_count (math $blocked_count + 1)
        else
            set fail_count (math $fail_count + 1)
            if test -n "$parts[4]" -a -f "$parts[4]"
                set -a failed_logs "$parts[1]: $parts[4]"
            end
        end
    end

    set -l total_count (math $pass_count + $fail_count + $blocked_count)

    # build summary detail line
    set -l detail_parts
    if test "$__nixx_brew_upgraded_count" -gt 0
        set -a detail_parts "$__nixx_brew_upgraded_count packages upgraded"
    end
    if test $fail_count -gt 0
        set -a detail_parts "$fail_count step(s) failed"
    end
    if test $blocked_count -gt 0
        set -a detail_parts "$blocked_count step(s) blocked"
    end
    set -l detail_str (string join " · " $detail_parts)

    echo
    if test $fail_count -eq 0
        if test -n "$detail_str"
            gum style --foreground $p_green --bold --border rounded --border-foreground $p_green \
                --padding "0 2" \
                "✓  Done · $total_elapsed_str" \
                (gum style --faint --foreground $p_muted "$detail_str")
        else
            gum style --foreground $p_green --bold --border rounded --border-foreground $p_green \
                --padding "0 2" \
                "✓  Done · $total_elapsed_str"
        end
    else
        if test -n "$detail_str"
            gum style --foreground $p_red --bold --border rounded --border-foreground $p_red \
                --padding "0 2" \
                "▲  $fail_count of $total_count steps failed · $total_elapsed_str" \
                (gum style --faint --foreground $p_muted "$detail_str")
        else
            gum style --foreground $p_red --bold --border rounded --border-foreground $p_red \
                --padding "0 2" \
                "▲  $fail_count of $total_count steps failed · $total_elapsed_str"
        end
    end
    # list logs for failed steps
    if test (count $failed_logs) -gt 0
        for entry in $failed_logs
            gum style --foreground $p_muted "  log: $entry"
        end
    end
    echo

    # --- cleanup ---
    # kill sudo keep-alive
    if test $__nixx_sudo_keep_pid -gt 0
        kill $__nixx_sudo_keep_pid 2>/dev/null
    end
    set -e __nixx_verbose
    set -e __nixx_results
    set -e __nixx_brew_upgraded_count
    set -e __nixx_sudo_keep_pid
    functions -e __nixx_step

    # --- drift check (full update only) ---
    switch "$mode"
        case '' '*'
            nixx-drift

            # --- restore custom LaunchAgents (full update only) ---
            # Ensures any *.plist in ~/.config/scripts/*/ is loaded.
            # Stderr is captured to a temp file so _nixx_heal can diagnose
            # fish runtime errors (e.g. test syntax errors) without catching
            # gum's terminal control output on stdout.
            if type -q scripts-restore
                set -l sr_stderr /tmp/nixx-scripts-restore-(date +%s).err
                scripts-restore 2>$sr_stderr
                if test -s $sr_stderr
                    and grep -q '\.fish.*(line [0-9]\+):' $sr_stderr 2>/dev/null
                    _nixx_heal "scripts-restore error" \
                        (cat $sr_stderr | string collect) \
                        ~/.config/fish/functions/scripts-restore.fish
                end
                rm -f $sr_stderr
            end

            # --- publish public dotfiles (full update only) ---
            # Syncs the public-safe subset of ~/.config to its GitHub repos.
            # Shows a diff + confirms before pushing; secret-scan gates every repo.
            if type -q publish-dots
                publish-dots
            end

            # --- self-heal failed steps ---
            # After all sub-commands finish, offer to heal any steps that
            # failed during the update. Uses the captured logfiles.
            if test $fail_count -gt 0; and type -q _nixx_heal
                for entry in $failed_logs
                    set -l parts (string split ": " $entry)
                    set -l label $parts[1]
                    set -l logfile $parts[2]
                    if test -f "$logfile"
                        _nixx_heal "$label failure" \
                            (cat $logfile | string collect) \
                            ~/.config/fish/functions/nixx.fish
                    end
                end
            end
    end

    if test $fail_count -gt 0
        return 1
    end
end
