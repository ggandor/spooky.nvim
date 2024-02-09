# spooky.nvim 👻

Spooky is a Neovim plugin that defines "remote" text objects: that is, it
exposes atomic bundles of jumps and selection commands. It's not just the
number of keystrokes that matter here, but the potentially more intuitive
workflow achieved through these higher abstractions, that are nevertheless
obvious extensions of Vim's grammar. The aim, as usual, is to [sharpen the
saw](http://vimcasts.org/blog/2012/08/on-sharpening-the-saw/): there are no big
list of new commands to learn, except for a single affix that can be added to
all existing text objects. `carb[jump]` ("change a remote block [marked by
jump]") in no time will be just as natural as
[targets.vim](https://github.com/wellle/targets.vim)'s `canb` ("change a[round]
next block").

Spooky uses [Leap](https://github.com/ggandor/leap.nvim) as the default jump
engine, but in fact the plugin is jumper-agnostic - you can use or define any
custom function you want.

## Usage

The jump function is automatically invoked once the text object is specified;
after e.g. `yarw`, select the target as you would usually do, to define the
point of reference for the selection. The difference is that instead of jumping
there, the word will be yanked.

## What are some fun things you can do with this?

- Delete/fold/comment/etc. paragraphs without leaving your position
  (`zfarp[jump]`).
- Clone text objects in the blink of an eye, even from another window
  (`yarp[jump]`).
- Do the above stunt in Insert mode (`...<C-o>yarW[jump]...`).
- Fix a typo with a short, atomic command sequence (`cirw[jump][correction]`).
- Operate on distant lines: `daa[jump]`.
- Use `count`: e.g. `y3aa[jump]` yanks 3 lines, just as `3yy` would do.

## Status

WIP - everything is experimental, no stability guarantees yet.

## Requirements

* [leap.nvim](https://github.com/ggandor/leap.nvim) (for default setup)

## Setup

### Basic setup

```lua
-- `setup` will create remote text objects from all native ones, by
-- inserting `r` into the middle (e.g. `ip` -> `irp`), using Leap as the
-- targeting engine (searching in all windows).
require('spooky').setup()

-- Set "boomerang" behavior and automatic paste after yanking:
vim.api.nvim_create_augroup('SpookyUser', {})
vim.api.nvim_create_autocmd('User', {
  pattern = 'SpookyOperationDone',
  group = 'SpookyUser',
  callback = function (event)
    local op = vim.v.operator
    -- Restore cursor position (except after change operation).
    if op ~= 'c' then event.data.restore_cursor() end
    -- (Auto)paste after yanking and restoring the cursor, if the
    -- unnamed register was used.
    if op == 'y' and event.data.register == '"' then vim.cmd('normal! p') end
  end
})
```

### Customization and extension

#### Text objects

`setup` is just a wrapper over the lower-level method
`create_text_object({mapping}, {jumper}, {selector}, {opts})`.

* `jumper`: a callback that moves the cursor to the reference point.

* `selector`: a callback that visually selects a range.

* `opts`: Dictionary with the following optional fields:
    * `event_data`: dict to send back arbitrary data on `SpookyOperationDone`.
      It will be accessed via the `data` field of the event. By default, `data`
      is filled with:
        * `restore_cursor`: callback to restore the window and the cursor
          position
        * `register`: value of `vim.v.register` at the time of the operation
        * `mapping`: mapping used

```lua
do
  local spooky = require('spooky')

  -- The default jumper used by Spooky.
  local leap_anywhere = function ()
    require('leap').leap {
      opts = { safe_labels = {} },  -- disable autojump
      target_windows = vim.tbl_filter(
        function (win) return vim.api.nvim_win_get_config(win).focusable end,
        vim.api.nvim_tabpage_list_wins(0)
      ),
    }
  end

  -- If you already have a predefined (native or custom) text object,
  -- `selector()` can return a selector that propagates forced motions
  -- properly.
  -- E.g. this is what `setup()` does by default:
  for _, tobj in ipairs(spooky.default_text_objects) do
    local mapping = tobj:sub(1,1) .. 'r' .. tobj:sub(2)
    spooky.create_text_object(mapping, leap_anywhere, spooky.selector(tobj))
  end


  -- The special `range` and `lines` selectors are implemented by
  -- default.

  -- `range` is specified by two consecutive jumps (end-inclusive -
  -- use `v` to make it exclusive).
  spooky.create_text_object('arr', leap_anywhere, spooky.selectors.range)
  -- Line-range.
  -- A `state` table is automatically passed to selector functions as
  -- a first argument, containing the saved values of `vim.fn.mode(true)`
  -- and `vim.v.count1` (the jumper function can mess with those). Make
  -- sure to pass it on if you're wrapping the call.
  spooky.create_text_object('arR', leap_anywhere, function (state)
    spooky.selectors.range(state)
    vim.cmd('normal! V')
  end)
  -- Custom second jumper (default is Leap in current window).
  spooky.create_text_object('arr', leap_anywhere, function (state)
    spooky.selectors.range(state, { jumper = leap_anywhere })
  end)

  -- `lines` is equivalent to `V{op}`, or, if count > 1 is given,
  -- `V[count-1]j{op}` at the given position.
  spooky.create_text_object('aa', leap_anywhere, spooky.selectors.lines)


  -- "Inner remote line" object, with custom selector function.
  spooky.create_text_object('ii', leap_anywhere, function()
    local mode = vim.fn.mode(true)
    -- Exit Visual mode if already in it.
    if not mode:match('o') then vim.cmd('normal! ' .. mode:sub(1,1)) end
    vim.cmd('normal! _vg_')
  end)
end
```

#### Autocommands

More complex autocommand examples:

```lua
vim.api.nvim_create_augroup('SpookyUser', {})
vim.api.nvim_create_autocmd('User', {
  pattern = 'SpookyOperationDone',
  group = 'SpookyUser',
  callback = function (event)
    local op = vim.v.operator
    local mapping = event.data.mapping

    -- Just pattern match on your mappings here if you want
    -- restore/no-restore pairs of text objects. E.g. if you use
    -- the affix `R` for "no-restore":
    if not mapping:match('[ai]R') then
      event.data.restore_cursor()
    end

    -- You can also define default behaviors for operations, like above,
    -- but _invert_ it with `R`:

    -- if ((op ~= 'c' and mapping:match('[ai]R')) or
    --     (op == 'c' and not mapping:match'[ai]R'))
    -- then
    --   event.data.restore_cursor()
    -- end

    -- Besides autopaste on remote yanking, you can implement any other
    -- features here, like automatically reformatting a section after
    -- delete, etc.
  end
})
```
