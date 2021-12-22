# Use emacs keybindings (equiv to set -o emacs in bash)
Set-PSReadLineOption -EditMode Emacs

# Render unicode characters properly
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding =
                    New-Object System.Text.UTF8Encoding

function ImportModuleIfExists() {
  $module = $args[0]
  $module_exists = Get-Module -ListAvailable $module
  if($module_exists) {
    Import-Module $module
    return $true
  } else {
    Write-Host "Consider installing module $module"
    return $false
  }
}

if((ImportModuleIfExists "oh-my-posh")) {
  Set-PoshPrompt -Theme pure
}

# Cast the function call to void to suppress output
[void] (ImportModuleIfExists "posh-git")

# Make a function to exit
# This is to get around not being able to use 'exit' as an alias value
function Quit() {
   exit
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
Set-Alias -name ll -value Get-ChildItem
Set-Alias -name l -value Get-ChildItem
# FIXME - see above function
Set-Alias -name sz -value Source-Profile

# Git
function GitStatus() { git status }
function GitLog { git log }
function GitLogOneline { git log --oneline }
function GitDiff { git diff }
function GitDiffStaged { git diff --staged }
Set-Alias -name gs -value GitStatus
# Delete the existing gl alias before overriding
del alias:gl -Force
Set-Alias -name gl -value GitLog -force
Set-Alias -name glo -value GitLogOneline
Set-Alias -name gd -value GitDiff
Set-Alias -name gds -value GitDiffStaged

