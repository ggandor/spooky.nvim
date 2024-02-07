local api = vim.api


local function select_remotely (jumper, selector, event_data)
  local register = vim.v.register
  local mode = vim.fn.mode(true)
  local op_mode = mode:match('o')
  -- `jumper` can mess with these, should save here.
  local state = { mode = mode, count = vim.v.count1 }
  local saved_view = vim.fn.winsaveview()
  -- Handle cross-window operations.
  local source_win = vim.fn.win_getid()
  -- Set an extmark as an anchor, so that we can execute remote delete
  -- commands in the backward direction, and move together with the text.
  local anch_ns
  local anch_id
  if op_mode then
    anch_ns = api.nvim_create_namespace('')
    anch_id = api.nvim_buf_set_extmark(
      0, anch_ns, saved_view.lnum - 1, saved_view.col, {}
    )
  end

  jumper()
  selector(state)

  -- In O-P mode, the operation itself will be executed after exiting this
  -- function. We can set up an autocommand for follow-up stuff, triggering
  -- on mode change:
  if op_mode then
    local restore_cursor = function ()
      if vim.fn.win_getid() ~= source_win then
        api.nvim_set_current_win(source_win)
      end
      vim.fn.winrestview(saved_view)
      local anch_pos = api.nvim_buf_get_extmark_by_id(0, anch_ns, anch_id, {})
      api.nvim_win_set_cursor(0, { anch_pos[1] + 1, anch_pos[2] })
    end

    api.nvim_create_augroup('SpookyDefault', {})
    api.nvim_create_autocmd('ModeChanged', {
      group = 'SpookyDefault',
      -- We might return to Insert mode if doing an i_CTRL-O stunt,
      -- but make sure we never trigger on it when doing _change_
      -- operations (then we enter Insert mode for doing the change
      -- itself, and should wait for returning to Normal).
      pattern = vim.v.operator == 'c' and '*:n' or '*:[ni]',
      once = true,
      callback = function ()
        api.nvim_exec_autocmds('User', {
          pattern = 'SpookyOperationDone',
          data = vim.tbl_extend('error', event_data or {}, {
            register = register,
            restore_cursor = restore_cursor,
          })
        })
        api.nvim_buf_clear_namespace(0, anch_ns, 0, -1)
      end,
    })
  end
end


local function create_text_object (mapping, jumper, selector, opts)
  local opts = opts or {}
  local event_data = opts.event_data or {}
  event_data.mapping = mapping
  vim.keymap.set({'x', 'o'}, mapping, function ()
    select_remotely(jumper, selector, event_data)
  end)
end


-- Convenience layer
--------------------

local default_text_objects = {
  'iw', 'iW', 'is', 'ip', 'i[', 'i]', 'i(', 'i)', 'ib',
  'i>', 'i<', 'it', 'i{', 'i}', 'iB', 'i"', 'i\'', 'i`',
  'aw', 'aW', 'as', 'ap', 'a[', 'a]', 'a(', 'a)', 'ab',
  'a>', 'a<', 'at', 'a{', 'a}', 'aB', 'a"', 'a\'', 'a`',
}

local v_exit = function ()
  local mode = vim.fn.mode(true)
  -- v/V/<C-v> exits the Corresponding Visual mode if already in it.
  return mode:match('o') and '' or mode:sub(1,1)
end

local force_exclusive = function(negative_range)
  -- To fill '> and '< with the current selection.
  vim.cmd('normal! vgv')
  local single_col = vim.fn.getpos("'<")[3] == vim.fn.getpos("'>")[3]
  -- TODO: unimportant edge case, but could we achieve native behavior
  --       (select nothing) for single_col + exclusive?
  if single_col then
    return
  end
  vim.cmd('normal! ' .. (negative_range and 'oh' or 'h'))
end

local function selector (textobj)
  return function(state)
    local force = state.mode:match('o') and state.mode:sub(3) or ''
    -- v/V/<C-v> exits the corresponding Visual mode if already in it.
    vim.cmd('normal! ' .. v_exit() .. 'v')
    -- No bang - custom text objects should work too.
    vim.cmd.normal(state.count .. textobj)
    if force ~= '' then
      if force == 'v' then force_exclusive() else vim.cmd('normal! ' .. force) end
    end
  end
end


local selectors = {
  lines = function (state)
    -- Note: [count]V would not work, its behaviour depends on the previous
    -- Visual operation, see `:h V`.
    local n_js = state.count - 1
    local js = n_js > 0 and (tostring(n_js) .. 'j') or ''
    vim.cmd('normal! ' .. v_exit() .. 'V' .. js)
  end,

  range = function (state, kwargs)
    local kwargs = kwargs or {}
    local jumper = kwargs.jumper or function ()
      require('leap').leap {
        opts = { safe_labels = {} },  -- disable autojump
        target_windows = { api.nvim_get_current_win() },
      }
    end
    local force = state.mode:match('o') and state.mode:sub(3) or ''
    local v_exit = v_exit()
    local mode1 = state.mode:sub(1,1)
    local restore_vmode = (mode1 == 'V' and mode1) or (mode1 == '' and mode1)

    if v_exit ~= '' then
      vim.cmd('normal! ' .. v_exit)
    end

    local negative_range
    local _, l1, c1, _ = unpack(vim.fn.getpos('.'))

    vim.cmd('normal! v')
    -- TODO: handle interrupted operation
    -- TODO: handle <esc>/error, cleanup etc
    jumper()

    local _, l2, c2, _ = unpack(vim.fn.getpos('.'))
    if l2 < l2 or c2 < c1 then negative_range = true end

    if restore_vmode then
        vim.cmd('normal! ' .. restore_vmode)
    end
    if force ~= '' then
      if force == 'v' then
        force_exclusive(negative_range)
      else
        vim.cmd('normal! ' .. force)
      end
    end
  end
}


local function setup ()
  local affix = 'r'
  local jumper = function ()
    require('leap').leap {
      opts = { safe_labels = {} },  -- disable autojump
      target_windows = vim.tbl_filter(
        function (win) return api.nvim_win_get_config(win).focusable end,
        api.nvim_tabpage_list_wins(0)
      ),
    }
  end
  for _, tobj in ipairs(default_text_objects) do
    local mapping = tobj:sub(1,1) .. affix .. tobj:sub(2)
    create_text_object(mapping, jumper, selector(tobj))
  end
end

return {
  select_remotely = select_remotely,
  create_text_object = create_text_object,
  default_text_objects = default_text_objects,
  selector = selector,
  selectors = selectors,
  setup = setup,
}
