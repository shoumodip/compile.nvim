vim.cmd([[
  command! -nargs=0 Recompile lua require("compile").restart(true)
  command! -nargs=0 CompileNext lua require("compile").next()
  command! -nargs=0 CompilePrev lua require("compile").prev()
  command! -nargs=* -complete=file Compile lua require("compile").start(<q-args>)
]])
