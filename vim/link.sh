#!/bin/bash
 
relative_directory=$(dirname "$0")
dotfiles_directory=$(realpath $relative_directory)
echo "Creating symlink for $HOME/.vimrc to $dotfiles_directory/.vimrc"
# ln -s <real_file> <link>
ln -s $dotfiles_directory/.vimrc $HOME/.vimrc
