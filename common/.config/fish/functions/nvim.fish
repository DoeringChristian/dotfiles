function nvim --description 'Run nvim with a clean LD_LIBRARY_PATH so conda/pixi project envs do not shadow its libraries'
    command env -u LD_LIBRARY_PATH nvim $argv
end
