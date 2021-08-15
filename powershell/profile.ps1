# Use emacs keybindings (equiv to set -o emacs in bash)
Set-PSReadLineOption -EditMode Emacs

if((Get-Module -ListAvailable "oh-my-posh")) {
  Import-Module oh-my-posh
  Set-PoshPrompt -Theme pure
}

# Make a function to exit
# This is to get around not being able to use 'exit' as an alias value
function Quit() {
  Invoke-Command -ScriptBlock { exit }
}

function Source-Profile() {
  Write-Host "Sourcing $profile"
  # FIXME - this doesn't apply the changes to the session
  . $profile
}

function Edit-Vimrc() {
  vim ~/.vimrc
}

Set-Alias -name ":wq" -value Quit
Set-Alias -name vi -value vim
Set-Alias -name v -value vim
Set-Alias -name vv -value Edit-Vimrc
# FIXME - see above function
Set-Alias -name sz -value Source-Profile

# Git
function GitStatus() { git status }

function GitLog { git log }
function GitLogOneline { git log --oneline }
Set-Alias -name gs -value GitStatus
# Delete the existing gl alias before overriding
del alias:gl -Force
Set-Alias -name gl -value GitLog -force
Set-Alias -name glo -value GitLogOneline
