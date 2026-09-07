function mic --description "EVO4 mic input volume via setmic"
    if test (count $argv) -eq 0
        $HOME/.local/bin/setmic get
    else
        $HOME/.local/bin/setmic set $argv
    end
end
