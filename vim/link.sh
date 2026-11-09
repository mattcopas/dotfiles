#!/usr/bin/env bash

relative_directory=$(dirname "$0")
dotfiles_directory=$(realpath $relative_directory)
echo "Creating symlink for $HOME/.vimrc to $dotfiles_directory/.vimrc"
# ln -s <real_file> <link>
ln -s -f $dotfiles_directory/.vimrc $HOME/.vimrc

# Vim loads anything under pack/*/start by itself, so this is the whole install.
package_directory=$HOME/.vim/pack/orgflow/start
echo "Creating symlink for $package_directory/orgflow to $dotfiles_directory/orgflow"
mkdir -p "$package_directory"
ln -s -f -n "$dotfiles_directory/orgflow" "$package_directory/orgflow"
