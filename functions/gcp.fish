function gcp
    if test (count $argv) -eq 0
        git commit && git push
    else
        git commit -m (string join " " $argv) && git push
    end
end
