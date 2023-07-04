dotfiles_directory=$HOME/git/dotfiles
shell_directory=$dotfiles_directory/shell
rc_file="$HOME/.zshrc"

echo "Sourcing dotfiles from $shell_directory to $rc_file"

function source_dotfile () {
  file=$1
  echo "Adding $file to $rc_file"
  echo "source $shell_directory/$file" >> $rc_file
}

source_dotfile alias
source_dotfile functions
source_dotfile env
