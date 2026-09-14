function xv --wraps=fx --description 'fx + 10 work MCPs + work instructions (no args = TUI, prompt args = fx ask --auto, resume flags pass through)'
    _fx_set_profile work
    set -l trace $HOME/.local/share/fx/xv-trace-(date +%Y-%m-%dT%H%M%S).log
    mkdir -p $HOME/.local/share/fx
    ln -sf $trace $HOME/.local/share/fx/trace-latest.log
    switch "$argv[1]"
        case ''
            FX_TRACE=1 FX_TRACE_LOG=$trace fx $argv 2>$trace
        case -c --continue -r --resume --resume-last
            FX_TRACE=1 FX_TRACE_LOG=$trace fx $argv 2>$trace
        case '*'
            FX_TRACE=1 FX_TRACE_LOG=$trace fx ask --auto $argv 2>$trace
    end
end
