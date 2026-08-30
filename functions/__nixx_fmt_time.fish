function __nixx_fmt_time --description 'Format seconds as Ns or Nm Ns'
    set -l secs $argv[1]
    if test $secs -lt 60
        echo {$secs}s
    else
        set -l mins (math "floor($secs / 60)")
        set -l rem (math "$secs % 60")
        echo {$mins}m\ {$rem}s
    end
end
