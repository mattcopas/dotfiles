set nocompatible
" Uncommant to install plugins
" source .vimrc-load-plugins


" Get backspace to work in Powershell
set backspace=indent,eol,start

" Change <leader> to Spacebar
map <Space> <leader>

set number
set relativenumber
syntax on

" Search
set hlsearch " use :nohl to remove highlighting after search
set incsearch
set ignorecase smartcase " Ignore case in searches unless a capital is present
" Remove highlighting
nnoremap <Space><Space> :noh<CR>

set scrolloff=8 " start scrolling when cursor is 8 lines from the bottom

" Improve file search autocompleting
set path+=**
set wildmenu " Display matching files on tab completion
set wildignore=.swp

set noswapfile

set noerrorbells

" Set tab to 2 spaces
set tabstop=2 softtabstop=0 expandtab shiftwidth=2 smarttab
set smartindent

" Edit vimrc
nnoremap <Leader>vv :tab sp $MYVIMRC<CR>
nnoremap <leader>sv :source $MYVIMRC<CR>

" Use C-g to cancel like in Emacs
inoremap <C-g> <Esc>
vnoremap <C-g> <Esc>

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

" Exit insert mode after updatetime milliseconds (default 4000) - to see this value run :set updatetime?
" au CursorHoldI * stopinsert

"Display error when using arrow keys in normal mode
noremap <up>    :echo 'USE K TO GO UP'<CR>
noremap <down>  :echo 'USE J TO GO DOWN'<CR>
noremap <left>  :echo 'USE H TO GO LEFT'<CR>
noremap <right> :echo 'USE L TO GO RIGHT'<CR>

" Easier saving
nnoremap <leader>w :w<CR>

" Easier buffer/tab movement
" C-hjkl to switch panes
noremap <C-l> <C-w>l
noremap <C-h> <C-w>h
noremap <C-j> <C-w>j
noremap <C-k> <C-w>k
" Shift h/l to switch tabs
noremap <S-l> gt
noremap <S-h> gT

" Spell check current file
nnoremap <leader>sc :setlocal spell spelllang=en<CR>:echo 'Run :set nospell remove highlighting'<CR>

colorscheme desert

" Override search highlight colours
highlight Search ctermbg=LightYellow
" Override visual selection text color
highlight Visual ctermfg=LightYellow

