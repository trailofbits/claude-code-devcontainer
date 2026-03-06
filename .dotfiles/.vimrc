" Auto-install vim-plug
let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

call plug#begin('~/.vim/plugged')
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'tpope/vim-fugitive'
Plug 'tomtom/tcomment_vim'
Plug 'tpope/vim-markdown'
Plug 'cespare/vim-toml'
call plug#end()

" Core settings
set wrap
set tabstop=4
set shiftwidth=4
set autoindent
set smartindent
set wildchar=<Tab>
set nonumber
set foldmethod=marker
set hidden
set wmh=0
set background=dark
set showmode
set pastetoggle=<F2>

filetype plugin indent on
syntax on
colorscheme habamax

let g:vim_json_syntax_conceal = 0

" Navigate between split windows
nmap <C-J> <C-W>j<C-W>_
nmap <C-K> <C-W>k<C-W>_
nmap <c-h> <c-w>h<c-w><bar>
nmap <c-l> <c-w>l<c-w><bar>

" Toggle dark/light background
map <F9> :set bg=dark<CR>
map <F10> :set bg=light<CR>

" Shift-Space to exit insert mode
imap <S-Space> <Esc>

" Toggle paste mode
nnoremap <F2> :set invpaste paste?<CR>

" Toggle whitespace visibility
nnoremap <F5> :set listchars=eol:¬,tab:>·,trail:~,extends:>,precedes:<,space:␣ list!<CR>

" YAML 2-space indent
autocmd Filetype yaml,yml setlocal ts=2 sw=2 expandtab

" Markdown filetype
augroup markdown
    au!
    au BufNewFile,BufRead *.md,*.markdown setlocal filetype=ghmarkdown
augroup END

" TAB completion in popup menu
inoremap <expr><TAB> pumvisible() ? "\<C-n>" : "\<TAB>"

" fzf mappings
nnoremap <Leader>o :Files<CR>
nnoremap <Leader>b :Buffers<CR>
nnoremap <Leader>r :Rg<CR>
nnoremap <Leader>w :w<CR>
