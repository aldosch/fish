# open text editor in current dir if no argument is provided
function e
    if test (count $argv) -eq 0
        nvim .
    else
        nvim $argv
    end
end
