function proofread
    if not type -q gum
        echo "Error: gum is not installed. add 'gum' to nix/modules/apps.nix then run nixx l"
        return 1
    end

    _aldo_dracula_apply_palette

    set content (pbpaste)

    if test -z "$content"
        gum style --foreground $p_red "Error: Clipboard is empty!"
        return 1
    end

    set prompt "You are a professional proofreader. Review this text:

$content

Respond in this exact format:
1. ISSUES: List all grammar, spelling, and style issues (or 'No issues found')
2. CORRECTED: Provide the improved version with all fixes applied"

    gum spin --spinner dot --spinner.foreground $p_purple --title "Analyzing text..." -- fish -c "ollama run deepseek-custom \"$prompt\" | string collect" > /tmp/proof.txt

    gum style --foreground $p_cyan --bold "Proofreading Results:"
    echo

    cat /tmp/proof.txt | gum format

    set corrected_text (string collect < /tmp/proof.txt | awk '/CORRECTED:/,EOF/' | tail -n +2)

    echo
    if gum confirm "Copy corrected text to clipboard?"
        printf "%s\n" $corrected_text | pbcopy
        gum style --foreground $p_green "Corrected text copied to clipboard!"
    end

    rm /tmp/proof.txt
end
