function opencode --wraps=opencode --description 'opencode with theme-mode lock auto-cleared so the theme follows macOS light/dark'
    set -l kv ~/.local/state/opencode/kv.json

    function _opencode_clear_theme_lock
        set -l kv $argv[1]
        test -f "$kv"; or return
        jq -ce 'del(.theme_mode_lock, .theme_mode)' "$kv" > "$kv.tmp" 2>/dev/null && mv "$kv.tmp" "$kv"
    end

    # Prefer the patched local build (~/.local/bin/opencode, from
    # ~/repos/opencode branch aldo/patches-v1.18.30 via opencode-sync). Brew
    # (/opt/homebrew/bin/opencode) stays as the fallback when no local build
    # exists. Built with bun 1.3.14 (the repo's pinned bun) — a bun 1.4.x
    # build crashes every prompt (LayerNode chunk-split init order).
    if test -x ~/.local/bin/opencode
        set -l bin ~/.local/bin/opencode
        _opencode_clear_theme_lock $kv
        command $bin $argv
        set -l code $status
        _opencode_clear_theme_lock $kv
        functions -e _opencode_clear_theme_lock
        return $code
    end

    _opencode_clear_theme_lock $kv
    command /opt/homebrew/bin/opencode $argv
    set -l code $status
    _opencode_clear_theme_lock $kv
    functions -e _opencode_clear_theme_lock
    return $code
end
