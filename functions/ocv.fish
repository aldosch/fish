function ocv --wraps=opencode --description 'opencode + work MCPs (no args = TUI) or opencode run --auto with a prompt'
    set -l log $HOME/.local/share/opencode/log/ocv-debug-(date +%Y-%m-%dT%H%M%S).log
    ln -sf $log $HOME/.local/share/opencode/log/debug-latest.log
    if test (count $argv) -eq 0
        _oc_work_overlay opencode --log-level DEBUG --print-logs 2>$log
    else
        _oc_work_overlay opencode --log-level DEBUG --print-logs run --agent build --auto (string join " " $argv) 2>$log
    end
end
