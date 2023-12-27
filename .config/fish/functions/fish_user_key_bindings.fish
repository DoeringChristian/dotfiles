function fish_user_key_bindings
    # fish_vi_key_bindings default
    
    # Mapping for jk to escape
    bind --mode insert --sets-mode default jk cancel repaint-mode
    # Mapping for jj to j
    bind -M insert jj 'commandline -i j'

    #Mapping for clipboard in vim mode
    bind yy fish_clipboard_copy
    bind Y fish_clipboard_copy
    bind p fish_clipboard_paste
end
