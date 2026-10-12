function ab-dashboard --description "Start or open the agent-browser dashboard via portless (single instance)"
    function __ab_extract_url
        string match -r 'https://dashboard\.agent-browser\.localhost/#dashboard-access-token=\S+'
    end

    set -l out
    set -l url

    if test "$argv[1]" = -r
        agent-browser dashboard stop >/dev/null 2>&1
    end

    # Self-heal the portless route: re-register the alias idempotently so the
    # https URL survives lost portless state, then make sure the proxy is up.
    portless alias dashboard.agent-browser 4848 >/dev/null 2>&1

    set out (agent-browser dashboard start 2>&1)
    set url (__ab_extract_url -- $out)

    if not curl -sf -o /dev/null --max-time 2 https://dashboard.agent-browser.localhost/
        # Clean https origin refused: proxy is down or stuck in HTTP mode on
        # 1355. Retry without sudo (falls back to 1355), then report the fix.
        portless proxy start >/dev/null 2>&1
        if not curl -sf -o /dev/null --max-time 2 https://dashboard.agent-browser.localhost/
            echo $out
            echo "https://dashboard.agent-browser.localhost refused to connect."
            echo "Port 443 needs one interactive sudo. Run in a terminal and accept the prompt:"
            echo "  portless proxy stop; and portless proxy start"
            echo "To survive reboots, also: portless service install"
            return 1
        end
    end

    if set -q url[1]
        # Fresh start: open the tokenized portless URL once to pin the cookie.
        open $url[1]
    else if string match -q "*already running*" -- $out
        open https://dashboard.agent-browser.localhost
    else
        echo $out
        open https://dashboard.agent-browser.localhost
    end
end
