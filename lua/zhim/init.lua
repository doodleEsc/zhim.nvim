local Job = require("plenary.job")

local M = {}

M.options = {}

local function determine_os()
    if vim.fn.has("macunix") == 1 then
        return "macOS"
    elseif vim.fn.has("win32") == 1 then
        return "Windows"
    elseif vim.fn.has("wsl") == 1 then
        return "WSL"
    else
        return "Linux"
    end
end

local function is_supported()
    local os = determine_os()
    -- macOS, Windows, WSL
    if os ~= "Linux" then
        return true
    end

    -- Support fcitx5, fcitx and ibus in Linux
    -- other frameworks are not support yet, PR welcome
    local ims = { "fcitx5-remote", "fcitx-remote", "ibus" }
    for _, im in ipairs(ims) do
        if vim.fn.executable(im) then
            return true
        end
    end
end

local default = {
    enabled = true,

    -- im-select binary's name, or the binary's full path
    command = "im-select.exe",

    -- normal mode im
    default_im = { "1033" },

    -- insert mode im
    zh_im = { "2052" },

    -- Restore the default input method state when the following events are triggered
    default_events = { "VimEnter", "FocusGained", "InsertLeave", "CmdlineLeave" },

    -- when to change zh im
    zh_events = { "InsertEnter" },

    -- enabled treesitter nodes, always enabled if nodes is nil or nodes is empty
    nodes = nil,

    -- only works in those filetype, always enabled if ft is nil or ft is empty
    ft = nil,
}

local function check_table_empty(data)
    if next(data) == nil then
        return true
    end

    return false
end

local function check_enabled_ft()
    if M.options.ft == nil or check_table_empty(M.options.ft) then
        return true
    end

    local current_ft = vim.bo.filetype
    for _, ft in ipairs(M.options.ft) do
        if current_ft == ft then
            return true
        end
    end
    return false
end

-- Get node in user's cursor
-- In insert mode, cursor's position at cursor right
local function get_node_in_cursor()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local row, col = cursor_pos[1] - 1, cursor_pos[2] - 1
    local success, node = pcall(vim.treesitter.get_node, { pos = { row, col } })
    return success and node or nil
end

local function get_node_type_in_cursor()
    local node = get_node_in_cursor()
    return node and node:type() or nil
end

local function check_enabled_nodes()
    if M.options.nodes == nil or check_table_empty(M.options.nodes) then
        return true
    end

    local current_node_type = get_node_type_in_cursor()
    if current_node_type == nil then
        return false
    end

    for _, node_type in ipairs(M.options.nodes) do
        if current_node_type == node_type then
            return true
        end
    end

    return false
end

local function change_im_select(cmd, args, callback)
    local job = Job:new({
        command = cmd,
        args = args,
        on_exit = function(_, code, signal)
            if code ~= 0 then
                vim.notify(
                    string.format(
                        "Command failed: %s %s, code: %d, signal: %s",
                        cmd,
                        table.concat(args, " "),
                        code,
                        tostring(signal)
                    ),
                    vim.log.levels.ERROR
                )
            end
            if callback then
                callback(code, signal)
            end
        end,
    })

    job:start()
end

local function restore_default_im()
    if M.options.enabled then
        -- Add a callback here to see the exit code for default_im changes as well
        change_im_select(M.options.command, M.options.default_im, function(code, signal)
            if code ~= 0 then
                vim.notify(
                    string.format(
                        "Restore default IM command failed: %s %s, code: %d, signal: %s",
                        M.options.command,
                        table.concat(M.options.default_im, " "),
                        code,
                        tostring(signal)
                    ),
                    vim.log.levels.ERROR
                )
            end
        end)
    end
end

local function set_smart_im()
    if M.options.enabled then
        if check_enabled_nodes() and check_enabled_ft() then
            change_im_select(M.options.command, M.options.zh_im)
        end
    end
end

M.toggle = function()
    local status = M.options.enabled
    M.options.enabled = not status
end

M.setup = function(opts)
    if not is_supported() then
        return
    end
    M.options = vim.tbl_deep_extend("force", {}, default, opts or {})

    -- set autocmd
    local group_id = vim.api.nvim_create_augroup("zhim", { clear = true })

    -- set default im
    vim.api.nvim_create_autocmd(M.options.default_events, {
        callback = restore_default_im,
        group = group_id,
    })

    -- change im when InsertEnter
    vim.api.nvim_create_autocmd(M.options.zh_events, {
        callback = set_smart_im,
        group = group_id,
    })
end

return M
