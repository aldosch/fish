function _secret_set_write --description 'Write one key/value into the consolidated aldo-env-secrets Keychain blob'
    set -l key $argv[1]
    set -l value $argv[2]
    set -l blob (security find-generic-password -a $USER -s "aldo-env-secrets" -w 2>/dev/null)
    or set -l blob '{}'
    set -l new_blob (echo $blob | jq --arg key "$key" --arg value "$value" '.[$key] = $value')
    security add-generic-password -U -a $USER -s "aldo-env-secrets" -w "$new_blob"
    echo "Set $key ("(string length -- $value)" chars) in aldo-env-secrets"
end
