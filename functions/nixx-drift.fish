# nixx-drift - package drift detection and remediation
#
# Scans four surfaces for drift between what's declared in config and what's
# actually installed:
#   1. Homebrew brews    ← nix/modules/apps.nix
#   2. Homebrew casks    ← nix/modules/apps.nix
#   3. pnpm globals      ← pnpm/globals.txt
#   4. uv tools          ← uv/tools.txt
#
# Called directly as `nixx check` / `nixx d`, or invoked from nixx.fish after
# a full update. Returns 0 if no drift found, 1 if any unresolved drift remains.

function nixx-drift
    _aldo_dracula_apply_palette

    # NB: these must be GLOBAL, not `set -l`. The __drift_* helpers below are
    # defined as nested functions, and fish functions do NOT inherit the
    # enclosing function's local variables — a `set -l` here would read as empty
    # inside __drift_brew/__drift_pnpm/__drift_uv (producing `cd &&` → wrong dir,
    # and empty canonical lists → false "extra" drift). Cleaned up at the end.
    set -g __drift_config_dir ~/.config
    set -g __drift_nix_dir $__drift_config_dir/nix

    # Interactive TTY guard. gum's choose/confirm need a real terminal; when nixx
    # runs non-interactively (backgrounded, piped, in CI) those calls fail with
    # "could not open a new TTY". In that case we run in report-only mode: drift
    # is listed but no interactive remediation is attempted.
    set -g __drift_interactive 1
    if not test -t 0; or not test -t 1
        set -g __drift_interactive 0
    end

    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    # Parse a canonical package list: strip comments and blank lines, sort.
    # Uses fish string ops (no reliance on grep's \s handling across platforms).
    function __drift_parse_list
        test -f $argv[1]; or return 0
        for line in (cat $argv[1])
            set -l trimmed (string trim -- $line)
            test -z "$trimmed"; and continue
            string match -q -- '#*' $trimmed; and continue
            echo $trimmed
        end | sort
    end

    # Echo 1 if the canonical list has at least one real (non-comment) entry,
    # else 0. Used to distinguish "genuinely empty list" from "read failed".
    function __drift_list_has_entries
        set -l entries (__drift_parse_list $argv[1])
        if test (count $entries) -gt 0
            echo 1
        else
            echo 0
        end
    end

    # Extract `.name` values from a captured `nix eval --json` log.
    # nix prints warnings ("Git tree is dirty", "Using saved setting", obsolete
    # option traces) to the same stream we capture, so the log is NOT pure JSON.
    # Grab the single JSON array line (starts with `[`) and feed only that to jq.
    function __drift_json_names
        test -f $argv[1]; or return 0
        set -l json_line (grep -m1 '^\[' $argv[1] 2>/dev/null)
        test -n "$json_line"; or return 0
        printf '%s\n' $json_line | jq -r '.[].name' 2>/dev/null | sort
    end

    # Run a command with a timeout (seconds). Stdout captured to $argv[-1] logfile.
    # Usage: __drift_run_timed <timeout_secs> <logfile> <cmd>
    # Returns the exit code (124 = timed out).
    function __drift_run_timed
        set -l timeout_secs $argv[1]
        set -l logfile $argv[2]
        set -l cmd (string join " " $argv[3..-1])
        set -l exitfile {$logfile}.exit

        fish -c "$cmd >$logfile 2>&1; echo \$status >$exitfile" &
        set -l job_pid $last_pid

        perl -e "sleep $timeout_secs; kill 'TERM', $job_pid; sleep 2; kill 'KILL', $job_pid;" \
            >/dev/null 2>&1 &
        set -l watchdog_pid $last_pid

        wait $job_pid 2>/dev/null
        kill $watchdog_pid 2>/dev/null

        if test -f $exitfile
            set -l rc (string trim (cat $exitfile))
            rm -f $exitfile
            return $rc
        else
            rm -f $exitfile
            return 124
        end
    end

    function __drift_header
        echo
        gum style --bold --foreground $p_purple --border rounded --border-foreground $p_purple \
            --padding "0 2" --align center \
            "nixx · drift check" \
            (gum style --faint --foreground $p_muted "$hostname")
    end

    function __drift_section
        echo
        gum style --foreground $p_cyan --bold "⚙  $argv[1]"
    end

    # Print a drift item with context and prompt for action.
    # Usage: __drift_item <kind> <surface> <name> [extra_info]
    #   kind:    "extra" (installed, not declared) | "missing" (declared, not installed)
    #   surface: display label (e.g. "brew formula")
    #   name:    package/tool name
    #   extra_info: optional additional context shown in dim
    #
    # Returns via $__drift_action: dismiss | add | remove | install
    function __drift_item
        set -l kind $argv[1]
        set -l surface $argv[2]
        set -l name $argv[3]
        set -l extra $argv[4]

        set -e __drift_action

        if test "$kind" = extra
            set -l label (gum join --horizontal \
                (gum style --foreground $p_orange "  ▸ extra") \
                (gum style --foreground $p_fg "  $name") \
                (gum style --foreground $p_muted "  $surface"))
            echo $label
            if test -n "$extra"
                gum style --foreground $p_muted --faint "    $extra"
            end

            # Report-only mode (no TTY): list the item and move on.
            if test "$__drift_interactive" -eq 0
                gum style --foreground $p_muted --faint "    → report-only (no TTY); resolve with: nixx check"
                set -g __drift_action dismiss
                return
            end

            set -l choice (gum choose \
                --cursor.foreground $p_purple \
                --selected.foreground $p_purple \
                --header "    What should happen with '$name'?" \
                --header.foreground $p_muted \
                "Dismiss  (keep installed, skip for now)" \
                "Add to config  (declare it in the canonical list)" \
                "Uninstall / remove  (remove from system)")

            switch "$choice"
                case "Dismiss*"
                    set -g __drift_action dismiss
                case "Add*"
                    set -g __drift_action add
                case "Uninstall*" "remove*"
                    set -g __drift_action remove
            end

        else if test "$kind" = missing
            set -l label (gum join --horizontal \
                (gum style --foreground $p_yellow "  ▸ missing") \
                (gum style --foreground $p_fg "  $name") \
                (gum style --foreground $p_muted "  $surface"))
            echo $label
            if test -n "$extra"
                gum style --foreground $p_muted --faint "    $extra"
            end

            # Report-only mode (no TTY): list the item and move on.
            if test "$__drift_interactive" -eq 0
                gum style --foreground $p_muted --faint "    → report-only (no TTY); resolve with: nixx check"
                set -g __drift_action dismiss
                return
            end

            set -l choice (gum choose \
                --cursor.foreground $p_purple \
                --selected.foreground $p_purple \
                --header "    '$name' is declared but not installed. What should happen?" \
                --header.foreground $p_muted \
                "Dismiss  (skip for now)" \
                "Install now")

            switch "$choice"
                case "Dismiss*"
                    set -g __drift_action dismiss
                case "Install*"
                    set -g __drift_action install
            end
        end
    end

    # Confirm a destructive action. Returns 0 if confirmed.
    function __drift_confirm_destructive
        set -l msg $argv[1]
        # Never perform destructive actions without an interactive TTY.
        if test "$__drift_interactive" -eq 0
            return 1
        end
        set -l choice (gum choose \
            --cursor.foreground $p_red \
            --selected.foreground $p_red \
            --header "    $msg" \
            --header.foreground $p_orange \
            "Cancel" \
            "Yes, proceed")
        test "$choice" = "Yes, proceed"
    end

    # -------------------------------------------------------------------------
    # Surface 1 + 2: Homebrew brews and casks (via nix eval)
    # -------------------------------------------------------------------------

    function __drift_brew
        __drift_section "Homebrew"

        set -l hn $hostname
        set -l nix_log /tmp/nixx-drift-nix-eval-(date +%s).log

        # Evaluate declared brews and casks with SEPARATE nix evals.
        # NB: do NOT eval the whole `.config.homebrew` attribute — that forces
        # evaluation of removed/renamed options (e.g. `homebrew.brewPrefix`) and
        # errors out. Targeting `.brews`/`.casks` directly sidesteps that.
        #
        # Raw JSON is captured to a file (rather than piped straight into jq) so
        # the true nix exit status is preserved — a piped `nix eval | jq` would
        # report jq's status and silently mask a nix failure.
        # 90s timeout: a freshly-updated flake may need to evaluate uncached.
        set -l brews_log {$nix_log}-brews
        __drift_run_timed 90 $brews_log \
            "cd $__drift_nix_dir && nix eval '.#darwinConfigurations.$hn.config.homebrew.brews' --extra-experimental-features 'nix-command flakes' --json"
        set -l brews_rc $status
        set -l declared_brews
        if test $brews_rc -eq 0
            set declared_brews (__drift_json_names $brews_log)
        end

        set -l casks_log {$nix_log}-casks
        __drift_run_timed 90 $casks_log \
            "cd $__drift_nix_dir && nix eval '.#darwinConfigurations.$hn.config.homebrew.casks' --extra-experimental-features 'nix-command flakes' --json"
        set -l casks_rc $status
        set -l declared_casks
        if test $casks_rc -eq 0
            set declared_casks (__drift_json_names $casks_log)
        end

        if test -z "$declared_brews" -a -z "$declared_casks"
            set -l reason
            if test $brews_rc -eq 124 -o $casks_rc -eq 124
                set reason " (nix eval timed out after 90s)"
            else if test $brews_rc -ne 0 -o $casks_rc -ne 0
                set reason " (nix eval failed)"
            end
            gum style --foreground $p_red "  ✗ Could not evaluate nix config — skipping brew drift check$reason"
            # Surface the eval error so the cause isn't hidden.
            for l in $brews_log $casks_log
                if test -s $l
                    set -l errline (grep -i error $l 2>/dev/null | head -1)
                    if test -n "$errline"
                        gum style --foreground $p_muted --faint "    $errline"
                        gum style --foreground $p_muted --faint "    log: $l"
                        break
                    end
                end
            end
            return
        end
        rm -f $brews_log $casks_log

        # For "extra" detection: brew leaves = explicitly installed, not a dep of anything else.
        # `brew leaves` returns full tap-prefixed names for tap formulae.
        set -l leaves_brews_raw (brew leaves 2>/dev/null)
        # For "missing" detection: full formula list — declared things may be installed as deps.
        # `brew list --formula` returns short names only.
        set -l all_installed_brews (brew list --formula 2>/dev/null | sort)
        # Installed casks (always explicit)
        set -l installed_casks (brew list --cask 2>/dev/null | sort)

        # Normalize both declared and installed brew names by stripping tap prefixes.
        # e.g. "anomalyco/tap/opencode" → "opencode", "oven-sh/bun/bun" → "bun"
        set -l declared_brews_normalized
        for pkg in $declared_brews
            set declared_brews_normalized $declared_brews_normalized (string replace -ra '^.+/' '' $pkg)
        end

        # Build parallel arrays for leaves: raw name (for display/action) and normalized
        set -l leaves_brews_normalized
        for pkg in $leaves_brews_raw
            set leaves_brews_normalized $leaves_brews_normalized (string replace -ra '^.+/' '' $pkg)
        end

        set -l brew_found_drift 0

        # --- brews: extra (leaf-installed but not declared) ---
        # Only flags formulae that nothing else depends on — avoids false positives
        # from packages installed as transitive dependencies.
        for i in (seq (count $leaves_brews_raw))
            set -l pkg $leaves_brews_raw[$i]
            set -l pkg_short $leaves_brews_normalized[$i]
            if not contains -- $pkg_short $declared_brews_normalized
                set brew_found_drift 1
                __drift_item extra "brew formula" $pkg
                switch "$__drift_action"
                    case add
                        gum style --foreground $p_muted \
                            "    → Add \"$pkg\" to commonBrews or a host-specific list in nix/modules/apps.nix, then run nixx l to apply."
                    case remove
                        if __drift_confirm_destructive "Uninstall brew formula '$pkg'?"
                            gum spin --spinner dot --spinner.foreground $p_purple \
                                --title "  Uninstalling $pkg..." \
                                -- fish -c "brew uninstall --formula $pkg"
                            if test $status -eq 0
                                gum style --foreground $p_green "  ✓ Uninstalled $pkg"
                            else
                                gum style --foreground $p_red "  ✗ Failed to uninstall $pkg"
                            end
                        else
                            gum style --foreground $p_muted "  → Skipped"
                        end
                end
            end
        end

        # --- brews: missing (declared but not in full installed list) ---
        # Compares normalized names (tap prefix stripped) against full brew list.
        for i in (seq (count $declared_brews))
            set -l pkg $declared_brews[$i]
            set -l pkg_short $declared_brews_normalized[$i]
            if not contains -- $pkg_short $all_installed_brews
                set brew_found_drift 1
                __drift_item missing "brew formula" $pkg "declared in apps.nix but not installed"
                switch "$__drift_action"
                    case install
                        gum spin --spinner dot --spinner.foreground $p_purple \
                            --title "  Installing $pkg..." \
                            -- fish -c "brew install $pkg"
                        if test $status -eq 0
                            gum style --foreground $p_green "  ✓ Installed $pkg"
                        else
                            gum style --foreground $p_red "  ✗ Failed to install $pkg"
                        end
                end
            end
        end

        # --- casks: extra ---
        for pkg in $installed_casks
            if not contains -- $pkg $declared_casks
                set brew_found_drift 1
                __drift_item extra "brew cask" $pkg
                switch "$__drift_action"
                    case add
                        gum style --foreground $p_muted \
                            "    → Add \"$pkg\" to commonCasks or a host-specific list in nix/modules/apps.nix, then run nixx l to apply."
                    case remove
                        if __drift_confirm_destructive "Uninstall cask '$pkg'? This removes the application."
                            gum spin --spinner dot --spinner.foreground $p_purple \
                                --title "  Uninstalling $pkg..." \
                                -- fish -c "brew uninstall --cask $pkg"
                            if test $status -eq 0
                                gum style --foreground $p_green "  ✓ Uninstalled $pkg"
                            else
                                gum style --foreground $p_red "  ✗ Failed to uninstall $pkg"
                            end
                        else
                            gum style --foreground $p_muted "  → Skipped"
                        end
                end
            end
        end

        # --- casks: missing ---
        for pkg in $declared_casks
            if not contains -- $pkg $installed_casks
                set brew_found_drift 1
                __drift_item missing "brew cask" $pkg "declared in apps.nix but not installed"
                switch "$__drift_action"
                    case install
                        gum spin --spinner dot --spinner.foreground $p_purple \
                            --title "  Installing $pkg..." \
                            -- fish -c "brew install --cask $pkg"
                        if test $status -eq 0
                            gum style --foreground $p_green "  ✓ Installed $pkg"
                        else
                            gum style --foreground $p_red "  ✗ Failed to install $pkg"
                        end
                end
            end
        end

        if test $brew_found_drift -eq 0
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " No drift")
        end
    end

    # -------------------------------------------------------------------------
    # Surface 3: pnpm globals
    # -------------------------------------------------------------------------

    function __drift_pnpm
        __drift_section "pnpm globals"

        set -l canonical_file $__drift_config_dir/pnpm/globals.txt

        if not test -f $canonical_file
            gum style --foreground $p_red "  ✗ $canonical_file not found — skipping"
            return
        end

        # Parse canonical list (strip comments and blank lines)
        set -l declared (__drift_parse_list $canonical_file)

        # Guard against a transient/empty read of the canonical list: if the file
        # has real (non-comment) content but parsing yielded nothing, bail out
        # rather than flagging every installed package as "extra".
        if test -z "$declared"; and test (__drift_list_has_entries $canonical_file) -eq 1
            gum style --foreground $p_red "  ✗ Could not read pnpm/globals.txt — skipping"
            return
        end

        # Installed pnpm globals (package names only, 30s timeout)
        set -l pnpm_log /tmp/nixx-drift-pnpm-(date +%s).log
        __drift_run_timed 30 $pnpm_log "pnpm list -g --depth=0 --json"
        set -l pnpm_rc $status
        set -l installed
        if test $pnpm_rc -eq 0
            set installed (jq -r '.[0].dependencies | keys[]' $pnpm_log 2>/dev/null | sort)
        end
        rm -f $pnpm_log

        if test -z "$installed"
            set -l reason
            if test $pnpm_rc -eq 124
                set reason " (timed out after 30s)"
            end
            gum style --foreground $p_red "  ✗ Could not read pnpm global packages — skipping$reason"
            return
        end

        set -l found_drift 0

        # Extra: installed but not declared
        for pkg in $installed
            if not contains -- $pkg $declared
                set found_drift 1
                __drift_item extra "pnpm global" $pkg
                switch "$__drift_action"
                    case add
                        echo "    $pkg" >> $canonical_file
                        gum style --foreground $p_green "  ✓ Added '$pkg' to pnpm/globals.txt"
                        gum style --foreground $p_muted "  → Remember to commit the change"
                    case remove
                        if __drift_confirm_destructive "Uninstall pnpm global '$pkg'?"
                            gum spin --spinner dot --spinner.foreground $p_purple \
                                --title "  Removing $pkg..." \
                                -- fish -c "pnpm remove -g $pkg"
                            if test $status -eq 0
                                gum style --foreground $p_green "  ✓ Removed $pkg"
                            else
                                gum style --foreground $p_red "  ✗ Failed to remove $pkg"
                            end
                        else
                            gum style --foreground $p_muted "  → Skipped"
                        end
                end
            end
        end

        # Missing: declared but not installed
        for pkg in $declared
            if not contains -- $pkg $installed
                set found_drift 1
                __drift_item missing "pnpm global" $pkg "in pnpm/globals.txt but not installed"
                switch "$__drift_action"
                    case install
                        gum spin --spinner dot --spinner.foreground $p_purple \
                            --title "  Installing $pkg..." \
                            -- fish -c "pnpm add -g $pkg"
                        if test $status -eq 0
                            gum style --foreground $p_green "  ✓ Installed $pkg"
                        else
                            gum style --foreground $p_red "  ✗ Failed to install $pkg"
                        end
                end
            end
        end

        if test $found_drift -eq 0
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " No drift")
        end
    end

    # -------------------------------------------------------------------------
    # Surface 4: uv tools
    # -------------------------------------------------------------------------

    function __drift_uv
        __drift_section "uv tools"

        set -l canonical_file $__drift_config_dir/uv/tools.txt

        if not test -f $canonical_file
            gum style --foreground $p_red "  ✗ $canonical_file not found — skipping"
            return
        end

        # Parse canonical list
        set -l declared (__drift_parse_list $canonical_file)

        # Guard against a transient/empty read of the canonical list.
        if test -z "$declared"; and test (__drift_list_has_entries $canonical_file) -eq 1
            gum style --foreground $p_red "  ✗ Could not read uv/tools.txt — skipping"
            return
        end

        # Installed uv tools — top-level lines only (sub-executables start with "- ")
        set -l installed (uv tool list 2>/dev/null | grep -v '^-' | grep -v '^\s*$' | awk '{print $1}' | sort)

        if test -z "$installed" -a (count $declared) -gt 0
            gum style --foreground $p_yellow "  ▸ No uv tools installed"
        end

        set -l found_drift 0

        # Extra: installed but not declared
        for pkg in $installed
            if not contains -- $pkg $declared
                set found_drift 1
                __drift_item extra "uv tool" $pkg
                switch "$__drift_action"
                    case add
                        echo "$pkg" >> $canonical_file
                        gum style --foreground $p_green "  ✓ Added '$pkg' to uv/tools.txt"
                        gum style --foreground $p_muted "  → Remember to commit the change"
                    case remove
                        if __drift_confirm_destructive "Uninstall uv tool '$pkg'?"
                            gum spin --spinner dot --spinner.foreground $p_purple \
                                --title "  Removing $pkg..." \
                                -- fish -c "uv tool uninstall $pkg"
                            if test $status -eq 0
                                gum style --foreground $p_green "  ✓ Removed $pkg"
                            else
                                gum style --foreground $p_red "  ✗ Failed to remove $pkg"
                            end
                        else
                            gum style --foreground $p_muted "  → Skipped"
                        end
                end
            end
        end

        # Missing: declared but not installed
        for pkg in $declared
            if not contains -- $pkg $installed
                set found_drift 1
                __drift_item missing "uv tool" $pkg "in uv/tools.txt but not installed"
                switch "$__drift_action"
                    case install
                        gum spin --spinner dot --spinner.foreground $p_purple \
                            --title "  Installing $pkg..." \
                            -- fish -c "uv tool install $pkg"
                        if test $status -eq 0
                            gum style --foreground $p_green "  ✓ Installed $pkg"
                        else
                            gum style --foreground $p_red "  ✗ Failed to install $pkg"
                        end
                end
            end
        end

        if test $found_drift -eq 0
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " No drift")
        end
    end

    # -------------------------------------------------------------------------
    # Run all checks
    # -------------------------------------------------------------------------

    __drift_header
    __drift_brew
    __drift_pnpm
    __drift_uv

    echo

    # Cleanup inner functions
    functions -e __drift_parse_list
    functions -e __drift_list_has_entries
    functions -e __drift_json_names
    functions -e __drift_run_timed
    functions -e __drift_header
    functions -e __drift_section
    functions -e __drift_item
    functions -e __drift_confirm_destructive
    functions -e __drift_brew
    functions -e __drift_pnpm
    functions -e __drift_uv
    set -e __drift_action
    set -e __drift_interactive
    set -e __drift_config_dir
    set -e __drift_nix_dir
end
