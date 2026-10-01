# rectangle-drift - interactive gate for Rectangle settings drift
#
# Compares the live com.knollsoft.Rectangle defaults domain against the host
# snapshot in rectangle/Rectangle.$hostname.plist and offers, per drift:
#   Back up - snapshot Rectangle's current settings (runs rectangle-sync)
#   Discard - restore the snapshot into Rectangle (quit app, delete domain,
#             defaults import, relaunch)
# In --pre-apply mode (run by nixx before darwin-rebuild touches defaults)
# it also offers:
#   Continue anyway - proceed with the drift in place
#   Abort           - exit nonzero so nixx stops before running anything
#
# Without a TTY it is report-only and never blocks.
#
# rc 0 = proceed (clean, resolved, or report-only), 1 = abort.

# rectangle-sync.fish defines __rect_diff_keys / __rect_filtered_plist
source (status dirname)/rectangle-sync.fish

function rectangle-drift --description 'Check Rectangle settings against the dotfiles snapshot'
    set -l pre_apply 0
    for arg in $argv
        switch $arg
            case --pre-apply
                set pre_apply 1
        end
    end

    # nixx contexts already have the palette loaded; standalone runs need it
    if type -q _aldo_dracula_apply_palette
        _aldo_dracula_apply_palette
    end

    set -l interactive 1
    if not test -t 0; or not test -t 1
        set interactive 0
    end

    # Rectangle not installed: nothing to check
    if not defaults read com.knollsoft.Rectangle >/dev/null 2>&1
        return 0
    end

    set -l snapshot ~/.config/rectangle/Rectangle.$hostname.plist

    if not test -f "$snapshot"
        if test "$interactive" -eq 0
            echo "rectangle-drift: no snapshot at $snapshot (run rectangle-sync to create one)"
            return 0
        end
        set -l choice (gum choose \
            --cursor.foreground $p_purple \
            --selected.foreground $p_purple \
            --header "  No Rectangle snapshot yet ($snapshot). Create one?" \
            --header.foreground $p_muted \
            "Back up  (snapshot Rectangle's current settings)" \
            "Skip")
        if string match -q "Back up*" -- "$choice"
            rectangle-sync
        end
        return 0
    end

    set -l changes
    set -l out (__rect_diff_keys $snapshot)
    if test $status -eq 2
        echo "rectangle-drift: failed to compare Rectangle settings"
        return 0
    end
    set changes $out
    if test (count $changes) -eq 0
        return 0
    end

    echo
    gum style --foreground $p_orange --bold "  ▸ Rectangle settings drifted from the snapshot:"
    for line in $changes
        set -l f (string split \t -- $line)
        switch $f[1]
            case changed
                gum style --foreground $p_orange "    ~ $f[2]: $f[3] → $f[4]"
            case added
                gum style --foreground $p_green "    + $f[2]: $f[3]"
            case removed
                gum style --foreground $p_red "    - $f[2] (was $f[3])"
        end
    end

    if test "$interactive" -eq 0
        echo "rectangle-drift: report-only (no TTY); resolve with: nixx check or rectangle-drift"
        return 0
    end

    if test "$pre_apply" -eq 1
        set -l choice (gum choose \
            --cursor.foreground $p_purple \
            --selected.foreground $p_purple \
            --header "  Rectangle settings drifted and apply is about to run. What should happen?" \
            --header.foreground $p_orange \
            "Back up  (save Rectangle's current settings to the snapshot)" \
            "Discard  (restore snapshot settings into Rectangle)" \
            "Continue anyway  (apply with the drift in place)" \
            "Abort  (stop nixx here, change nothing)")
        switch "$choice"
            case "Back up*"
                rectangle-sync
                and gum style --foreground $p_green "  ✓ Snapshot updated"
            case "Discard*"
                __rect_restore $snapshot
            case "Continue*"
                return 0
            case "Abort*"
                return 1
        end
        return 0
    end

    set -l choice (gum choose \
        --cursor.foreground $p_purple \
        --selected.foreground $p_purple \
        --header "  Rectangle settings drifted. What should happen?" \
        --header.foreground $p_orange \
        "Back up  (save Rectangle's current settings to the snapshot)" \
        "Discard  (restore snapshot settings into Rectangle)" \
        "Dismiss  (skip for now)")
    switch "$choice"
        case "Back up*"
            rectangle-sync
            and gum style --foreground $p_green "  ✓ Snapshot updated"
        case "Discard*"
            __rect_restore $snapshot
        case "Dismiss*"
            # leave drift in place
    end
    return 0
end

function __rect_restore --argument-names snapshot
    gum style --foreground $p_red \
        "    Restoring overwrites Rectangle's current settings with the snapshot."

    set -l choice (gum choose \
        --cursor.foreground $p_red \
        --selected.foreground $p_red \
        --header "    Overwrite live Rectangle settings with the snapshot?" \
        --header.foreground $p_orange \
        "Cancel" \
        "Yes, restore")
    if test "$choice" != "Yes, restore"
        gum style --foreground $p_muted "  → Skipped"
        return 0
    end

    # Rectangle rewrites its whole domain on quit, so it must be fully quit
    # before the plist is touched.
    osascript -e 'tell application "Rectangle" to quit' 2>/dev/null
    set -l waits 0
    while pgrep -x Rectangle >/dev/null 2>&1; and test $waits -lt 20
        sleep 0.25
        set waits (math $waits + 1)
    end
    if pgrep -x Rectangle >/dev/null 2>&1
        killall Rectangle 2>/dev/null
        sleep 1
    end

    # delete + import (not just import) so keys added since the snapshot are
    # removed too: a faithful restore of the snapshotted state.
    defaults delete com.knollsoft.Rectangle 2>/dev/null
    if not defaults import com.knollsoft.Rectangle $snapshot
        gum style --foreground $p_red "  ✗ Restore failed (defaults import)"
        open -ga Rectangle
        return 0
    end
    open -ga Rectangle
    gum style --foreground $p_green "  ✓ Snapshot restored into Rectangle"
    return 0
end
