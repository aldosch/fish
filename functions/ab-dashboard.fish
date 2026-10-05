function ab-dashboard --description "Start or open the agent-browser dashboard via portless (single instance)"
    function __ab_extract_url
        string match -r 'https://dashboard\.agent-browser\.localhost/#dashboard-access-token=\S+'
    end

    set -l out
    set -l url

    if test "$argv[1]" = -r
        agent-browser dashboard stop >/dev/null 2>&1
    end

    set out (agent-browser dashboard start 2>&1)
    set url (__ab_extract_url -- $out)

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
