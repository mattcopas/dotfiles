dotfiles_directory=$HOME/git/dotfiles
shell_directory=$dotfiles_directory/shell
rc_file="$HOME/.zshrc"

echo "Sourcing dotfiles from $shell_directory to $rc_file"

for file in "$shell_directory"/.*
do
  echo "Linking file $file"
  echo "source $file" >> $rc_file
done
