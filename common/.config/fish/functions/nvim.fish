function nvim --description 'Run nvim with a clean LD_LIBRARY_PATH so conda/pixi envs do not shadow Nix libuv'
    command env -u LD_LIBRARY_PATH nvim $argv
end
