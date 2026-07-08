# open text editor in current dir if no argument is provided
function c
    if test (count $argv) -eq 0
        cursor .
    else
        cursor $argv
    end
end
