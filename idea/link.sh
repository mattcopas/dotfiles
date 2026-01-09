#!/usr/bin/env bash
 
relative_directory=$(dirname "$0")
dotfiles_directory=$(realpath $relative_directory)
config_directory="$HOME"
file=".ideavimrc"
mkdir -p $config_directory
echo "Creating symlink for $config_directory/$file to $dotfiles_directory/$file"
# ln -s <real_file> <link>
ln -s -f $dotfiles_directory/$file $config_directory/$file
