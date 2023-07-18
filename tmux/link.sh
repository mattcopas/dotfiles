#!/usr/bin/env bash

dotfiles_tmux_directory=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

ln -s $dotfiles_tmux_directory/tmux.conf ~/.tmux.conf
