" Filetype settings for Cyrograf contracts.
if exists('b:did_ftplugin')
  finish
endif
let b:did_ftplugin = 1

setlocal commentstring=//\ %s
setlocal comments=://
setlocal suffixesadd=.cyrograf
setlocal iskeyword+=_
setlocal expandtab
setlocal shiftwidth=2
setlocal softtabstop=2

let b:undo_ftplugin = 'setlocal commentstring< comments< suffixesadd< iskeyword< expandtab< shiftwidth< softtabstop<'