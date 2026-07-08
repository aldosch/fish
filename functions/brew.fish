function brew
    if test "$argv[1]" = i
        command brew install $argv[2..-1]
    else
        command brew $argv
    end
end