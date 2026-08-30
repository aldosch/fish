# nixx-drift - package drift detection and remediation
#
# Scans eight surfaces for drift between what's declared in config and what's
# actually installed (or, for surface 8, between what nix generates and what's
# on disk):
#   1. Homebrew brews    ← nix/modules/apps.nix
#   2. Homebrew casks    ← nix/modules/apps.nix
#   3. pnpm globals      ← pnpm/globals.txt
#   4. uv tools          ← uv/tools.txt
#   5. opencode plugin   ← opencode/pnpm-lock.yaml (node_modules is gitignored)
#   6. model catalog     ← opencode/model-catalog.json (staleness check against
#                          the live Vercel AI Gateway catalog, not an
#                          install/declare drift — informational only)
#   7. opencode MCP cmds ← opencode/opencode.json local MCPs must not use `pnpx`
#                          (broken under pnpm 11's global virtual store for ESM
#                          packages); plus a functional smoke test from a neutral
#                          directory so a silent pnpm dlx regression is caught
#                          before it takes down every pnpx-based MCP at once.
#   8. generated files   ← files written by nix activation scripts (ghostty
#                          config) compared against /etc/static/<name>-expected
#                          exposed via environment.etc; catches manual edits to
#                          files that should only be nix-generated.
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
        __drift_section "brew"

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

        # Normalize cask names by stripping tap prefixes, same as brews above.
        # e.g. "rauchg/typing-stats/typing-stats" → "typing-stats"
        # `brew list --cask` returns short names; nix eval returns full tap-prefixed names.
        set -l declared_casks_normalized
        for pkg in $declared_casks
            set declared_casks_normalized $declared_casks_normalized (string replace -ra '^.+/' '' $pkg)
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
            if not contains -- $pkg $declared_casks_normalized
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
        for i in (seq (count $declared_casks))
            set -l pkg $declared_casks[$i]
            set -l pkg_short $declared_casks_normalized[$i]
            if not contains -- $pkg_short $installed_casks
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
    # Surface 5: opencode plugin (node_modules is gitignored)
    # -------------------------------------------------------------------------

    function __drift_opencode
        __drift_section "opencode plugin"

        set -l dir $__drift_config_dir/opencode
        set -l lockfile $dir/pnpm-lock.yaml
        set -l plugin_path $dir/node_modules/@opencode-ai/plugin/package.json

        if not test -f "$lockfile"
            gum style --foreground $p_red "  ✗ opencode/pnpm-lock.yaml not found — skipping"
            return
        end

        # The plugin resolves if node_modules/@opencode-ai/plugin exists.
        # This is the exact failure that breaks every prompt with
        # "Cannot find module '@opencode-ai/plugin'" when node_modules is
        # missing (fresh checkout, git clean -fdx, pnpm store prune).
        set -l found_drift 0

        if not test -f "$plugin_path"
            set found_drift 1
            __drift_item missing "opencode plugin" "@opencode-ai/plugin" \
                "declared in opencode/pnpm-lock.yaml but not installed (node_modules missing)"
            switch "$__drift_action"
                case install
                    if type -q opencode-restore
                        gum spin --spinner dot --spinner.foreground $p_purple \
                            --title "  Restoring opencode plugin..." \
                            -- fish -c "opencode-restore"
                        if test $status -eq 0
                            gum style --foreground $p_green "  ✓ Restored @opencode-ai/plugin"
                        else
                            gum style --foreground $p_red "  ✗ Failed to restore @opencode-ai/plugin"
                        end
                    else
                        gum style --foreground $p_muted \
                            "    → Run: pnpm install --dir ~/.config/opencode"
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
    # Surface 6: model catalog freshness (informational, no install/remove)
    # -------------------------------------------------------------------------
    #
    # Unlike surfaces 1-5, there's no mechanical fix here — deciding whether a
    # newer model is actually a better pick needs judgment (a flashy new
    # release isn't automatically an upgrade for our use case; see the
    # Claude Fable 5 case, a newer/pricier creative-only model that looked
    # like an Opus upgrade but wasn't). So this surface only ever reports.

    function __drift_model_catalog
        __drift_section "model catalog"

        if not type -q opencode-model-catalog-check
            gum style --foreground $p_muted "  ✗ opencode-model-catalog-check function not found — skipping"
            return
        end

        set -l out (opencode-model-catalog-check 2>&1)
        set -l rc $status

        if test $rc -eq 0
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " No drift")
        else if test $rc -eq 2
            for line in $out
                if string match -q '  ▸*' -- $line
                    gum join --horizontal \
                        (gum style --foreground $p_orange "  ▸") \
                        (gum style --foreground $p_fg " "(string sub -s 4 -- $line))
                else if string match -q '  →*' -- $line
                    gum style --foreground $p_muted --faint "    "(string sub -s 4 -- $line)
                end
            end
        else
            gum style --foreground $p_muted "  ✗ check couldn't run — $out"
        end
    end

    # -------------------------------------------------------------------------
    # Surface 7: opencode MCP commands (pnpx → npx + skills binary smoke test)
    # -------------------------------------------------------------------------
    #
    # pnpm 11 switched `pnpm dlx` to a global virtual store. ESM packages
    # (mcp-remote, chrome-devtools-mcp, etc.) hit ERR_MODULE_NOT_FOUND from a
    # store/v11/links/... path that is never created, but ONLY when launched
    # from a non-workspace directory. From ~/.config it happens to work because
    # the nearby opencode/pnpm-workspace.yaml gives pnpm a local virtual store
    # to resolve against, so the bug is invisible until you run `ocv` from a
    # customer dir like ~/vercel/customers/sbs and every pnpx-based MCP fails
    # silently with "Connection closed".
    #
    # We already migrated opencode.json to `npx -y`, so this surface guards
    # against regressions (someone adding a new local MCP with `pnpx`).

    function __drift_mcp_commands
        __drift_section "opencode mcp commands"

        set -l cfg $__drift_config_dir/opencode/opencode.json
        if not test -f "$cfg"
            gum style --foreground $p_red "  ✗ opencode/opencode.json not found — skipping"
            return
        end

        set -l found_drift 0

        # --- Part A: scan for `pnpx` in local MCP commands ---
        # `jq -r` walks every mcp entry; for local ones, print "name|cmd0|cmd1..."
        # so we can detect `pnpx` as the first command token.
        set -l pnpx_entries
        set -l entries_raw (jq -r '
            .mcp // {} | to_entries[]
            | select(.value.type == "local")
            | .key + "\t" + ((.value.command // []) | join(" "))
        ' "$cfg" 2>/dev/null)

        for line in $entries_raw
            set -l parts (string split \t -- $line)
            set -l name $parts[1]
            set -l cmd $parts[2]
            set -l first_token (string split ' ' -- $cmd)[1]
            if test "$first_token" = pnpx
                set pnpx_entries $pnpx_entries $name
            end
        end

        if test (count $pnpx_entries) -gt 0
            set found_drift 1
            for name in $pnpx_entries
                gum join --horizontal \
                    (gum style --foreground $p_orange "  ▸ wrong cmd") \
                    (gum style --foreground $p_fg "  $name") \
                    (gum style --foreground $p_muted "  uses pnpx (broken under pnpm 11 for ESM pkgs)")
                if test "$__drift_interactive" -eq 0
                    gum style --foreground $p_muted --faint "    → report-only (no TTY); fix: change pnpx → npx -y in opencode.json"
                else
                    set -l choice (gum choose \
                        --cursor.foreground $p_purple \
                        --selected.foreground $p_purple \
                        --header "    '$name' uses pnpx. Switch to npx -y?" \
                        --header.foreground $p_muted \
                        "Dismiss  (skip for now)" \
                        "Fix now  (replace pnpx → npx -y in opencode.json)")
                    switch "$choice"
                        case "Fix*"
                            # Replace "pnpx" with "npx -y" in the command array
                            # for this MCP entry. Use jq for a safe in-place edit.
                            set -l tmp (mktemp)
                            if jq --arg mcp "$name" '
                                .mcp[$mcp].command = (
                                    .mcp[$mcp].command | map(
                                        if . == "pnpx" then "npx" else . end
                                    )
                                ) | .mcp[$mcp].command |= (
                                    . as $c
                                    | if $c[0] == "npx" then ["npx","-y"] + $c[1:] else $c end
                                )
                            ' "$cfg" >$tmp 2>/dev/null
                                mv $tmp "$cfg"
                                gum style --foreground $p_green "  ✓ Switched '$name' to npx -y"
                            else
                                rm -f $tmp
                                gum style --foreground $p_red "  ✗ Failed to patch opencode.json"
                            end
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
    # Surface 8: generated files (activation-script-managed configs)
    # -------------------------------------------------------------------------
    #
    # Files like ~/.config/ghostty/config are written by nix activation scripts
    # and should only be edited via the nix module. This surface diffs the
    # on-disk file against the expected content exposed via environment.etc
    # (e.g. /etc/static/ghostty-expected). If they differ, the user either
    # manually edited the generated file or the nix module changed but hasn't
    # been applied yet.
    #
    # To add a new generated file:
    #   1. In the nix module, write the config via pkgs.writeText and expose
    #      it with environment.etc."<name>-expected".source = <file>
    #   2. Add a __drift_generated_file call below with the expected/actual paths

    # Generate a plain-language hint explaining what Migrate vs Discard means
    # for a specific diff. Uses a cheap AI Gateway model (gpt-4o-mini). Prints
    # nothing on any failure (no key, API down, empty response) so the caller
    # falls back seamlessly to the generic gum choose header.
    # Usage: __drift_ai_hint <label> <diff_line1> <diff_line2> ...
    function __drift_ai_hint
        set -l label $argv[1]
        set -l diff_lines $argv[2..-1]

        set -l gw_key $AI_GATEWAY_API_KEY
        if test -z "$gw_key"
            set gw_key (secret-get AI_GATEWAY_API_KEY)
        end

        if test -z "$gw_key"
            return
        end

        set -l sys "You explain config drift resolution in plain language. Given a unified diff for a config file (lines starting with - are the nix-generated original, lines starting with + are the user manual edits), output exactly 3 lines:\nLine 1: Changed: <what the user edited, in plain language>\nLine 2: Migrate = keep <new value> (update nix source to match)\nLine 3: Discard = revert to <old value> (undo your edit)\nIf multiple things changed, combine on line 1 and use your edits on lines 2-3. No em dashes. No markdown. No preamble. Output only the 3 lines."

        set -l req_diff (mktemp)
        printf '%s\n' $diff_lines >$req_diff
        set -l req (mktemp)
        jq -n \
            --arg model "openai/gpt-4o-mini" \
            --arg sys "$sys" \
            --arg label "$label" \
            --rawfile diff "$req_diff" \
            '{model:$model,messages:[{role:"system",content:$sys},{role:"user",content:("Diff for "+$label+":\n"+$diff)}],max_tokens:200,temperature:0.3}' >$req
        rm -f $req_diff

        set -l resp (curl -s --max-time 8 \
            -H "Authorization: Bearer $gw_key" \
            -H "Content-Type: application/json" \
            -d @$req \
            https://ai-gateway.vercel.sh/v1/chat/completions 2>/dev/null)
        rm -f $req

        set -l hint (echo $resp | jq -r '.choices[0].message.content // empty' 2>/dev/null)
        if test (count $hint) -eq 0
            return
        end

        echo
        for line in $hint
            set -l trimmed (string trim -- $line)
            if test -n "$trimmed"
                gum style --foreground $p_cyan "    $trimmed"
            end
        end
        echo
    end

    # Compare a single generated file against its expected content.
    # Usage: __drift_generated_file <label> <expected> <actual> <source>
    # Returns 1 if drift found, 0 if clean (so caller can aggregate).
    function __drift_generated_file
        set -l label $argv[1]
        set -l expected $argv[2]
        set -l actual $argv[3]
        set -l source $argv[4]

        if not test -f "$expected"
            return 0  # No expected file = module not applied yet, skip
        end

        if not test -f "$actual"
            gum join --horizontal \
                (gum style --foreground $p_yellow "  ▸ missing") \
                (gum style --foreground $p_fg "  $label") \
                (gum style --foreground $p_muted "  $actual not found")
            if test "$__drift_interactive" -eq 0
                gum style --foreground $p_muted --faint "    → report-only (no TTY); resolve with: nixx check"
            end
            return 1
        end

        # Compare
        set -l diff_output (diff -u "$expected" "$actual" 2>/dev/null)
        set -l diff_rc $status

        if test $diff_rc -eq 0
            return 0  # No drift
        end

        # Drift detected
        gum join --horizontal \
            (gum style --foreground $p_orange "  ▸ modified") \
            (gum style --foreground $p_fg "  $label") \
            (gum style --foreground $p_muted "  manually edited, diverged from nix-generated content")

        # Show diff with colors (skip --- and +++ header lines)
        for line in $diff_output
            set -l first (string sub -l 1 -- $line)
            switch $first
                case '+'
                    if not string match -q -- '+++*' $line
                        gum style --foreground $p_green "    $line"
                    end
                case '-'
                    if not string match -q -- '---*' $line
                        gum style --foreground $p_red "    $line"
                    end
                case '@'
                    gum style --foreground $p_muted --faint "    $line"
                case '*'
                    if test "$line" != ""
                        gum style --foreground $p_muted "    $line"
                    end
            end
        end

        if test "$__drift_interactive" -eq 0
            gum style --foreground $p_muted --faint "    → report-only (no TTY); resolve with: nixx check"
            return 1
        end

        __drift_ai_hint "$label" $diff_output

        set -l choice (gum choose \
            --cursor.foreground $p_purple \
            --selected.foreground $p_purple \
            --header "    $label diverged from nix. What should happen?" \
            --header.foreground $p_muted \
            "Migrate  (open nix source in nvim to capture changes)" \
            "Discard  (overwrite from nix, lose manual edits)" \
            "Dismiss  (skip for now)")

        switch "$choice"
            case "Migrate*"
                gum style --foreground $p_muted "  → Opening $source in nvim..."
                nvim "$source"
                set -l rebuild (gum choose \
                    --cursor.foreground $p_purple \
                    --selected.foreground $p_purple \
                    --header "    Rebuild and apply now?" \
                    --header.foreground $p_muted \
                    "Yes  (nixx l)" \
                    "No  (I'll do it later)")
                if string match -q "Yes*" -- "$rebuild"
                    nixx l
                end
            case "Discard*"
                cp "$expected" "$actual"
                gum style --foreground $p_green "  ✓ Overwrote $actual from nix"
        end

        return 1
    end

    function __drift_generated
        __drift_section "generated files"

        set -l found_drift 0

        # Ghostty config: nix/modules/ghostty.nix writes ~/.config/ghostty/config
        # via activation script; expected content at /etc/static/ghostty-expected
        __drift_generated_file \
            "ghostty config" \
            /etc/static/ghostty-expected \
            ~/.config/ghostty/config \
            $__drift_nix_dir/modules/ghostty.nix
        or set found_drift 1

        if test $found_drift -eq 0
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " No drift")
        end
    end

    # -------------------------------------------------------------------------

    __drift_header
    __drift_brew
    __drift_pnpm
    __drift_uv
    __drift_opencode
    __drift_model_catalog
    __drift_mcp_commands
    __drift_generated

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
    functions -e __drift_opencode
    functions -e __drift_model_catalog
    functions -e __drift_mcp_commands
    functions -e __drift_generated_file
    functions -e __drift_generated
    set -e __drift_action
    set -e __drift_interactive
    set -e __drift_config_dir
    set -e __drift_nix_dir
end
