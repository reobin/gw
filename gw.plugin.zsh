# gw (oh-my-zsh / antigen / zplug entrypoint). Sources gw.sh under sh
# emulation so the POSIX functions keep sh behavior (word splitting, cd)
# when defined from zsh.
emulate sh -c '. "${${(%):-%N}:h}/gw.sh"'
