" Highlights {{{
function! s:HL(name, link)
  if !hlexists(a:name)
    execute "highlight! link ".a:name." ".a:link
  endif

  return 1
endfunction

call s:HL("compileError", "WarningMsg")
call s:HL("compileGood", "Function")
call s:HL("compileFile", "Identifier")
call s:HL("compileFileNum", "Special")
call s:HL("compileCommand", "Function")
call s:HL("compilePrompt", "Function")
" }}}
" Variables {{{
if !exists("g:compile#open_command")
  let g:compile#open_command = "split"
endif

if !exists("g:compile#previous_command")
  let g:compile#previous_command = ""
endif
" }}}
command! -nargs=0 Compile call compile#input()
