# nixx - system update and build tool
#
#  - nixx        - full update: nix, pnpm globals, brew (sudo auth upfront)
#  - nixx l      - build and apply using current lock file (no updates)
#  - nixx locked - same as nixx l
#  - nixx b      - build only (no apply, no updates)
#  - nixx a      - apply only (assumes already built)
#
# Flags:
#  -v / --verbose  - show full command output instead of spinners


function nixx
    # --- gum guard ---
    if not type -q gum
        echo "Error: gum is not installed. Install with 'brew install gum'"
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

    # --- helper: format elapsed time ---
    function __nixx_fmt_time
        set -l secs $argv[1]
        if test $secs -lt 60
            echo {$secs}s
        else
            set -l mins (math "floor($secs / 60)")
            set -l rem (math "$secs % 60")
            echo {$mins}m\ {$rem}s
        end
    end

    # --- helper: manual spinner with live hint from a log file ---
    # Usage: __nixx_spin_with_hint <logfile> <exitfile> <label>
    # Reads <logfile> for "==> Upgrading <pkg>" lines and updates the spinner.
    # Runs until <exitfile> exists (written by the background process).
    function __nixx_spin_with_hint
        set -l logfile $argv[1]
        set -l exitfile $argv[2]
        set -l label $argv[3]
        set -l frames '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'
        set -l n_frames (count $frames)
        set -l i 1
        set -l hint ""

        # hide cursor
        printf '\033[?25l'

        while not test -f $exitfile
            # parse latest "==> Upgrading <pkg>" hint from log
            if test -f $logfile
                set -l pkg (grep '==> Upgrading ' $logfile 2>/dev/null | tail -1 | string replace -r '^==> Upgrading ' '')
                if test -n "$pkg"
                    set hint (string trim $pkg)
                end
            end

            set -l frame $frames[$i]
            if test -n "$hint"
                set -l line (gum join --horizontal \
                    (gum style --foreground $p_purple " $frame") \
                    (gum style --foreground $p_muted "  $label") \
                    (gum style --foreground $p_muted --faint " · $hint"))
            else
                set -l line (gum join --horizontal \
                    (gum style --foreground $p_purple " $frame") \
                    (gum style --foreground $p_muted "  $label"))
            end
            printf '\r\033[K%s' $line

            set i (math "($i % $n_frames) + 1")
            sleep 0.1
        end

        # clear spinner line
        printf '\r\033[K'
        # restore cursor
        printf '\033[?25h'
    end

    # --- helper: run a step ---
    # Usage: __nixx_step <label> <command string...>
    function __nixx_step
        set -l label $argv[1]
        set -l cmd (string join " " $argv[2..-1])

        set -l t_start (date +%s)
        set -l status_code 0

        if test "$__nixx_verbose" -eq 1
            echo
            gum style --foreground $p_muted --bold "  $label"
            echo
            eval $cmd
            set status_code $status
        else
            gum spin --spinner dot \
                --spinner.foreground $p_purple \
                --title.foreground $p_muted \
                --title "  $label" \
                -- fish -c "$cmd" >/dev/null 2>&1
            set status_code $status
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
            set -g __nixx_results $__nixx_results "$label|ok|$elapsed_str"
        else
            if test "$__nixx_verbose" -eq 1
                echo
                gum join --horizontal \
                    (gum style --foreground $p_red --bold "  ✗ Failed") \
                    (gum style --foreground $p_muted " ($elapsed_str)")
            else
                gum join --horizontal \
                    (gum style --foreground $p_red "  ✗") \
                    (gum style --foreground $p_fg " $label") \
                    (gum style --foreground $p_muted " ($elapsed_str)")
            end
            set -g __nixx_results $__nixx_results "$label|fail|$elapsed_str"
        end
    end

    # --- helper: run brew upgrade with live package hints ---
    function __nixx_brew_upgrade
        set -l label "Upgrading Homebrew packages"
        set -l t_start (date +%s)
        set -l status_code 0

        if test "$__nixx_verbose" -eq 1
            echo
            gum style --foreground $p_muted --bold "  $label"
            echo
            brew upgrade
            set status_code $status
        else
            set -l tmplog (mktemp /tmp/nixx-brew-XXXXXX)
            set -l exitfile {$tmplog}.exit

            # run brew upgrade in background; write exit code to exitfile when done
            fish -c "brew upgrade >$tmplog 2>&1; echo \$status >$exitfile" &
            set -l brew_pid $last_pid

            # show live spinner with hints (blocks until exitfile appears)
            __nixx_spin_with_hint $tmplog $exitfile $label

            # wait for brew to fully finish (should already be done)
            wait $brew_pid 2>/dev/null
            set status_code (string trim (cat $exitfile 2>/dev/null; or echo 1))

            # count upgraded packages from log
            set -l raw_count (grep -c '==> Upgrading ' $tmplog 2>/dev/null)
            if test -n "$raw_count"
                set -g __nixx_brew_upgraded_count (string trim $raw_count)
            else
                set -g __nixx_brew_upgraded_count 0
            end

            rm -f $tmplog $exitfile
        end

        set -l t_end (date +%s)
        set -l elapsed (math "$t_end - $t_start")
        set -l elapsed_str (__nixx_fmt_time $elapsed)

        if test "$status_code" = "0"
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " $label") \
                (gum style --foreground $p_muted " ($elapsed_str)")
            set -g __nixx_results $__nixx_results "$label|ok|$elapsed_str"
        else
            gum join --horizontal \
                (gum style --foreground $p_red "  ✗") \
                (gum style --foreground $p_fg " $label") \
                (gum style --foreground $p_muted " ($elapsed_str)")
            set -g __nixx_results $__nixx_results "$label|fail|$elapsed_str"
        end
    end

    # --- init tracking ---
    set -g __nixx_results
    set -g __nixx_brew_upgraded_count 0
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

    # --- sudo pre-auth for modes that need it ---
    switch "$mode"
        case a l locked '' '*'
            echo
            gum style --foreground $p_orange "  ▸ Authenticating (sudo)..."
            sudo -v 2>/dev/null
            if test $status -ne 0
                gum style --foreground $p_red "  ✗ sudo authentication failed"
                # cleanup
                set -e __nixx_verbose
                set -e __nixx_results
                set -e __nixx_brew_upgraded_count
                functions -e __nixx_step
                functions -e __nixx_fmt_time
                functions -e __nixx_spin_with_hint
                functions -e __nixx_brew_upgrade
                return 1
            end
    end

    # --- pre-expand hostname and extra_args for command strings ---
    set -l hn $hostname
    set -l ea (string join " " $extra_args)

    # --- execute based on mode ---
    switch "$mode"
        case b
            echo
            gum style --foreground $p_cyan --bold "⚙  Nix Build"
            __nixx_step "Building nix configuration" \
                "cd ~/.config/nix && nix build '.#darwinConfigurations.$hn.system' --extra-experimental-features 'nix-command flakes' $ea"

        case a
            echo
            gum style --foreground $p_cyan --bold "⚙  Nix Apply"
            __nixx_step "Applying nix configuration" \
                "cd ~/.config/nix && sudo -E ./result/sw/bin/darwin-rebuild switch --flake '.#$hn'"
            __nixx_step "Collecting nix garbage" \
                "nix-collect-garbage -d"
            __nixx_step "Cleaning up Homebrew" \
                "brew cleanup"

        case l locked
            echo
            gum style --foreground $p_cyan --bold "⚙  Nix Build + Apply (locked)"
            __nixx_step "Building nix configuration" \
                "cd ~/.config/nix && nix build '.#darwinConfigurations.$hn.system' --extra-experimental-features 'nix-command flakes' $ea"
            __nixx_step "Applying nix configuration" \
                "cd ~/.config/nix && sudo -E ./result/sw/bin/darwin-rebuild switch --flake '.#$hn'"
            __nixx_step "Collecting nix garbage" \
                "nix-collect-garbage -d"
            __nixx_step "Cleaning up Homebrew" \
                "brew cleanup"

        case '*'
            # --- nix ---
            echo
            gum style --foreground $p_cyan --bold "⚙  Nix"
            __nixx_step "Updating nix flake" \
                "cd ~/.config/nix && nix flake update"
            __nixx_step "Building nix configuration" \
                "cd ~/.config/nix && nix build '.#darwinConfigurations.$hn.system' --extra-experimental-features 'nix-command flakes' $ea"
            __nixx_step "Applying nix configuration" \
                "cd ~/.config/nix && sudo -E ./result/sw/bin/darwin-rebuild switch --flake '.#$hn'"
            __nixx_step "Collecting nix garbage" \
                "nix-collect-garbage -d"

            # --- neovim ---
            echo
            gum style --foreground $p_cyan --bold "⚙  Neovim"
            __nixx_step "Updating neovim plugins" \
                "nvim --headless '+Lazy! sync' +qa"

            # --- agent skills ---
            echo
            gum style --foreground $p_cyan --bold "⚙  Agent Skills"
            __nixx_step "Updating agent skills" \
                "npx skills update -g -y"

            # --- claude ---
            echo
            gum style --foreground $p_cyan --bold "⚙  Claude"
            __nixx_step "Installing/updating Claude" \
                "curl -fsSL https://claude.ai/install.sh | bash"

            # --- node ---
            echo
            gum style --foreground $p_cyan --bold "⚙  Node"
            __nixx_step "Installing latest Node (fnm)" \
                "fnm install --lts && fnm default lts-latest"
            __nixx_step "Updating pnpm (corepack)" \
                "corepack prepare pnpm@latest --activate"
            __nixx_step "Updating pnpm globals" \
                "pnpm update -g"

            # --- python tools ---
            echo
            gum style --foreground $p_cyan --bold "⚙  Python Tools"
            __nixx_step "Updating uv tools" \
                "uv tool upgrade --all"

            # --- brew ---
            echo
            gum style --foreground $p_cyan --bold "⚙  Homebrew"
            __nixx_step "Updating Homebrew" \
                "brew update"
            __nixx_brew_upgrade
            __nixx_step "Cleaning up Homebrew" \
                "brew cleanup"
    end

    # --- summary ---
    # (printed before drift check so the full-update summary is visible, then
    #  drift check runs interactively below it)
    set -l total_end (date +%s)
    set -l total_elapsed (math "$total_end - $total_start")
    set -l total_elapsed_str (__nixx_fmt_time $total_elapsed)

    set -l fail_count 0
    set -l pass_count 0
    for r in $__nixx_results
        set -l parts (string split "|" $r)
        if test "$parts[2]" = ok
            set pass_count (math $pass_count + 1)
        else
            set fail_count (math $fail_count + 1)
        end
    end

    set -l total_count (math $pass_count + $fail_count)

    # build summary detail line
    set -l detail_parts
    if test "$__nixx_brew_upgraded_count" -gt 0
        set -a detail_parts "$__nixx_brew_upgraded_count packages upgraded"
    end
    if test $fail_count -gt 0
        set -a detail_parts "$fail_count step failed"
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
    echo

    # --- cleanup ---
    set -e __nixx_verbose
    set -e __nixx_results
    set -e __nixx_brew_upgraded_count
    functions -e __nixx_step
    functions -e __nixx_fmt_time
    functions -e __nixx_spin_with_hint
    functions -e __nixx_brew_upgrade

    # --- drift check (full update only) ---
    switch "$mode"
        case '' '*'
            nixx-drift

            # --- publish public dotfiles (full update only) ---
            # Syncs the public-safe subset of ~/.config to its GitHub repos.
            # Shows a diff + confirms before pushing; secret-scan gates every repo.
            if type -q publish-dots
                publish-dots
            end
    end

    if test $fail_count -gt 0
        return 1
    end
end
