function typora
    if test (count $argv) -eq 0
        open -a Typora .
    else
        open -a Typora $argv
    end
end
