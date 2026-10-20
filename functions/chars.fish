function chars --description "Count characters (multibyte-aware) in a string"
    if test (count $argv) -eq 0
        cat | wc -m | string trim
        return
    end
    printf '%s' "$argv" | wc -m | string trim
end
