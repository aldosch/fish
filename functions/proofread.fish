function proofread
    # Check if gum is installed
    if not type -q gum
        echo "Error: gum is not installed. Install with 'brew install gum'"
        return 1
    end

    # Get clipboard content
    set content (pbpaste)
    
    if test -z "$content"
        gum style --foreground 196 "🚫 Error: Clipboard is empty!"
        return 1
    end
    
    # Create prompt for the model
    set prompt "You are a professional proofreader. Review this text:

$content

Respond in this exact format:
1. ISSUES: List all grammar, spelling, and style issues (or 'No issues found')
2. CORRECTED: Provide the improved version with all fixes applied"
    
    # Run Ollama with spinner - using string collect to preserve newlines
    gum spin --spinner dot --title "🔍 Analyzing text..." -- fish -c "ollama run deepseek-custom \"$prompt\" | string collect" > /tmp/proof.txt
    
    # Display results with proper formatting preserved
    gum style --foreground 39 --bold "📋 Proofreading Results:"
    echo
    
    # Format and display the content with preserved line breaks
    cat /tmp/proof.txt | gum format
    
    # Extract corrected text (preserving line breaks)
    set corrected_text (string collect < /tmp/proof.txt | awk '/CORRECTED:/,EOF/' | tail -n +2)
    
    # Copy option with confirmation
    echo
    if gum confirm "Copy corrected text to clipboard?"
        printf "%s\n" $corrected_text | pbcopy
        gum style --foreground 46 "✅ Corrected text copied to clipboard!"
    end
    
    # Clean up
    rm /tmp/proof.txt
end

