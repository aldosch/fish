function _exc_api --description 'Call the Excalidraw+ REST API; prints the body, exit 0 iff HTTP 2xx'
    set -l method $argv[1]
    set -l path $argv[2]
    set -l data $argv[3]
    set -l key $EXCALIDRAW_API_KEY
    if test -z "$key"
        set key (secret-get EXCALIDRAW_API_KEY 2>/dev/null)
    end
    if test -z "$key"
        echo "_exc_api: EXCALIDRAW_API_KEY not available (run: secret-set EXCALIDRAW_API_KEY)" >&2
        return 1
    end
    set -l tmp (mktemp)
    set -l curl_args -sS -o $tmp -w '%{http_code}' -X $method \
        -H "Authorization: Bearer $key" -H 'Content-Type: application/json' \
        "https://api.excalidraw.com/api/v1$path"
    if test -n "$data"
        set curl_args $curl_args --data $data
    end
    set -l code (curl $curl_args 2>&1 | tail -1)
    set -l body (cat $tmp)
    rm -f $tmp
    if test "$code" -lt 200 -o "$code" -ge 300 2>/dev/null
        echo "_exc_api: HTTP $code from $method $path" >&2
        echo "$body" | head -5 >&2
        return 1
    end
    printf '%s\n' $body
end
