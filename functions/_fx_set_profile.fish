function _fx_set_profile --description 'Point ~/.fx/mcp.json and ~/.fx/AGENTS.md at the fx base or work profile'
    set -l mode $argv[1]
    mkdir -p $HOME/.fx $HOME/.config/fx
    switch $mode
        case work
            ln -sfn $HOME/.config/fx/mcp.work.json $HOME/.fx/mcp.json
            cat $HOME/.config/opencode/instructions/research.md \
                $HOME/.config/opencode/instructions/assistant.md \
                $HOME/.config/opencode/instructions/email-style.md \
                $HOME/.config/opencode/instructions/design.md > $HOME/.fx/AGENTS.md
        case base
            ln -sfn $HOME/.config/fx/mcp.json $HOME/.fx/mcp.json
            ln -sfn $HOME/.config/fx/AGENTS.md $HOME/.fx/AGENTS.md
    end
end
