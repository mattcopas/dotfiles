try
  " Plugins will be downloaded under the specified directory.
  call plug#begin('~/.vim/plugged')
  Plug 'tpope/vim-fugitive'
  Plug 'morhetz/gruvbox'
  Plug 'dense-analysis/ale'
  Plug 'pangloss/vim-javascript'    " JavaScript support
  Plug 'leafgarland/typescript-vim' " TypeScript syntax
  Plug 'maxmellon/vim-jsx-pretty'   " JS and JSX syntax
  Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
  " Set better search command to include hidden files
  " Consider changing this to use rg (ripgrep)
  let $FZF_DEFAULT_COMMAND="find ." " Note that this searches from whichever dir
  " we were in when running the vim command
  Plug 'junegunn/fzf.vim' 
  " List ends here. Plugins become visible to Vim after this call.
  call plug#end()

  " Ale config
  let g:ale_fixers = {
  \   'typescript': ['prettier', 'eslint'],
  \   'typescriptreact': ['prettier', 'eslint'],
  \}
  let g:ale_linters = {}
  let g:ale_linters.typescript = ['eslint', 'tsserver']
  let g:ale_linters.typescriptreact = ['eslint', 'tsserver']
  let g:ale_typescript_prettier_use_local_config = 1
  let g:ale_fix_on_save = 1
  let g:ale_linters_explicit = 1
  let g:ale_completion_enabled = 1
  " Use j to cycle ale autocomplete suggestions
  inoremap <silent><expr> "j"
      \ pumvisible() ? "\<C-n>" : j

  " Git fugitive aliases
  nmap <leader>gs :G<CR>

catch
  echo "vim-plug error - not installed?" . v:exception
endtry

" use gruvbox color scheme
try
  colorscheme gruvbox
catch
  echo "Could not use gruvbox - Plugins installed?"
  echo "If a vim-plug is installed, run :PlugInstall"
endtry

" Change <leader> to Spacebar
map <Space> <leader>

set number
set relativenumber
syntax on

set hlsearch " use :nohl to remove highlighting after search
set incsearch

set scrolloff=8 " start scrolling when cursor is 8 lines from the bottom


set ignorecase smartcase " Ignore case in searches unless a capital is present

set path+=**
set wildmenu " Display matching files on tab completion
set wildignore=.swp

nnoremap <C-p> :FZF<CR>

set noerrorbells

" Set tab to 2 spaces
set tabstop=2 softtabstop=0 expandtab shiftwidth=2 smarttab
set smartindent

if $TERM == 'screen'
  " Workaround to get colors to work in tmux
  set t_Co=256
endif
set background=dark
" Current line highlighting
" set cursorline 
" Highlight current line
" highlight CursorLine guifg=white guibg=darkblue ctermfg=white ctermbg=darkblue
" Change colour of highlight when entering/leaving insert mode
" autocmd InsertEnter * highlight CursorLine guifg=white guibg=darkblue ctermfg=white ctermbg=darkgreen
" autocmd InsertLeave * highlight CursorLine guifg=white guibg=darkblue ctermfg=white ctermbg=darkblue
