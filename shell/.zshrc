# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="agnoster"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled
zstyle ':omz:update' mode auto
# zstyle ':omz:update' mode reminder

# Uncomment the following line to change how often to auto-update (in days).
zstyle ':omz:update' frequency 14

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git aws virtualenv)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
export PATH=$PATH:~/tools/bin

# Treat these characters as words, so C-w will work as pected on things like
# kubectl exec -it -- echo("hello") | grep "h"
export WORDCHARS="|~-"

# Use neovim
if [ -x "$(command -v nvim)" ]; then
  alias vi=nvim
  alias vim=nvim
fi

# Ensure we're in a tmux session if in an interactive shell
# See arch docs for details - https://wiki.archlinux.org/title/Tmux#Start_tmux_on_every_shell_login
#
# NOTE - this is done BEFORE aliasing - as otherwise command -v tmux will return the alias, not the executable
#
# Only do this if we're not in an Emacs (or IntelliJ) terminal - things get weird otherwise
#
TMUX_TPM_DIRECTORY="$HOME/.tmux/plugins/tpm"
if [[ -z "$INSIDE_EMACS" ]] && [[  "$TERMINAL_EMULATOR" != "JetBrains-JediTerm" ]]; then
  # If on a mac, ignore the DISPLAY check as it's not set (unless X is installed)
  if [[ "$(uname -s)" == "Darwin" ]]; then
      if [ -x "$(command -v tmux)" ]; then
          if [ -d "$TMUX_TPM_DIRECTORY" ]; then
              echo "Tmux plugin directory $TMUX_TPM_DIRECTORY found"
          else
              echo "TPM plugin not found - clone it in to $TMUX_TPM_DIRECTORY"
          fi
          if [ -z "${TMUX}" ]; then
             exec tmux new-session -A -s ${USER} >/dev/null 2>%1
          fi
      fi

  elif [ -x "$(command -v tmux)" ] && [ -n "${DISPLAY}" ] && [ -z "${TMUX}" ]; then
      exec tmux new-session -A -s ${USER} >/dev/null 2>&1
  fi
fi

export PATH=$PATH:~/.emacs.d/bin
export SHELL_DOTFILES_DIRECTORY="$HOME/git/dotfiles/shell"
source $SHELL_DOTFILES_DIRECTORY/alias
source $SHELL_DOTFILES_DIRECTORY/functions
source $SHELL_DOTFILES_DIRECTORY/env

ENV_SPECIFIC_DOTFILES_DIR="$HOME/git/env-specific-dotfiles"
ENV_SPECIFIC_ZSHRC="$ENV_SPECIFIC_DOTFILES_DIR/.env_specific_zshrc"

if test "$ENV_SPECIFIC_ZSHRC"; then
  source $ENV_SPECIFIC_ZSHRC
else
  echo "No env specific zshrc found"
fi

# Enable bash completion for AWS
autoload bashcompinit && bashcompinit
autoload -Uz compinit && compinit
if command -v aws &> /dev/null
then
  complete -C '/usr/local/bin/aws_completer' aws
fi

if command -v starship; then
  eval "$(starship init zsh)"
else
  echo "Starship command not found"
fi

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
