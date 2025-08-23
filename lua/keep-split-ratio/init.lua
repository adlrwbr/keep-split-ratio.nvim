local M = {}

-- per-tab ratios for top-level columns (aka vertical splits)
local state = {}
local restoring = false

local function tabkey()
    return tostring(vim.api.nvim_tabpage_get_number(0))
end

local function first_leaf(node)
    local t = node[1]
    if t == "leaf" then
        return node[2]
    end
    for _, child in ipairs(node[2]) do
        local win = first_leaf(child)
        if win then
            return win
        end
    end
end

local function any_leaf_fixed(node)
    local t = node[1]
    if t == "leaf" then
        local win = node[2]
        return vim.api.nvim_win_get_option(win, "winfixwidth")
    end
    for _, child in ipairs(node[2]) do
        if any_leaf_fixed(child) then
            return true
        end
    end
    return false
end

-- Collect top-level "columns" (children of a root 'row') each represented by a leaf winid, its current width, and whether any window in that column is winfixwidth
local function collect_columns()
    local layout = vim.fn.winlayout()
    local cols = {}
    if layout[1] ~= "row" then
        -- No side-by-side splits- treat whole layout as one column
        local win = first_leaf(layout)
        if win then
            table.insert(cols, { win = win, width = vim.api.nvim_win_get_width(win), fixed = any_leaf_fixed(layout) })
        end
        return cols
    end

    for _, child in ipairs(layout[2]) do
        local win = first_leaf(child)
        if win then
            local width = vim.api.nvim_win_get_width(win)
            local fixed = any_leaf_fixed(child)
            table.insert(cols, { win = win, width = width, fixed = fixed })
        end
    end
    return cols
end

-- Save ratios for non-fixed columns; fixed columns keep their absolute width
function M.save()
    if restoring then
        return
    end -- don't capture during our own restore
    local cols = collect_columns()
    if #cols <= 1 then
        state[tabkey()] = nil
        return
    end

    local free = 0
    for _, c in ipairs(cols) do
        if not c.fixed then
            free = free + c.width
        end
    end

    -- If everything is fixed, nothing to do
    if free == 0 then
        state[tabkey()] = { ratios = nil, fixed = cols }
        return
    end

    local ratios = {}
    for i, c in ipairs(cols) do
        if c.fixed then
            ratios[i] = { fixed = true, width = c.width, win = c.win }
        else
            ratios[i] = { fixed = false, ratio = c.width / free, win = c.win }
        end
    end
    state[tabkey()] = { ratios = ratios }
end

-- Restore widths by applying saved ratios to the NEW total width
function M.restore()
    local s = state[tabkey()]
    if not s or not s.ratios then
        return
    end

    local cols = collect_columns()
    -- If column count changed, bail (avoid doing the wrong thing)
    if #cols ~= #s.ratios then
        return
    end

    -- Compute current free width (after UI resize)
    local free = 0
    for i, c in ipairs(cols) do
        if not s.ratios[i].fixed then
            free = free + c.width
        end
    end
    if free <= 0 then
        return
    end

    restoring = true
    -- Apply ratios, respect winminwidth, fix rounding on the last adjustable column
    local minw = vim.o.winminwidth
    local remaining = free
    local last_idx = nil
    for i, meta in ipairs(s.ratios) do
        if not meta.fixed then
            last_idx = i
        end
    end

    for i, meta in ipairs(s.ratios) do
        local target
        if meta.fixed then
            -- leave fixed columns alone
            target = cols[i].width
        else
            if i == last_idx then
                target = math.max(minw, remaining) -- dump the remainder here
            else
                target = math.max(minw, math.floor(free * meta.ratio + 0.5))
                remaining = remaining - target
            end
            -- Set the width on a representative leaf in that column
            pcall(vim.api.nvim_win_set_width, cols[i].win, target)
        end
    end
    restoring = false
end

function M.setup(opts)
    opts = opts or {}

    -- Don't fight equalalways; but it tends to equalize things unlike ratios.
    -- If you keep it on elsewhere, set it off here.
    if opts.manage_equalalways ~= false then
        vim.o.equalalways = false
    end

    -- Save on geometry changes *inside* Neovim (not external UI size)
    vim.api.nvim_create_autocmd({ "WinResized", "WinNew", "WinClosed", "TabEnter", "VimEnter" }, {
        group = vim.api.nvim_create_augroup("KeepSplitRatio_Save", { clear = true }),
        callback = function()
            M.save()
        end,
        desc = "KeepSplitRatio: snapshot split ratios for this tab",
    })

    -- Restore on external UI resize only
    vim.api.nvim_create_autocmd("VimResized", {
        group = vim.api.nvim_create_augroup("KeepSplitRatio_Restore", { clear = true }),
        callback = function()
            M.restore()
        end,
        desc = "KeepSplitRatio: restore split ratios after UI resize",
    })

    -- some manual commands for testing
    vim.api.nvim_create_user_command("KeepSplitRatioSave", function()
        M.save()
    end, {})
    vim.api.nvim_create_user_command("KeepSplitRatioRestore", function()
        M.restore()
    end, {})
end

return M
