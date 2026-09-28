" Detect Cyrograf contract files by extension.
augroup cyrograf_ftdetect
  autocmd!
  autocmd BufRead,BufNewFile *.cyrograf setfiletype cyrograf
augroup END