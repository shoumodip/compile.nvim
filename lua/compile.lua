local M = {}

local function is_open()
    return M.buffer and vim.api.nvim_buf_is_valid(M.buffer)
end

local function open()
    if not is_open() then
        M.buffer = nil
        return false
    end

    local window = vim.fn.bufwinid(M.buffer)
    if window == -1 then
        vim.cmd("split")
        vim.api.nvim_set_current_buf(M.buffer)
    else
        vim.api.nvim_set_current_win(window)
    end

    return true
end

function M.start(cmd)
    if not cmd or cmd == "" then
        _, cmd = pcall(vim.fn.input, "Compile: ")
        if cmd == "" then
            return
        end
    end

    if is_open() then
        vim.api.nvim_buf_delete(M.buffer, {force = true})
    end

    vim.cmd("wall | split | terminal echo Executing \\`"..vim.fn.shellescape(cmd).."\\`; echo; "..cmd)
    vim.api.nvim_win_set_option(0, "cursorline", true)

    M.cmd = cmd
    M.buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(M.buffer, "*compilation*")

    vim.cmd([[
        syntax match String '\%1l`.*`'
        syntax match Keyword '\%1l^Executing\>'
        syntax match ErrorMsg '^\[Process exited \d\+\]$'
        syntax match Function '^\[Process exited 0\]$'
        syntax match Underlined '\f\+:\d\+\(:\d\+\)\?'
    ]])

    for key, func in pairs(M.bindings) do
        vim.keymap.set("n", key, func, {buffer = M.buffer, silent = false})
    end
end

function M.open()
    if not open() then
        M.start()
        return
    end

    local pos = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_buf_get_lines(M.buffer, pos[1] - 1, pos[1], false)[1]
        :sub(pos[2] + 1)

    if vim.fn.matchstr(line, "^\\f\\+:\\d\\+:") == "" then
        vim.cmd("normal! j")
        return
    end

    line = vim.split(line, ":")
    vim.cmd([[
        normal! zz
        wincmd p
        edit ]]..line[1])

    vim.api.nvim_win_set_cursor(0, {tonumber(line[2]) or 1, (tonumber(line[3]) or 1) - 1})
end

function M.next_with_col(prev)
    if open() then
        vim.fn.search("\\f\\+:\\d\\+:\\d\\+:", prev and "wb" or "w")
        M.open()
    else
        M.start()
    end
end

function M.prev_with_col()
    M.next_with_col(true)
end

function M.next(prev)
    if open() then
        vim.fn.search("\\f\\+:\\d\\+:\\(\\d\\+:\\)\\?", prev and "wb" or "w")
        M.open()
    else
        M.start()
    end
end

function M.prev()
    M.next(true)
end

function M.restart()
    M.start(M.cmd)
end

function M.stop()
    if is_open() then
        vim.fn.jobstop(vim.b[M.buffer].terminal_job_id)
    end
end

function M.bind(bindings)
    for key, func in pairs(bindings or {}) do
        M.bindings[key] = func
    end
end

M.bindings = {
    ["r"] = M.restart,
    ["]e"] = M.next_with_col,
    ["[e"] = M.prev_with_col,
    ["]E"] = M.next,
    ["[E"] = M.prev,
    ["<cr>"] = M.open,
    ["<c-c>"] = M.stop,
}

return M
