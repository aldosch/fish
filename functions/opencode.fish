function opencode --wraps=opencode --description 'opencode with theme-mode lock auto-cleared so the theme follows macOS light/dark'
    set -l kv ~/.local/state/opencode/kv.json

    function _opencode_clear_theme_lock
        set -l kv $argv[1]
        test -f "$kv"; or return
        jq -ce 'del(.theme_mode_lock, .theme_mode)' "$kv" > "$kv.tmp" 2>/dev/null && mv "$kv.tmp" "$kv"
    end

    _opencode_clear_theme_lock $kv
    command opencode $argv
    set -l code $status
    _opencode_clear_theme_lock $kv
    functions -e _opencode_clear_theme_lock
    return $code
end
