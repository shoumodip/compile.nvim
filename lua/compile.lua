local M = {}

local pattern = {}  -- The currently active pattern
local patterns = {} -- All the registered patterns

local function is_open()
    if not M.buffer then
        return false
    end

    if not vim.api.nvim_buf_is_valid(M.buffer) then
        M.buffer = nil
        return false
    end

    return true
end

local function open()
    if not is_open() then
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

local function apply_highlights()
    if not is_open() then
        return
    end

    local function escape(s)
        return s:gsub("/", "\\/")
    end

    vim.api.nvim_buf_call(M.buffer, function ()
        vim.cmd(string.format([[
            syntax clear
            syntax keyword Error error Error ERROR
            syntax keyword WarningMsg hint Hint HINT note Note NOTE warning Warning WARNING

            syntax match String '\%%1l`.*`'
            syntax match Keyword '\%%1l^Executing\>'
            syntax match ErrorMsg '^\[Process exited \d\+\]$'
            syntax match Function '^\[Process exited 0\]$'
            syntax match Underlined /%s/
            syntax match Underlined /%s/
        ]], escape(pattern.without_col), escape(pattern.with_col)))
    end)
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

    local number_before = vim.api.nvim_win_get_option(0, "number")
    local relativenumber_before = vim.api.nvim_win_get_option(0, "relativenumber")

    vim.cmd("wall | split | terminal echo Executing \\`"..vim.fn.shellescape(cmd).."\\`; echo; "..cmd)
    vim.api.nvim_win_set_option(0, "cursorline", true)

    vim.api.nvim_win_set_option(0, "number", number_before)
    vim.api.nvim_win_set_option(0, "relativenumber", relativenumber_before)

    M.cmd = cmd
    M.buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(M.buffer, "*compilation*")

    for key, func in pairs(M.bindings) do
        vim.keymap.set("n", key, func, {buffer = M.buffer, silent = false})
    end

    apply_highlights()
end

local function current_match(row, col, line, pattern, order)
    local p = 0
    while true do
        local match_text, match_begin, match_end = unpack(vim.fn.matchstrpos(line, pattern, p))
        if match_begin == -1 then
            return nil
        end

        if col >= match_begin and col < match_end then
            local list = vim.fn.matchlist(match_text, pattern)
            local result = {}
            for i, field in ipairs(order) do
                local val = list[i + 1]
                result[field] = (field == "row" or field == "col") and tonumber(val) or val
            end
            return result
        end

        p = match_end
    end
end

local function edit_file(path)
    local fullpath = vim.fn.fnamemodify(path, ":p")
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            if vim.fn.fnamemodify(bufname, ":p") == fullpath then
                vim.api.nvim_set_current_buf(bufnr)
                return
            end
        end
    end

    vim.cmd.edit(fullpath)
end

function M.open()
    if not open() then
        M.start()
        return
    end

    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()

    local result = current_match(row, col, line, pattern.with_col, pattern.with_col_order)
    if not result then
        result = current_match(row, col, line, pattern.without_col, pattern.without_col_order)
    end

    if not result then
        return
    end

    if result.col then
        result.col = result.col - 1
    else
        result.col = 0
    end

    vim.cmd([[
        normal! zz
        wincmd p
    ]])

    edit_file(result.path)

    if result.row == vim.fn.line("$") + 1 then
        result.row = result.row - 1
        result.col = #vim.fn.getline("$") - 1
    end

    pcall(vim.api.nvim_win_set_cursor, 0, {result.row, result.col})
end

function M.open_mouse_click()
    local mouse = vim.fn.getmousepos()
    vim.api.nvim_set_current_win(mouse.winid)
    vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, math.max(mouse.column - 1, 0) })
    M.open()
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

local function compile_pattern(pattern)
    local order = {}
    local replacements = {
        ["[<path>]"] = "\\(\\f\\+\\)",
        ["[<row>]"]  = "\\(\\d\\+\\)",
        ["[<col>]"]  = "\\(\\d\\+\\)",
    }

    local compiled = pattern:gsub("%[<%a+>%]", function(token)
        if not order then
            return nil
        end

        local replacement = replacements[token]
        if replacement then
            local title = token:sub(3, -3)
            if vim.tbl_contains(order, title) then
                vim.api.nvim_echo({
                    {"Invalid pattern ", "Error"},
                    {vim.fn.shellescape(pattern), "String"},
                    {". ", "Error"},
                    {"(Duplicate specifier ", "WarningMsg"},
                    {"'[<"..title..">]'", "String"},
                    {")\n", "WarningMsg"}
                }, true, {})

                order = nil
                return nil
            end

            table.insert(order, title)
            return replacement
        end
    end)

    if not order then
        return nil, nil
    end

    local path_absent = not vim.tbl_contains(order, "path")
    local row_absent = not vim.tbl_contains(order, "row")

    if path_absent or row_absent then
        vim.api.nvim_echo({
            {"Invalid pattern ", "Error"},
            {vim.fn.shellescape(pattern), "String"},
            {". ", "Error"},
            {path_absent and row_absent and "(Specifiers " or "(Specifier ", "WarningMsg"},
            {path_absent and "'[<path>]'" or "", "String"},
            {path_absent and row_absent and " and " or "", "WarningMsg"},
            {row_absent and "'[<row>]'" or "", "String"},
            {" absent)\n\n", "WarningMsg"},
            {"Example Pattern: ", "Title"},
            {"'[<path>]:[<row>]:[<col>]:'\n", "String"}
        }, true, {})

        return nil, nil
    end

    return compiled, order
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

    local with_col_compiled, with_col_order = compile_pattern(with_col)
    if not with_col_compiled then
        return
    end

    local without_col_compiled, without_col_order = compile_pattern(without_col)
    if not without_col_compiled then
        return
    end

    patterns[name] = {
        with_col = with_col_compiled,
        without_col = without_col_compiled,

        with_col_order = with_col_order,
        without_col_order = without_col_order,
    }

    if use then
        pattern = patterns[name]
    end
end

function M.use_pattern(name)
    if not name then
        local current = vim.api.nvim_get_current_win()
        vim.cmd("wincmd p")

        local previous = vim.api.nvim_get_current_win()
        vim.cmd("wincmd p")

        return vim.ui.select(vim.tbl_keys(patterns), {prompt = "Select Pattern"}, function (p)
            vim.api.nvim_set_current_win(previous)
            vim.api.nvim_set_current_win(current)
            M.use_pattern(p)
        end)
    end

    local p = patterns[name]
    if not p then
        return
    end

    pattern = p
    apply_highlights()
end

M.bindings = {
    ["s"] = M.use_pattern,
    ["r"] = M.restart,
    ["]e"] = M.next_with_col,
    ["[e"] = M.prev_with_col,
    ["]E"] = M.next,
    ["[E"] = M.prev,
    ["<cr>"] = M.open,
    ["<leftmouse>"] = M.open_mouse_click,
    ["<c-c>"] = M.stop,
}

M.add_pattern(
    "Default",
    "[<path>]:[<row>]:[<col>]:",
    "[<path>]:[<row>]:",
    true
)

return M
