#!/usr/bin/env bash
 
relative_directory=$(dirname "$0")
dotfiles_directory=$(realpath $relative_directory)
echo "Creating symlink for $HOME/.config/emacs to $dotfiles_directory"
# ln -s <real_file> <link>
ln -s -f $dotfiles_directory $HOME/.config/emacs
