apt-get update -y && apt-get install -y --no-install-recommends tmux vim neovim
mkdir -p ~/git
DOTFILES_DIRECTORY=~/git/dotfiles
DOTFILES_BRANCH=mc-plugins
git clone -b $DOTFILES_BRANCH https://github.com/mattcopas/dotfiles.git $DOTFILES_DIRECTORY
cd $DOTFILES_DIRECTORY
git pull origin $DOTFILES_BRANCH
cd -


# Add bash/zsh stuff
RC_FILE=~/.bashrc
echo "source ~/git/dotfiles/.alias" >> $RC_FILE
echo "source ~/git/dotfiles/.functions" >> $RC_FILE

# Add vimrc
cp ~/git/dotfiles/.vimrc ~/.vimrc
# Add neovim config
mkdir -p ~/.config/nvim
cp ~/git/dotfiles/init.vim ~/.config/nvim/init.vim

# Install vim-plug
curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim 
