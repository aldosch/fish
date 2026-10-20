# is-dark - exit 0 when the effective appearance is dark, 1 when light
#
# Tiered detection:
#   1. Interactive ghostty shells: ask the terminal itself (OSC 11, via
#      _aldo_terminal_bg). Ground truth: reflects the real window theme
#      even when it disagrees with macOS appearance, works over SSH.
#   2. Everyone else: osascript, which reports the effective appearance.
#      `defaults read -g AppleInterfaceStyle` is NOT reliable when
#      appearance is set to Auto: the key stays "Dark" during the light
#      period. osascript follows the effective mode.
#   3. Last resort (headless, System Events unavailable): the defaults
#      key, correct whenever Auto is off.
#
# Prints nothing. Use it in conditionals: `if is-dark ... end`.

function is-dark --description "exit 0 when the effective appearance is dark"
    set -l bg (_aldo_terminal_bg)
    if set -q bg[1]
        test "$bg" = dark
        return
    end
    set -l dm (osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode' 2>/dev/null)
    if test $status -eq 0
        test "$dm" = true
        return
    end
    test (defaults read -g AppleInterfaceStyle 2>/dev/null) = Dark
end
