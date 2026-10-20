# vi `l`: accept the autosuggestion when on the last character (vi normal mode
# never moves past it, so forward-char alone can't reach the suggestion);
# otherwise move right as usual.
function vi_forward_or_accept
    set -l len (string length -- "$(commandline -b)")
    if commandline --showing-suggestion; and test (commandline -C) -ge (math max 0, $len - 1)
        commandline -f accept-autosuggestion
    else
        fish_vi_run_count forward-char
    end
end
