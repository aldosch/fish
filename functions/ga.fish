# add all in current dir if no argument is provided
function ga
    if test (count $argv) -eq 0
        git add .
        gs
        gd
    else
        git add $argv
        gs
        gd
    end
end
