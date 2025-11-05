#!/usr/bin/env bash
 
relative_directory=$(dirname "$0")
dotfiles_directory=$(realpath $relative_directory)
echo "Creating symlink for $HOME/.vimrc to $dotfiles_directory/.vimrc"
# ln -s <real_file> <link>
ln -s -f $dotfiles_directory/.vimrc $HOME/.vimrc
