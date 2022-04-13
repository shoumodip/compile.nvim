" Highlights
function! s:HL(name, link)
  if !hlexists(a:name)
    execute "highlight! link ".a:name." ".a:link
  endif

  return 1
endfunction

call s:HL("compileBad", "WarningMsg")
call s:HL("compileGood", "Function")
call s:HL("compileLabel", "Identifier")
call s:HL("compileFile", "Special")
call s:HL("compileCommand", "Function")
call s:HL("compilePrompt", "Function")

" Variables
if !exists("g:compile#open_command")
  let g:compile#open_command = "split"
endif

if !exists("g:compile#previous_command")
  let g:compile#previous_command = ""
endif

command! -nargs=* Compile call compile#start(<args>)
command! -nargs=0 CompileNext call compile#jump(0)
command! -nargs=0 CompilePrev call compile#jump(1)
command! -nargs=0 Recompile call compile#restart()
