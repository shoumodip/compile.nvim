vim.cmd([[
  command! -nargs=0 Recompile lua require("compile").restart(true)
  command! -nargs=0 CompileNext lua require("compile").next()
  command! -nargs=0 CompilePrev lua require("compile").prev()
  command! -nargs=0 CompileNextWithCol lua require("compile").next_with_col()
  command! -nargs=0 CompilePrevWithCol lua require("compile").prev_with_col()
  command! -nargs=* CompilePattern lua require("compile").pattern = <q-args>
  command! -nargs=* CompilePatternWithCol lua require("compile").pattern_with_col = <q-args>
  command! -nargs=* -complete=file Compile lua require("compile").start(<q-args>)
]])
