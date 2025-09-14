function vercel-case
    # Function: vercel-case - Manages Vercel support case directories
    # Usage: vercel-case [case_number]
    # If no case number provided, tries to use clipboard content
    
    # Get case number from argument or clipboard
    set case_number $argv[1]
    
    if test -z "$case_number"
        set case_number (pbpaste)
    end
    
    # Validate case number format (must be 8 digits)
    if not string match -qr '^[0-9]{8}$' "$case_number"
        gum style --foreground "#ff0000" "😬 Error: Input should be an 8-digit case number."
        return 1
    end
    
    set CASE_DIR "$HOME/vercel/cases/$case_number"
    
    # Create directory if it doesn't exist
    if not test -d "$CASE_DIR"
        gum style --foreground "#00ff00" --bold "✨ Creating new case: $case_number"
        mkdir -p "$CASE_DIR"
    else
        gum style --foreground "#0088ff" --bold "👀 Opening existing case: $case_number"
        
        # Check when this case was last accessed
        if test -f "$CASE_DIR/.last_access"
            set last_access (cat "$CASE_DIR/.last_access")
            gum style --foreground "#888888" "🕒 Last accessed: $last_access"
        end
        
        # Check for non-hidden files
        set visible_files (ls -A "$CASE_DIR" | grep -v "^\." | wc -l | tr -d ' ')
        
        if test "$visible_files" -gt 0
            # Find most recently modified file
            set newest_file (ls -t "$CASE_DIR" | grep -v "^\." | head -n 1)
            
            if test -n "$newest_file" -a -f "$CASE_DIR/$newest_file"
                # Get modification time in macOS format
                set mod_time (date -r "$CASE_DIR/$newest_file" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
                if test -n "$mod_time"
                    gum style --foreground "#888888" "🕒 Last modified: $mod_time ($newest_file)"
                end
            end
            
            # Display directory contents
            gum style --foreground "#ffaa00" "📂 Case contents ($visible_files items):"
            
            # Format directory listing with gum
            ls -la "$CASE_DIR" | tail -n +4 |
            gum format -t code |
            gum style --padding "0 1" --margin "1" --border rounded --border-foreground "#aaaaaa"
        end
    end
    
    # Save current access time for future reference
    date "+%Y-%m-%d %H:%M:%S" > "$CASE_DIR/.last_access"
    
    # Open the directory in Finder
    # open "$CASE_DIR"
    
    # Change to the case directory
    cd "$CASE_DIR"
    
    # Confirm the current directory
    # gum style --foreground "#00ffaa" "📍 Now working in: $(pwd)"
end
