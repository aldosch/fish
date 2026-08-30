function ocpk --description 'List and stop running opencode portal instances + screen sessions'
    if not _oc_list_portals
        return 0
    end

    # Confirm
    if not gum confirm "Stop all portal instances and screen sessions?"
        set -e _oc_portal_pids _oc_portal_out _oc_has_portal
        return 0
    end

    # Stop openportal
    openportal stop 2>/dev/null

    # Kill portal screen sessions
    for pid in $_oc_portal_pids
        kill $pid 2>/dev/null
    end
    screen -wipe 2>/dev/null

    set -e _oc_portal_pids _oc_portal_out _oc_has_portal
    gum style --foreground $p_green "✓ All portal instances stopped"
end
