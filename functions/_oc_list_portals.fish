function _oc_list_portals --description 'Find running portal screen sessions + openportal instances'
    # Find portal screen sessions (SCREEN processes whose command contains 'openportal')
    set -l all_screens (screen -ls 2>/dev/null | awk '/\t/ {split($1,a,"."); print a[1]}')
    set -l portal_pids
    for spid in $all_screens
        if string match -q '*openportal*' -- (ps -p $spid -o command= 2>/dev/null)
            set portal_pids $portal_pids $spid
        end
    end

    # Get openportal instances (table output contains a separator line of dashes)
    set -l portal_out (openportal list 2>/dev/null)
    set -l has_portal (echo $portal_out | grep -q -- '----'; and echo true; or echo false)

    # Check if anything is running
    if test $has_portal = false; and test (count $portal_pids) -eq 0
        gum style --foreground $p_muted "No portal instances running."
        return 1
    end

    # Show what's running
    echo
    if test $has_portal = true
        gum style --foreground $p_cyan "OpenPortal instances:"
        echo $portal_out
        echo
    end
    if test (count $portal_pids) -gt 0
        gum style --foreground $p_cyan "Portal screen sessions:"
        for pid in $portal_pids
            echo "  "(set_color $p_muted)"PID $pid"(set_color normal)"  "(ps -p $pid -o command= 2>/dev/null)
        end
        echo
    end

    # Export pids and portal output for callers (ocpk needs pids to kill)
    set -gx _oc_portal_pids $portal_pids
    set -gx _oc_portal_out $portal_out
    set -gx _oc_has_portal $has_portal
    return 0
end
