# Recursively kill a process and all its descendants.
# Usage: __nixx_kill_tree <pid> [SIGNAL]
#
# Job control is frequently disabled under `fish -c` (e.g. when nixx itself is
# invoked non-interactively), so a process-group kill (kill -PID) is unreliable.
# Walk the tree with pgrep and kill children first, then the parent.
#
# Lives in its own autoloadable file so the watchdog subshells spawned by
# `nixx` (`fish -c "..."`) can resolve it via fish's function autoloading.
function __nixx_kill_tree
    set -l pid $argv[1]
    set -l sig TERM
    if set -q argv[2]
        set sig $argv[2]
    end
    test -n "$pid"; or return 0
    for child in (pgrep -P $pid 2>/dev/null)
        __nixx_kill_tree $child $sig
    end
    kill -$sig $pid 2>/dev/null
end
