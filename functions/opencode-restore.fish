# opencode-restore - install opencode plugin deps from the tracked lockfile
#
# Usage:
#   opencode-restore           - pnpm install --frozen-lockfile (reproducible)
#   opencode-restore --update  - pnpm update then install (advances the caret
#                                range within @opencode-ai/plugin's ^1.18.0,
#                                so the plugin tracks the brew-installed CLI
#                                generation without manual bumps)
#
# opencode/tools/research.ts imports @opencode-ai/plugin, which resolves from
# opencode/node_modules/. That dir is gitignored, so a fresh checkout, a
# `git clean -fdx`, or a pnpm store prune leaves the plugin missing and every
# prompt fails with "Cannot find module '@opencode-ai/plugin'". This function
# reinstalls it from opencode/pnpm-lock.yaml (the canonical lockfile, tracked).
#
# Safe to run repeatedly — pnpm install is a no-op when already in sync.
# Called automatically by nixx (full update). Run standalone on a new machine
# after cloning the repo.

function opencode-restore
    if not type -q gum
        echo "Error: gum is not installed. Install with 'brew install gum'"
        return 1
    end

    if not type -q pnpm
        echo "Error: pnpm not found. Ensure Node.js + corepack are installed."
        return 1
    end

    _aldo_dracula_apply_palette

    set -l do_update 0
    for arg in $argv
        switch $arg
            case --update -u
                set do_update 1
        end
    end

    set -l dir "$HOME/.config/opencode"

    if not test -f "$dir/pnpm-lock.yaml"
        gum style --foreground $p_red "  ✗ No pnpm-lock.yaml in $dir — nothing to restore from"
        return 1
    end

    if not test -f "$dir/package.json"
        gum style --foreground $p_red "  ✗ No package.json in $dir"
        return 1
    end

    # --- header ---
    echo
    gum style --bold --foreground $p_purple --border rounded --border-foreground $p_purple \
        --padding "0 2" --align center \
        "opencode-restore" \
        (gum style --faint --foreground $p_muted "installing plugin deps from pnpm-lock.yaml")
    echo

    # --- optional update step: advance the caret range within ^1.18.0 ---
    if test $do_update -eq 1
        set -l u_label "Updating @opencode-ai/plugin"
        set -l u_log (mktemp /tmp/opencode-restore-update-XXXXXX)
        set -l u_exit {$u_log}.exit

        fish -c "pnpm update --dir $dir >$u_log 2>&1; echo \$status >$u_exit" &
        set -l u_pid $last_pid

        gum spin --spinner dot \
            --spinner.foreground $p_purple \
            --title.foreground $p_muted \
            --title "  $u_label" \
            -- fish -c "while not test -f $u_exit; sleep 0.2; end"

        wait $u_pid 2>/dev/null
        set -l u_rc (string trim (cat $u_exit 2>/dev/null; or echo 1))
        rm -f $u_log $u_exit

        if test $u_rc -eq 0
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " $u_label")
        else
            gum join --horizontal \
                (gum style --foreground $p_red "  ✗") \
                (gum style --foreground $p_fg " $u_label")
        end
    end

    # --- install from lockfile ---
    set -l label "Installing opencode plugin deps"
    set -l t_start (date +%s)
    set -l tmplog (mktemp /tmp/opencode-restore-XXXXXX)
    set -l exitfile {$tmplog}.exit

    # --frozen-lockfile when not updating: fail rather than mutate the lockfile,
    # so a drifted lockfile is loud instead of silently "fixed".
    set -l frozen_flag "--frozen-lockfile"
    if test $do_update -eq 1
        set frozen_flag ""
    end

    fish -c "pnpm install --dir $dir $frozen_flag >$tmplog 2>&1; echo \$status >$exitfile" &
    set -l bg_pid $last_pid

    # spinner while running
    set -l frames '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'
    set -l n_frames (count $frames)
    set -l i 1
    printf '\033[?25l'
    while not test -f $exitfile
        set -l frame $frames[$i]
        printf '\r\033[K%s' (gum join --horizontal \
            (gum style --foreground $p_purple " $frame") \
            (gum style --foreground $p_muted "  $label..."))
        set i (math "($i % $n_frames) + 1")
        sleep 0.1
    end
    printf '\r\033[K'
    printf '\033[?25h'

    wait $bg_pid 2>/dev/null
    set -l exit_code (string trim (cat $exitfile 2>/dev/null; or echo 1))
    set -l t_end (date +%s)
    set -l elapsed (math "$t_end - $t_start")
    if test $elapsed -lt 60
        set elapsed_str "$elapsed"s
    else
        set elapsed_str (math "floor($elapsed / 60)")m(math "$elapsed % 60")s
    end

    if test "$exit_code" = "0"
        # read installed plugin version for the summary line
        set -l plug_ver ""
        if test -f "$dir/node_modules/@opencode-ai/plugin/package.json"
            set plug_ver (grep -m1 '"version"' "$dir/node_modules/@opencode-ai/plugin/package.json" | string replace -ra '[^0-9.]' '' | string trim)
        end
        set -l detail "($elapsed_str"
        if test -n "$plug_ver"
            set detail "$detail · @opencode-ai/plugin@$plug_ver"
        end
        set detail "$detail)"
        gum join --horizontal \
            (gum style --foreground $p_green "  ✓") \
            (gum style --foreground $p_fg " Plugin deps installed") \
            (gum style --foreground $p_muted " $detail")
        rm -f $tmplog $exitfile
        return 0
    else
        gum join --horizontal \
            (gum style --foreground $p_red "  ✗") \
            (gum style --foreground $p_fg " Install failed") \
            (gum style --foreground $p_muted " ($elapsed_str)")
        gum style --foreground $p_muted --faint "    log: $tmplog"
        rm -f $exitfile
        return 1
    end
end
