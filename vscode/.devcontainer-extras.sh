apt-get update -y && apt-get install -y --no-install-recommends tmux vim neovim git
mkdir -p ~/git
DOTFILES_DIRECTORY=~/git/dotfiles
DOTFILES_BRANCH=master
git clone -b $DOTFILES_BRANCH https://github.com/mattcopas/dotfiles.git $DOTFILES_DIRECTORY
cd $DOTFILES_DIRECTORY
git pull origin $DOTFILES_BRANCH
cd -


# Add bash/zsh stuff
RC_FILE=~/.bashrc
echo "source ~/git/dotfiles/.alias" >> $RC_FILE
echo "source ~/git/dotfiles/.functions" >> $RC_FILE

# Add vimrc
cp $DOTFILES_DIRECTORY/.vimrc ~/.vimrc
# Add neovim config
mkdir -p ~/.config/nvim
cp $DOTFILES_DIRECTORY/init.vim ~/.config/nvim/init.vim

# Install vim-plug
# curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim 

# Install vscode extensions
# This doesnt seem to work in the Dockerfile, postCreateCommand, or postStartCommand
# Unfortunately it seems these will have to be added under "extensions" in the .devcontainer.json file
# code --install-extension kahole.magit

# Example usage - add this to .devcontainer/Dockerfile
# curl https://raw.githubusercontent.com/mattcopas/dotfiles/master/vscode/.devcontainer-extras.sh | bash -s
