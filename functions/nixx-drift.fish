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

    set -l config_dir ~/.config
    set -l nix_dir $config_dir/nix

    # -------------------------------------------------------------------------
    # Helpers
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

        # Declared brews from nix eval
        set -l declared_brews (cd $nix_dir && \
            nix eval ".#darwinConfigurations.$hn.config.homebrew.brews" \
            --extra-experimental-features 'nix-command flakes' \
            --json 2>/dev/null | jq -r '.[].name' 2>/dev/null | sort)

        # Declared casks from nix eval
        set -l declared_casks (cd $nix_dir && \
            nix eval ".#darwinConfigurations.$hn.config.homebrew.casks" \
            --extra-experimental-features 'nix-command flakes' \
            --json 2>/dev/null | jq -r '.[].name' 2>/dev/null | sort)

        if test -z "$declared_brews" -a -z "$declared_casks"
            gum style --foreground $p_red "  ✗ Could not evaluate nix config — skipping brew drift check"
            return
        end

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

        set -l canonical_file $config_dir/pnpm/globals.txt

        if not test -f $canonical_file
            gum style --foreground $p_red "  ✗ $canonical_file not found — skipping"
            return
        end

        # Parse canonical list (strip comments and blank lines)
        set -l declared (grep -v '^\s*#' $canonical_file | grep -v '^\s*$' | sort)

        # Installed pnpm globals (package names only)
        # pnpm list --json returns an array; globals are at index 0
        set -l installed (pnpm list -g --depth=0 --json 2>/dev/null \
            | jq -r '.[0].dependencies | keys[]' 2>/dev/null | sort)

        if test -z "$installed"
            gum style --foreground $p_red "  ✗ Could not read pnpm global packages — skipping"
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

        set -l canonical_file $config_dir/uv/tools.txt

        if not test -f $canonical_file
            gum style --foreground $p_red "  ✗ $canonical_file not found — skipping"
            return
        end

        # Parse canonical list
        set -l declared (grep -v '^\s*#' $canonical_file | grep -v '^\s*$' | sort)

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
    functions -e __drift_header
    functions -e __drift_section
    functions -e __drift_item
    functions -e __drift_confirm_destructive
    functions -e __drift_brew
    functions -e __drift_pnpm
    functions -e __drift_uv
    set -e __drift_action
end
