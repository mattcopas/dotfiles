#!/usr/bin/env bash
 
relative_directory=$(dirname "$0")
dotfiles_directory=$(realpath $relative_directory)
echo "Creating symlink for $HOME/.tmux.conf to $dotfiles_directory/.tmux.conf"
# ln -s <real_file> <link>
ln -s -f $dotfiles_directory/.tmux.conf $HOME/.tmux.conf
