# nixx-drift - package drift detection and remediation
#
# Scans 7 surfaces for drift between what's declared in config and what's
# actually installed (or, for surface 7, between what nix generates and
# what's on disk). All surfaces are scanned in parallel via the DAG
# scheduler (__nixx_run_dag), then surfaces with drift are resolved
# sequentially with interactive gum prompts.
#
# Surfaces (each runs as a parallel scan task):
#   1. Homebrew brews + casks  <- nix/modules/apps.nix (2 nix evals in parallel)
#   2. pnpm globals            <- pnpm/globals.txt
#   3. uv tools                <- uv/tools.txt
#   4. opencode plugin         <- opencode/pnpm-lock.yaml (node_modules gitignored)
#   5. model catalog           <- opencode/model-catalog.json (informational staleness)
#   6. opencode MCP commands   <- opencode/opencode.json (pnpx guard)
#   7. generated files         <- nix activation scripts (ghostty config diff)
#
# Called directly as `nixx check` / `nixx d`, or invoked from nixx.fish after
# a full update. Returns 0 if no drift found, 1 if any unresolved drift remains.
#
# Scan functions live in __drift_scans.fish (sourced by each DAG subshell).
# Resolve functions (remediation logic) are nested below.

function nixx-drift
    _aldo_dracula_apply_palette

    # NB: these must be GLOBAL, not `set -l`. The __drift_resolve_* helpers
    # below are nested functions and don't inherit locals.
    set -g __drift_config_dir ~/.config
    set -g __drift_nix_dir $__drift_config_dir/nix

    # Interactive TTY guard. gum's choose/confirm need a real terminal; when
    # non-interactive (backgrounded, piped, CI) we run in report-only mode.
    set -g __drift_interactive 1
    if not test -t 0; or not test -t 1
        set -g __drift_interactive 0
    end

    # -------------------------------------------------------------------------
    # Display helpers
    # -------------------------------------------------------------------------

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

    # -------------------------------------------------------------------------
    # Resolve helpers (interactive remediation)
    # -------------------------------------------------------------------------

    # Show a drift item and prompt for action.
    # Usage: __drift_resolve_item <kind> <surface> <name> [extra]
    #   kind:    "extra" (installed, not declared) | "missing" (declared, not installed)
    #   surface: display label (e.g. "brew formula", "pnpm global")
    # Returns via $__drift_action: dismiss | add | remove | install
    function __drift_resolve_item
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

    # Generate a plain-language hint for a config diff using a cheap AI model.
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

    # -------------------------------------------------------------------------
    # Per-surface resolve functions
    # -------------------------------------------------------------------------
    # Each reads structured output (ITEM/ERROR/DIFF/META/MSG lines) from the
    # scan logfile and runs the appropriate remediation.

    # Parse a scan logfile into structured arrays.
    # Sets: $parse_items (ITEM lines), $parse_error (ERROR message or empty),
    #       $parse_diffs (diff lines), $parse_source, $parse_expected, $parse_actual
    function __drift_parse_logfile
        set -g parse_items
        set -g parse_error ""
        set -g parse_diffs
        set -g parse_source ""
        set -g parse_expected ""
        set -g parse_actual ""

        for line in (cat $argv[1] 2>/dev/null)
            set -l p (string split \t -m 1 -- $line)
            set -l prefix $p[1]
            set -l rest $p[2]
            switch $prefix
                case ITEM
                    set -g parse_items $parse_items $line
                case ERROR
                    set -g parse_error $rest
                case DIFF
                    set -g parse_diffs $parse_diffs $rest
                case META
                    set -l kv (string split = -m 1 -- $rest)
                    switch $kv[1]
                        case source
                            set -g parse_source $kv[2]
                        case expected
                            set -g parse_expected $kv[2]
                        case actual
                            set -g parse_actual $kv[2]
                    end
            end
        end
    end

    function __drift_resolve_brew
        set -l logfile $argv[1]
        __drift_section "brew"

        if not test -f "$logfile"
            gum style --foreground $p_red "  ✗ Scan failed (no log file)"
            return
        end

        __drift_parse_logfile $logfile

        if test -n "$parse_error"
            gum style --foreground $p_red "  ✗ $parse_error"
            return
        end

        if test (count $parse_items) -eq 0
            gum style --foreground $p_red "  ✗ Scan failed (no drift data found)"
            return
        end

        for item_line in $parse_items
            set -l f (string split \t -- $item_line)
            set -l kind $f[2]
            set -l type $f[3]
            set -l name $f[4]
            set -l extra $f[5]

            set -l surface
            if test "$type" = brew-formula
                set surface "brew formula"
            else if test "$type" = brew-cask
                set surface "brew cask"
            end

            __drift_resolve_item $kind $surface $name $extra

            switch "$__drift_action"
                case add
                    if test "$type" = brew-formula
                        gum style --foreground $p_muted \
                            "    → Add \"$name\" to commonBrews or a host-specific list in nix/modules/apps.nix, then run nixx l to apply."
                    else if test "$type" = brew-cask
                        gum style --foreground $p_muted \
                            "    → Add \"$name\" to commonCasks or a host-specific list in nix/modules/apps.nix, then run nixx l to apply."
                    end
                case remove
                    if test "$type" = brew-formula
                        if __drift_confirm_destructive "Uninstall brew formula '$name'?"
                            gum spin --spinner dot --spinner.foreground $p_purple \
                                --title "  Uninstalling $name..." \
                                -- fish -c "brew uninstall --formula $name"
                            if test $status -eq 0
                                gum style --foreground $p_green "  ✓ Uninstalled $name"
                            else
                                gum style --foreground $p_red "  ✗ Failed to uninstall $name"
                            end
                        else
                            gum style --foreground $p_muted "  → Skipped"
                        end
                    else if test "$type" = brew-cask
                        if __drift_confirm_destructive "Uninstall cask '$name'? This removes the application."
                            gum spin --spinner dot --spinner.foreground $p_purple \
                                --title "  Uninstalling $name..." \
                                -- fish -c "brew uninstall --cask $name"
                            if test $status -eq 0
                                gum style --foreground $p_green "  ✓ Uninstalled $name"
                            else
                                gum style --foreground $p_red "  ✗ Failed to uninstall $name"
                            end
                        else
                            gum style --foreground $p_muted "  → Skipped"
                        end
                    end
                case install
                    if test "$type" = brew-formula
                        gum spin --spinner dot --spinner.foreground $p_purple \
                            --title "  Installing $name..." \
                            -- fish -c "brew install $name"
                        if test $status -eq 0
                            gum style --foreground $p_green "  ✓ Installed $name"
                        else
                            gum style --foreground $p_red "  ✗ Failed to install $name"
                        end
                    else if test "$type" = brew-cask
                        gum spin --spinner dot --spinner.foreground $p_purple \
                            --title "  Installing $name..." \
                            -- fish -c "brew install --cask $name"
                        if test $status -eq 0
                            gum style --foreground $p_green "  ✓ Installed $name"
                        else
                            gum style --foreground $p_red "  ✗ Failed to install $name"
                        end
                    end
            end
        end
    end

    function __drift_resolve_pnpm
        set -l logfile $argv[1]
        __drift_section "pnpm globals"

        if not test -f "$logfile"
            gum style --foreground $p_red "  ✗ Scan failed (no log file)"
            return
        end

        __drift_parse_logfile $logfile

        if test -n "$parse_error"
            gum style --foreground $p_red "  ✗ $parse_error"
            return
        end

        if test (count $parse_items) -eq 0
            gum style --foreground $p_red "  ✗ Scan failed (no drift data found)"
            return
        end

        set -l canonical_file $__drift_config_dir/pnpm/globals.txt

        for item_line in $parse_items
            set -l f (string split \t -- $item_line)
            set -l kind $f[2]
            set -l name $f[4]
            set -l extra $f[5]

            __drift_resolve_item $kind "pnpm global" $name $extra

            switch "$__drift_action"
                case add
                    echo "    $name" >>$canonical_file
                    gum style --foreground $p_green "  ✓ Added '$name' to pnpm/globals.txt"
                    gum style --foreground $p_muted "  → Remember to commit the change"
                case remove
                    if __drift_confirm_destructive "Uninstall pnpm global '$name'?"
                        gum spin --spinner dot --spinner.foreground $p_purple \
                            --title "  Removing $name..." \
                            -- fish -c "pnpm remove -g $name"
                        if test $status -eq 0
                            gum style --foreground $p_green "  ✓ Removed $name"
                        else
                            gum style --foreground $p_red "  ✗ Failed to remove $name"
                        end
                    else
                        gum style --foreground $p_muted "  → Skipped"
                    end
                case install
                    gum spin --spinner dot --spinner.foreground $p_purple \
                        --title "  Installing $name..." \
                        -- fish -c "pnpm add -g $name"
                    if test $status -eq 0
                        gum style --foreground $p_green "  ✓ Installed $name"
                    else
                        gum style --foreground $p_red "  ✗ Failed to install $name"
                    end
            end
        end
    end

    function __drift_resolve_uv
        set -l logfile $argv[1]
        __drift_section "uv tools"

        if not test -f "$logfile"
            gum style --foreground $p_red "  ✗ Scan failed (no log file)"
            return
        end

        __drift_parse_logfile $logfile

        if test -n "$parse_error"
            gum style --foreground $p_red "  ✗ $parse_error"
            return
        end

        if test (count $parse_items) -eq 0
            gum style --foreground $p_red "  ✗ Scan failed (no drift data found)"
            return
        end

        set -l canonical_file $__drift_config_dir/uv/tools.txt

        for item_line in $parse_items
            set -l f (string split \t -- $item_line)
            set -l kind $f[2]
            set -l name $f[4]
            set -l extra $f[5]

            __drift_resolve_item $kind "uv tool" $name $extra

            switch "$__drift_action"
                case add
                    echo "$name" >>$canonical_file
                    gum style --foreground $p_green "  ✓ Added '$name' to uv/tools.txt"
                    gum style --foreground $p_muted "  → Remember to commit the change"
                case remove
                    if __drift_confirm_destructive "Uninstall uv tool '$name'?"
                        gum spin --spinner dot --spinner.foreground $p_purple \
                            --title "  Removing $name..." \
                            -- fish -c "uv tool uninstall $name"
                        if test $status -eq 0
                            gum style --foreground $p_green "  ✓ Removed $name"
                        else
                            gum style --foreground $p_red "  ✗ Failed to remove $name"
                        end
                    else
                        gum style --foreground $p_muted "  → Skipped"
                    end
                case install
                    gum spin --spinner dot --spinner.foreground $p_purple \
                        --title "  Installing $name..." \
                        -- fish -c "uv tool install $name"
                    if test $status -eq 0
                        gum style --foreground $p_green "  ✓ Installed $name"
                    else
                        gum style --foreground $p_red "  ✗ Failed to install $name"
                    end
            end
        end
    end

    function __drift_resolve_opencode
        set -l logfile $argv[1]
        __drift_section "opencode plugin"

        if not test -f "$logfile"
            gum style --foreground $p_red "  ✗ Scan failed (no log file)"
            return
        end

        __drift_parse_logfile $logfile

        if test -n "$parse_error"
            gum style --foreground $p_red "  ✗ $parse_error"
            return
        end

        if test (count $parse_items) -eq 0
            gum style --foreground $p_red "  ✗ Scan failed (no drift data found)"
            return
        end

        for item_line in $parse_items
            set -l f (string split \t -- $item_line)
            set -l kind $f[2]
            set -l name $f[4]
            set -l extra $f[5]

            __drift_resolve_item $kind "opencode plugin" $name $extra

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
    end

    function __drift_resolve_model_catalog
        set -l logfile $argv[1]
        __drift_section "model catalog"

        if not test -f "$logfile"
            gum style --foreground $p_muted "  ✗ Scan failed (no log file)"
            return
        end

        __drift_parse_logfile $logfile

        if test -n "$parse_error"
            gum style --foreground $p_muted "  ✗ $parse_error"
            return
        end

        # Model catalog uses MSG lines, not ITEM lines
        set -l msg_lines
        for line in (cat $logfile 2>/dev/null)
            set -l p (string split \t -m 1 -- $line)
            if test "$p[1]" = MSG
                set -a msg_lines $p[2]
            end
        end

        if test (count $msg_lines) -eq 0
            gum style --foreground $p_muted "  ✗ No output from model catalog check"
            return
        end

        for msg in $msg_lines
            if string match -q '  ▸*' -- $msg
                gum join --horizontal \
                    (gum style --foreground $p_orange "  ▸") \
                    (gum style --foreground $p_fg " "(string sub -s 4 -- $msg))
            else if string match -q '  →*' -- $msg
                gum style --foreground $p_muted --faint "    "(string sub -s 4 -- $msg)
            end
        end
    end

    function __drift_resolve_mcp
        set -l logfile $argv[1]
        __drift_section "opencode mcp commands"

        if not test -f "$logfile"
            gum style --foreground $p_red "  ✗ Scan failed (no log file)"
            return
        end

        __drift_parse_logfile $logfile

        if test -n "$parse_error"
            gum style --foreground $p_red "  ✗ $parse_error"
            return
        end

        if test (count $parse_items) -eq 0
            gum style --foreground $p_red "  ✗ Scan failed (no drift data found)"
            return
        end

        set -l cfg $__drift_config_dir/opencode/opencode.json

        for item_line in $parse_items
            set -l f (string split \t -- $item_line)
            set -l name $f[4]

            gum join --horizontal \
                (gum style --foreground $p_orange "  ▸ wrong cmd") \
                (gum style --foreground $p_fg "  $name") \
                (gum style --foreground $p_muted "  uses pnpx (broken under pnpm 11 for ESM pkgs)")

            if test "$__drift_interactive" -eq 0
                gum style --foreground $p_muted --faint "    → report-only (no TTY); fix: change pnpx → npx -y in opencode.json"
                continue
            end

            set -l choice (gum choose \
                --cursor.foreground $p_purple \
                --selected.foreground $p_purple \
                --header "    '$name' uses pnpx. Switch to npx -y?" \
                --header.foreground $p_muted \
                "Dismiss  (skip for now)" \
                "Fix now  (replace pnpx → npx -y in opencode.json)")

            switch "$choice"
                case "Fix*"
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

    function __drift_resolve_generated
        set -l logfile $argv[1]
        __drift_section "generated files"

        if not test -f "$logfile"
            gum style --foreground $p_red "  ✗ Scan failed (no log file)"
            return
        end

        __drift_parse_logfile $logfile

        if test -n "$parse_error"
            gum style --foreground $p_red "  ✗ $parse_error"
            return
        end

        if test (count $parse_items) -eq 0
            gum style --foreground $p_red "  ✗ Scan failed (no drift data found)"
            return
        end

        for item_line in $parse_items
            set -l f (string split \t -- $item_line)
            set -l kind $f[2]
            set -l name $f[4]

            if test "$kind" = missing
                gum join --horizontal \
                    (gum style --foreground $p_yellow "  ▸ missing") \
                    (gum style --foreground $p_fg "  $name") \
                    (gum style --foreground $p_muted "  $parse_actual not found")
                if test "$__drift_interactive" -eq 0
                    gum style --foreground $p_muted --faint "    → report-only (no TTY); resolve with: nixx check"
                end
                continue
            end

            # Modified
            gum join --horizontal \
                (gum style --foreground $p_orange "  ▸ modified") \
                (gum style --foreground $p_fg "  $name") \
                (gum style --foreground $p_muted "  manually edited, diverged from nix-generated content")

            # Show diff with colors (skip --- and +++ header lines)
            for line in $parse_diffs
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
                continue
            end

            __drift_ai_hint "$name" $parse_diffs

            set -l choice (gum choose \
                --cursor.foreground $p_purple \
                --selected.foreground $p_purple \
                --header "    $name diverged from nix. What should happen?" \
                --header.foreground $p_muted \
                "Migrate  (open nix source in nvim to capture changes)" \
                "Discard  (overwrite from nix, lose manual edits)" \
                "Dismiss  (skip for now)")

            switch "$choice"
                case "Migrate*"
                    gum style --foreground $p_muted "  → Opening $parse_source in nvim..."
                    nvim "$parse_source"
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
                    cp "$parse_expected" "$parse_actual"
                    gum style --foreground $p_green "  ✓ Overwrote $parse_actual from nix"
            end
        end
    end

    # -------------------------------------------------------------------------
    # Main flow: parallel scan + sequential resolve
    # -------------------------------------------------------------------------

    __drift_header

    # Build DAG tasks for parallel scanning.
    # Format: "section|task_id|label|timeout|dep_ids|hint_pattern|command"
    set -l hn $hostname
    set -l scans_file $__drift_config_dir/fish/functions/__drift_scans.fish
    set -l cd $__drift_config_dir
    set -l nd $__drift_nix_dir

    set -l tasks
    set -a tasks "brew|brew-scan|scanning|120|||source $scans_file; and __drift_scan_brew $cd $nd $hn"
    set -a tasks "pnpm globals|pnpm-scan|scanning|30|||source $scans_file; and __drift_scan_pnpm $cd"
    set -a tasks "uv tools|uv-scan|scanning|15|||source $scans_file; and __drift_scan_uv $cd"
    set -a tasks "opencode plugin|opencode-scan|scanning|10|||source $scans_file; and __drift_scan_opencode $cd"
    set -a tasks "model catalog|model-scan|scanning|30|||source $scans_file; and __drift_scan_model_catalog"
    set -a tasks "opencode mcp commands|mcp-scan|scanning|10|||source $scans_file; and __drift_scan_mcp $cd"
    set -a tasks "generated files|generated-scan|scanning|10|||source $scans_file; and __drift_scan_generated $cd $nd"

    # Surface names in the same order as tasks (for mapping results back)
    set -l surface_names "brew" "pnpm globals" "uv tools" "opencode plugin" "model catalog" "opencode mcp commands" "generated files"

    # Run parallel scan via DAG scheduler (live per-surface display)
    set -g __nixx_results
    echo
    __nixx_run_dag $tasks

    # Sequential resolve: only surfaces that failed (drift or error) get expanded
    set -l any_drift 0

    for i in (seq (count $__nixx_results))
        set -l r (string split "|" $__nixx_results[$i])
        set -l rstatus $r[2]
        set -l logfile $r[4]
        set -l surface $surface_names[$i]

        if test "$rstatus" != "ok"
            set any_drift 1
            switch "$surface"
                case brew
                    __drift_resolve_brew $logfile
                case "pnpm globals"
                    __drift_resolve_pnpm $logfile
                case "uv tools"
                    __drift_resolve_uv $logfile
                case "opencode plugin"
                    __drift_resolve_opencode $logfile
                case "model catalog"
                    __drift_resolve_model_catalog $logfile
                case "opencode mcp commands"
                    __drift_resolve_mcp $logfile
                case "generated files"
                    __drift_resolve_generated $logfile
            end
        end
    end

    # Summary
    echo
    if test $any_drift -eq 0
        gum join --horizontal \
            (gum style --foreground $p_green "  ✓") \
            (gum style --foreground $p_fg " no drift across all surfaces")
    end
    echo

    # Cleanup logfiles
    for r in $__nixx_results
        set -l parts (string split "|" $r)
        if test -n "$parts[4]" -a -f "$parts[4]"
            rm -f "$parts[4]"
        end
    end

    # Cleanup globals and inner functions
    set -e __nixx_results
    set -e __nixx_brew_upgraded_count
    set -e __drift_action
    set -e __drift_interactive
    set -e __drift_config_dir
    set -e __drift_nix_dir
    set -e parse_items
    set -e parse_error
    set -e parse_diffs
    set -e parse_source
    set -e parse_expected
    set -e parse_actual
    functions -e __drift_header
    functions -e __drift_section
    functions -e __drift_resolve_item
    functions -e __drift_confirm_destructive
    functions -e __drift_ai_hint
    functions -e __drift_parse_logfile
    functions -e __drift_resolve_brew
    functions -e __drift_resolve_pnpm
    functions -e __drift_resolve_uv
    functions -e __drift_resolve_opencode
    functions -e __drift_resolve_model_catalog
    functions -e __drift_resolve_mcp
    functions -e __drift_resolve_generated

    if test $any_drift -eq 0
        return 0
    end
    return 1
end
