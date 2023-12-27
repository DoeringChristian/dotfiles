function l
    ls -l -g
end

if type -q eza
  alias l "eza -l -g --icons"
  alias ll "l -a"
  alias la "ll"
end
