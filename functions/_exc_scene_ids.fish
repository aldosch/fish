function _exc_scene_ids --description 'List Excalidraw scene ids; optional arg filters by exact id or name substring'
    set -l q $argv[1]
    set -l offset 0
    set -l matches
    set -l total 0
    while true
        set -l page (_exc_api GET "/scenes?offset=$offset&limit=100")
        or return 1
        set -l lines (echo $page | jq -r '.data[] | "\(.metadata.id)\t\(.metadata.name)"')
        for line in $lines
            set total (math $total + 1)
            set -l id (string split \t $line)[1]
            set -l name (string split \t $line)[2]
            if test -z "$q"
                echo $id
            else if test (string lower $id) = (string lower $q)
                echo $id
                return 0
            else if string match -qi "*$q*" $name
                set matches $matches "$id	$name"
            end
        end
        set -l more (echo $page | jq -r '.hasNextPage')
        if test "$more" != true
            break
        end
        set offset (math $offset + 100)
    end
    if test -z "$q"
        return 0
    end
    if test (count $matches) -eq 0
        echo "_exc_scene_ids: no scene matching '$q' ($total scenes scanned)" >&2
        return 1
    end
    if test (count $matches) -gt 1
        echo "_exc_scene_ids: '$q' is ambiguous:" >&2
        for m in $matches
            echo "  $m" >&2
        end
        return 1
    end
    echo (string split \t $matches[1])[1]
end
