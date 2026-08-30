function ocps --description 'Show running opencode portal instances + screen sessions'
    if not _oc_list_portals
        return 0
    end

    # Show Tailscale access URL if an instance is running
    set -l ts_ip (tailscale ip -4 2>/dev/null)
    if test -n "$ts_ip"; and test "$_oc_has_portal" = true
        set -l port (string match -r '3000|3001|3002' -- $_oc_portal_out | head -1)
        if test -z "$port"
            set port 3000
        end
        gum style --foreground $p_green "📱 http://$ts_ip:$port"
    end

    set -e _oc_portal_pids _oc_portal_out _oc_has_portal
end
