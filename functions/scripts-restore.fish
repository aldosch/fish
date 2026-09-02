# scripts-restore - install and load custom LaunchAgents from ~/.config/scripts/
#
# Scans ~/.config/scripts/ for any *.plist files (one level deep) and ensures
# each is copied to ~/Library/LaunchAgents/ and loaded via launchctl.
# Also installs git hooks (post-push for docs-sync) into .git/hooks/.
#
# Safe to run repeatedly — skips plists/hooks that are already installed.
#
# Called automatically by nixx (full update) and can be run standalone
# on a new machine to restore all custom scripts/agents.
#
# Usage:
#   scripts-restore

function scripts-restore
    if not type -q gum
        echo "Error: gum is not installed. add 'gum' to nix/modules/apps.nix then run nixx l"
        return 1
    end

    _aldo_dracula_apply_palette

    set -l scripts_dir "$HOME/.config/scripts"
    set -l agents_dir "$HOME/Library/LaunchAgents"

    # --- header ---
    echo
    gum style --bold --foreground $p_purple --border rounded --border-foreground $p_purple \
        --padding "0 2" --align center \
        "scripts-restore" \
        (gum style --foreground $p_muted "syncing LaunchAgents from ~/.config/scripts/")
    echo

    set -l installed 0
    set -l skipped 0
    set -l failed 0

    # Find all *.plist files exactly one directory deep under scripts/
    for plist in $scripts_dir/*/*.plist
        if not test -f "$plist"
            continue
        end

        set -l plist_name (basename "$plist")
        set -l label (string replace '.plist' '' "$plist_name")
        set -l dest "$agents_dir/$plist_name"

        # Check if already loaded in launchd
        if launchctl list "$label" >/dev/null 2>&1
            gum join --horizontal \
                (gum style --foreground $p_muted "  –") \
                (gum style --foreground $p_muted " $label") \
                (gum style --foreground $p_muted " (already loaded)")
            set skipped (math $skipped + 1)
            continue
        end

        # Copy plist to LaunchAgents if not there or outdated
        if not test -f "$dest"; or not diff -q "$plist" "$dest" >/dev/null 2>&1
            if not cp "$plist" "$dest" 2>/dev/null
                gum join --horizontal \
                    (gum style --foreground $p_red "  ✗") \
                    (gum style --foreground $p_fg " $label") \
                    (gum style --foreground $p_muted " (failed to copy plist)")
                set failed (math $failed + 1)
                continue
            end
        end

        # Load the agent
        if launchctl bootstrap "gui/"(id -u) "$dest" 2>/dev/null
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " $label") \
                (gum style --foreground $p_muted " (loaded)")
            set installed (math $installed + 1)
        else
            gum join --horizontal \
                (gum style --foreground $p_red "  ✗") \
                (gum style --foreground $p_fg " $label") \
                (gum style --foreground $p_muted " (launchctl bootstrap failed)")
            set failed (math $failed + 1)
        end
    end

    if test $installed -eq 0; and test $failed -eq 0; and test $skipped -eq 0
        gum style --foreground $p_muted "  No plist files found in ~/.config/scripts/*/"
    end

    # --- git hooks ---
    # Installs a post-push hook that triggers docs-sync in the background
    # after a push to main. The hook is local-only (not tracked by git),
    # so it needs to be reinstalled on a fresh clone.
    set -l hooks_dir "$HOME/.config/.git/hooks"
    set -l post_push "$hooks_dir/post-push"
    set -l hook_content "#!/bin/bash
# Auto-installed by scripts-restore (fish function)
# Triggers docs-sync after a push to main (runs in background, non-blocking)
fish -c docs-sync >/dev/null 2>&1 &
"

    set -l hook_needs_install 1
    if test -f "$post_push"
        if printf '%s\n' "$hook_content" | diff -q - "$post_push" >/dev/null 2>&1
            set hook_needs_install 0
        end
    end

    if test $hook_needs_install -eq 1
        mkdir -p "$hooks_dir"
        printf '%s\n' "$hook_content" >"$post_push"
        chmod +x "$post_push"
        gum join --horizontal \
            (gum style --foreground $p_green "  ✓") \
            (gum style --foreground $p_fg " post-push hook") \
            (gum style --foreground $p_muted " (installed → docs-sync)")
    else
        gum join --horizontal \
            (gum style --foreground $p_muted "  –") \
            (gum style --foreground $p_muted " post-push hook") \
            (gum style --foreground $p_muted " (already installed)")
    end

    echo
end
