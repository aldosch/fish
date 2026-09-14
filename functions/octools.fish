# octools - check opencode custom tools the way `opencode mcp ls` checks MCPs
#
# Usage:
#   octools            # global tools (~/.config/opencode/tools) + project .opencode/tools
#   octools --live     # also boot a headless `opencode serve` and verify each tool id
#                      # is registered in a real instance
#
# A tool file is OK when it imports cleanly in bun and every export is a valid
# tool shape (args + description + execute). The --live pass fails when an
# expected id is missing from /experimental/tool/ids.
# Exit 0 = all good, 1 = failures (so `nixx check` can consume it).

function octools --description 'check opencode custom tools: exist, load, registered'
    _aldo_dracula_apply_palette

    set -l script $HOME/.config/fish/scripts/octools-check.ts
    if not test -f $script
        gum style --foreground $p_red "  ✗ fish/scripts/octools-check.ts not found"
        return 2
    end

    if not type -q bun
        gum style --foreground $p_red "  ✗ bun not found (required to validate tool files)"
        return 2
    end

    set -l dirs $HOME/.config/opencode/tools
    # project tools when run inside a repo with a local .opencode dir
    if test -d .opencode/tools
        set dirs $dirs $PWD/.opencode/tools
    end

    set -l live 0
    if contains -- --live $argv; or contains -- -l $argv
        set live 1
    end

    set -l tmpout (mktemp /tmp/octools-XXXXXX)
    set -l rc 0

    if test $live -eq 0
        bun $script $dirs >$tmpout 2>&1
        set rc $status
    else
        # --- live mode: throwaway headless instance + registration check ---
        # sh -c exec so the background PID is the real binary (kill works, no
        # wrapper function holding the output pipe open)
        set -l serve_bin $HOME/.local/bin/opencode
        test -x $serve_bin; or set serve_bin /opt/homebrew/bin/opencode
        set -l port (jot -r 1 4900 4999 2>/dev/null; or echo 4937)
        sh -c "exec '$serve_bin' serve --port $port --hostname 127.0.0.1" >/tmp/octools-serve-$port.log 2>&1 </dev/null &
        set -l serve_pid $last_pid

        set -l tries 0
        while not curl -sf http://127.0.0.1:$port/experimental/tool/ids >/dev/null 2>&1; and test $tries -lt 20
            sleep 0.5
            set tries (math $tries + 1)
        end

        bun $script --live http://127.0.0.1:$port $dirs >$tmpout 2>&1
        set rc $status
        kill $serve_pid 2>/dev/null
        wait $serve_pid 2>/dev/null
    end

    __octools_pretty <$tmpout
    rm -f $tmpout

    if test $rc -eq 0
        if test $live -eq 1
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " all opencode tools load and register")
        else
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " all opencode tools load")
        end
    else if test $rc -eq 2
        gum style --foreground $p_red "  ✗ octools: check could not run (see output above)"
    else
        gum style --foreground $p_red "  ✗ opencode tools have failures"
    end
    return $rc
end

function __octools_pretty
    while read -l line
        set -l parts (string split \t -- $line)
        switch $parts[1]
            case OK
                gum join --horizontal \
                    (gum style --foreground $p_green "  ✓") \
                    (gum style --foreground $p_fg " $parts[2]") \
                    (gum style --foreground $p_muted "  "(string replace $HOME '~' -- $parts[3]))
            case LIVE
                if test "$parts[3]" = registered
                    gum join --horizontal \
                        (gum style --foreground $p_green "  ✓") \
                        (gum style --foreground $p_fg " $parts[2]") \
                        (gum style --foreground $p_muted "  registered in live instance")
                else
                    gum join --horizontal \
                        (gum style --foreground $p_red "  ✗") \
                        (gum style --foreground $p_fg " $parts[2]") \
                        (gum style --foreground $p_red "  NOT registered in live instance")
                end
            case FAIL
                gum join --horizontal \
                    (gum style --foreground $p_red "  ✗") \
                    (gum style --foreground $p_fg " $parts[2]") \
                    (gum style --foreground $p_red "  $parts[4]")
            case ERROR
                gum style --foreground $p_red "  ✗ $parts[2]"
        end
    end
end
