vim.cmd([[
    command! -nargs=* -complete=shellcmdline Compile lua require("compile").start(<q-args>)
    command! -nargs=0 CompileNext lua require("compile").next()
    command! -nargs=0 CompilePrev lua require("compile").prev()
    command! -nargs=0 Recompile lua require("compile").restart(true)
]])
