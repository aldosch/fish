function _oc_work_overlay --description 'Set OPENCODE_CONFIG_CONTENT for work MCPs + instructions, then run the given command'
    set -lx OPENCODE_CONFIG_CONTENT '{"instructions":["~/.config/opencode/instructions/research.md","~/.config/opencode/instructions/assistant.md","~/.config/opencode/instructions/email-style.md","~/.config/opencode/instructions/design.md"],"mcp":{"gh_grep":{"enabled":true},"index":{"enabled":true},"notion":{"enabled":true},"slack":{"enabled":true},"email":{"enabled":true},"linear":{"enabled":true},"things":{"enabled":true},"clickstate":{"enabled":true},"excalidraw":{"enabled":true}}}'
    $argv
end
