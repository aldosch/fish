# dotfiles-health - background health check for dotfiles drift
#
# Runs lightweight, sudo-free checks and applies safe auto-fixes.
# Writes results to ~/.local/state/dotfiles/notices.json for the MOTD
# (conf.d/dotfiles-motd.fish) to pick up on shell launch. Logs to
# ~/Library/Logs/dotfiles-health.log.
#
# Called by:
#   - LaunchAgent com.aldo.dotfiles-health (every 4h + RunAtLoad)
#   - `dot refresh` (interactive, from a terminal)
#
# Auto-fix policy (sudo-free, non-destructive only):
#   missing pnpm global  -> pnpm add -g        (canonical list is truth)
#   missing uv tool      -> uv tool install     (same)
#   missing opencode pkg -> opencode-restore    (idempotent, from lockfile)
#   stale generated file -> cp expected actual  (activation script should've)
#   manual edit of gen   -> notice only         (needs your decision)
#   extra packages       -> notice only         (cleanup=zap on next apply)
#   git dirty / unpushed -> notice only
#
# The MOTD message is a simple hardcoded string, rotated from a small set.

function dotfiles-health
    _aldo_dracula_apply_palette

    set -l state_dir ~/.local/state/dotfiles
    mkdir -p $state_dir
    set -l notices_file $state_dir/notices.json
    set -l log_file ~/Library/Logs/dotfiles-health.log
    mkdir -p (dirname $log_file)

    # Items collected as JSON object strings (one per line)
    set -g __dot_items
    set -g __dot_auto_fixed 0
    set -g __dot_log_file $log_file

    set -l t_start (date +%s)
    echo "["(date '+%Y-%m-%d %H:%M:%S')"] dotfiles-health started" >>$log_file

    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    # Add a notice item. Args: surface kind name summary auto_fixed(0|1)
    function __dot_add
        set -l af false
        test "$argv[5]" = 1; and set af true
        set -l obj (jq -c -n \
            --arg surface "$argv[1]" \
            --arg kind "$argv[2]" \
            --arg name "$argv[3]" \
            --arg summary "$argv[4]" \
            --argjson auto_fixed $af \
            '{surface:$surface,kind:$kind,name:$name,summary:$summary,auto_fixed:$auto_fixed}')
        set -g __dot_items $__dot_items "$obj"
        if test "$argv[5]" = 1
            set -g __dot_auto_fixed (math $__dot_auto_fixed + 1)
        end
    end

    function __dot_log
        echo "["(date '+%Y-%m-%d %H:%M:%S')"] $argv" >>$__dot_log_file
    end

    # Parse a canonical package list: strip comments and blanks, sort.
    function __dot_parse_list
        for line in (cat $argv[1] 2>/dev/null)
            set -l t (string trim -- $line)
            test -z "$t"; and continue
            string match -q -- '#*' $t; and continue
            echo $t
        end | sort
    end

    # -------------------------------------------------------------------------
    # Check: pnpm globals
    # -------------------------------------------------------------------------
    function __dot_check_pnpm
        set -l canonical ~/.config/pnpm/globals.txt
        test -f "$canonical"; or return

        set -l declared (__dot_parse_list $canonical)
        test -n "$declared"; or return

        set -l pnpm_out (pnpm list -g --depth=0 --json 2>/dev/null)
        if test $status -ne 0
            __dot_log "pnpm: list failed, skipping"
            return
        end
        set -l installed (echo $pnpm_out | jq -r '.[0].dependencies | keys[]' 2>/dev/null | sort)
        test -n "$installed"; or return

        for pkg in $declared
            if not contains -- $pkg $installed
                __dot_log "pnpm: auto-installing missing global '$pkg'"
                fish -c "pnpm add -g $pkg" >/dev/null 2>&1
                if test $status -eq 0
                    __dot_add "pnpm globals" "missing" "$pkg" "installed $pkg (was in globals.txt but not installed)" 1
                else
                    __dot_add "pnpm globals" "missing" "$pkg" "$pkg in globals.txt but install failed" 0
                end
            end
        end

        for pkg in $installed
            if not contains -- $pkg $declared
                __dot_add "pnpm globals" "extra" "$pkg" "$pkg installed but not in globals.txt" 0
            end
        end
    end

    # -------------------------------------------------------------------------
    # Check: uv tools
    # -------------------------------------------------------------------------
    function __dot_check_uv
        set -l canonical ~/.config/uv/tools.txt
        test -f "$canonical"; or return

        set -l declared (__dot_parse_list $canonical)
        test -n "$declared"; or return

        set -l installed (uv tool list 2>/dev/null | grep -v '^-' | grep -v '^\s*$' | awk '{print $1}' | sort)
        if test -z "$installed" -a (count $declared) -gt 0
            __dot_log "uv: tool list empty, skipping"
            return
        end

        for pkg in $declared
            if not contains -- $pkg $installed
                __dot_log "uv: auto-installing missing tool '$pkg'"
                fish -c "uv tool install $pkg" >/dev/null 2>&1
                if test $status -eq 0
                    __dot_add "uv tools" "missing" "$pkg" "installed $pkg (was in tools.txt but not installed)" 1
                else
                    __dot_add "uv tools" "missing" "$pkg" "$pkg in tools.txt but install failed" 0
                end
            end
        end

        for pkg in $installed
            if not contains -- $pkg $declared
                __dot_add "uv tools" "extra" "$pkg" "$pkg installed but not in tools.txt" 0
            end
        end
    end

    # -------------------------------------------------------------------------
    # Check: opencode plugin
    # -------------------------------------------------------------------------
    function __dot_check_opencode
        set -l plugin ~/.config/opencode/node_modules/@opencode-ai/plugin/package.json
        if test -f "$plugin"
            return
        end

        __dot_log "opencode: plugin missing, auto-restoring"
        if type -q opencode-restore
            fish -c "opencode-restore" >/dev/null 2>&1
            if test $status -eq 0
                __dot_add "opencode plugin" "missing" "@opencode-ai/plugin" "restored from lockfile (node_modules was missing)" 1
            else
                __dot_add "opencode plugin" "missing" "@opencode-ai/plugin" "opencode-restore failed, run manually" 0
            end
        else
            __dot_add "opencode plugin" "missing" "@opencode-ai/plugin" "opencode-restore not found, run: pnpm install --dir ~/.config/opencode" 0
        end
    end

    # -------------------------------------------------------------------------
    # Check: generated files (ghostty config)
    # -------------------------------------------------------------------------
    # If expected is newer than actual AND they differ -> stale apply, auto-fix.
    # If actual is newer than expected AND they differ -> manual edit, notice.
    function __dot_check_ghostty
        set -l expected /etc/static/ghostty-expected
        set -l actual ~/.config/ghostty/config

        test -f "$expected"; or return
        test -f "$actual"; or return

        diff -q "$expected" "$actual" >/dev/null 2>&1; and return

        set -l exp_mtime (stat -L -f %m "$expected" 2>/dev/null; or echo 0)
        set -l act_mtime (stat -f %m "$actual" 2>/dev/null; or echo 0)

        if test "$exp_mtime" -gt "$act_mtime"
            __dot_log "ghostty: expected newer than actual, auto-fixing stale apply"
            cp "$expected" "$actual"
            if test $status -eq 0
                __dot_add "ghostty config" "stale" "ghostty config" "synced from nix (was stale, activation script hadn't run)" 1
            else
                __dot_add "ghostty config" "stale" "ghostty config" "cp failed, run: nixx a" 0
            end
        else
            __dot_add "ghostty config" "modified" "ghostty config" "manually edited, diverged from nix. migrate into nix or discard" 0
        end
    end

    # -------------------------------------------------------------------------
    # Check: git status of ~/.config
    # -------------------------------------------------------------------------
    function __dot_check_git
        set -l repo ~/.config

        set -l dirty (git -C "$repo" status --porcelain 2>/dev/null)
        if test -n "$dirty"
            set -l count (echo $dirty | wc -l | string trim)
            __dot_add "git repo" "dirty" "~/.config" "$count uncommitted file(s) in the config repo" 0
        end

        set -l unpushed (git -C "$repo" log --oneline @{u}..HEAD 2>/dev/null)
        if test -n "$unpushed"
            set -l count (echo $unpushed | wc -l | string trim)
            __dot_add "git repo" "unpushed" "~/.config" "$count unpushed commit(s)" 0
        end
    end

    # -------------------------------------------------------------------------
    # Check: heal backlog (documented issues awaiting fix)
    # -------------------------------------------------------------------------
    function __dot_check_heal_backlog
        set -l backlog ~/.local/state/dotfiles/heal-backlog.md
        if not test -f "$backlog"; or not test -s "$backlog"
            return
        end
        set -l count (grep -c '^## ' "$backlog" 2>/dev/null)
        if test "$count" -gt 0
            __dot_add "heal backlog" "documented" "heal backlog" \
                "$count documented issue(s) awaiting fix (dot heal)" 0
        end
    end

    # -------------------------------------------------------------------------
    # Pick a simple MOTD message
    # -------------------------------------------------------------------------
    function __dot_generate_message
        set -l item_count (count $__dot_items)
        if test $item_count -eq 0
            echo ""
            return
        end

        set -l msgs \
            "stuff needs attention" \
            "config drifted a bit" \
            "some things to fix" \
            "needs a look tbh" \
            "couple things drifted" \
            "config needs a check"
        set -l idx (random 1 (count $msgs))
        echo $msgs[$idx]
    end

    # -------------------------------------------------------------------------
    # Run all checks
    # -------------------------------------------------------------------------
    __dot_check_pnpm
    __dot_check_uv
    __dot_check_opencode
    __dot_check_ghostty
    __dot_check_git
    __dot_check_heal_backlog

    # -------------------------------------------------------------------------
    # Generate message
    # -------------------------------------------------------------------------
    set -l message (__dot_generate_message)

    # -------------------------------------------------------------------------
    # Write notices.json
    # -------------------------------------------------------------------------
    set -l item_count (count $__dot_items)

    if test $item_count -eq 0
        jq -n \
            --arg generated_at (date -u +%Y-%m-%dT%H:%M:%S) \
            '{items:[],message:"",count:0,auto_fixed_count:0,generated_at:$generated_at,last_shown:null}' >$notices_file
    else
        set -l items_json (printf '%s\n' $__dot_items | jq -s '.')

        jq -n \
            --argjson items "$items_json" \
            --arg message "$message" \
            --arg generated_at (date -u +%Y-%m-%dT%H:%M:%S) \
            --argjson auto_fixed $__dot_auto_fixed \
            --argjson count $item_count \
            '{items:$items,message:$message,count:$count,auto_fixed_count:$auto_fixed,generated_at:$generated_at,last_shown:null}' >$notices_file
    end

    # -------------------------------------------------------------------------
    # Log + interactive output
    # -------------------------------------------------------------------------
    set -l t_end (date +%s)
    set -l elapsed (math $t_end - $t_start)
    __dot_log "complete: $item_count notices, $__dot_auto_fixed auto-fixed, $elapsed sec"

    if test -t 1
        echo
        if test $item_count -eq 0
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " all good, no drift")
        else
            gum join --horizontal \
                (gum style --foreground $p_muted "  · ") \
                (gum style --foreground $p_fg "$message")
            echo
            gum join --horizontal \
                (gum style --foreground $p_muted "    → run: ") \
                (gum style --foreground $p_cyan --bold "dotfix")
            if test $__dot_auto_fixed -gt 0
                gum style --foreground $p_muted --faint "    ($__dot_auto_fixed auto-fixed, $item_count total)"
            end
        end
        echo
    end

    # -------------------------------------------------------------------------
    # Cleanup
    # -------------------------------------------------------------------------
    set -e __dot_items
    set -e __dot_auto_fixed
    set -e __dot_log_file
    functions -e __dot_add
    functions -e __dot_log
    functions -e __dot_parse_list
    functions -e __dot_check_pnpm
    functions -e __dot_check_uv
    functions -e __dot_check_opencode
    functions -e __dot_check_ghostty
    functions -e __dot_check_git
    functions -e __dot_check_heal_backlog
    functions -e __dot_generate_message
end
