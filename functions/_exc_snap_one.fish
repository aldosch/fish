function _exc_snap_one --description 'Fetch one Excalidraw scene + content and write a timestamped snapshot json'
    set -l id $argv[1]
    set -l ts (date +%Y-%m-%dT%H-%M-%S)
    set -l meta (_exc_api GET "/scenes/$id")
    or return 1
    set -l content (_exc_api GET "/scenes/$id/content")
    or return 1
    set -l scene_json (echo $meta | jq -c '.data // .')
    set -l content_json (echo $content | jq -c '.data // .')
    set -l dir "$HOME/.config/excalidraw/snapshots/$id"
    mkdir -p $dir
    set -l file $dir/$ts.json
    jq -n --argjson scene "$scene_json" --argjson content "$content_json" --arg ts $ts \
        '{snapshotted_at: $ts, scene: $scene, content: $content}' > $file
    or return 1
    echo "exc-snap: $id -> $file ("(wc -c < $file | string trim)" bytes)"
end
