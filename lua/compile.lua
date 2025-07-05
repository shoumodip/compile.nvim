local M = {}

local pattern = {}  -- The currently active pattern
local patterns = {} -- All the registered patterns

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

    -- Editor nerds try not to bikeshed challenge: difficulty impossible
    local number_before = vim.api.nvim_win_get_option(0, "number")
    local relativenumber_before = vim.api.nvim_win_get_option(0, "relativenumber")

    vim.cmd("wall | split | terminal echo Executing \\`"..vim.fn.shellescape(cmd).."\\`; echo; "..cmd)
    vim.api.nvim_win_set_option(0, "cursorline", true)

    vim.api.nvim_win_set_option(0, "number", number_before)
    vim.api.nvim_win_set_option(0, "relativenumber", relativenumber_before)

    M.cmd = cmd
    M.buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(M.buffer, "*compilation*")

    local function escape(s)
        return s:gsub("/", "\\/")
    end

    vim.cmd(string.format([[
        syntax keyword Error error Error ERROR
        syntax keyword WarningMsg hint Hint HINT note Note NOTE warning Warning WARNING

        syntax match String '\%%1l`.*`'
        syntax match Keyword '\%%1l^Executing\>'
        syntax match ErrorMsg '^\[Process exited \d\+\]$'
        syntax match Function '^\[Process exited 0\]$'
        syntax match Underlined /%s/
        syntax match Underlined /%s/
    ]], escape(pattern.without_col), escape(pattern.with_col)))

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

    local match = vim.fn.matchlist(line, "^"..pattern.with_col)
    if #match < 4 then
        match = vim.fn.matchlist(line, "^"..pattern.without_col)
        if #match < 3 then
            return
        end
    end

    local file = match[2]
    local row = tonumber(match[3]) or 1
    local col = (tonumber(match[4]) or 1) - 1

    vim.cmd(string.format([[
        normal! zz
        wincmd p
        edit %s
    ]], file))

    if row == vim.fn.line("$") + 1 then
        row = row - 1
        col = #vim.fn.getline("$") - 1
    end

    pcall(vim.api.nvim_win_set_cursor, 0, {row, col})
end

function M.next_with_col(prev)
    if open() then
        vim.fn.search(pattern.with_col, prev and "wb" or "w")
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
        vim.fn.search(pattern.without_col, prev and "wb" or "w")
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

function M.add_pattern(name, with_col, without_col, use)
    if not with_col then
        with_col = without_col
    end

    if not without_col then
        without_col = with_col
    end

    if not with_col then
        return
    end

    patterns[name] = {
        with_col = with_col,
        without_col = without_col,
    }

    if use then
        pattern = patterns[name]
    end
end

function M.use_pattern(name)
    if not name then
        return vim.ui.select(vim.tbl_keys(patterns), {prompt = "Select Pattern"}, M.use_pattern)
    end

    local p = patterns[name]
    if not p then
        return
    end

    pattern = p
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

M.add_pattern(
    "Default",
    "\\(\\f\\+\\):\\(\\d\\+\\):\\(\\d\\+\\):",
    "\\(\\f\\+\\):\\(\\d\\+\\):",
    true
)

return M
