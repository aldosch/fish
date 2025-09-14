# open finder in current dir or given path
function o
    if test (count $argv) -eq 0
        open .
    else
        open $argv
    end
end
