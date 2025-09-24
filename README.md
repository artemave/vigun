# vigun
Unclutter your test diet.

## What is this?

Vim plugin to run tests in a separate tmux window.

## Installation

Using [lazy](https://lazy.folke.io/):

```lua
require("lazy").setup({
  { "artemave/vigun" }
})
```

## Usage

Vigun comes with no mappings, but it does add the following commands:

#### VigunRun

Run test(s): `:VigunRun <mode>`. The `<mode>` is any name you define in your runner’s `commands` table (see Configuration).

If invoked from a non‑test file, `:VigunRun <mode>` will attempt to run the last command.

#### VigunToggleTestWindowToPane

Join tmux test window as a into the current vim window. Split out into a separate window if it's already a pane.

#### VigunShowSpecIndex

Open quickfix window to quickly navigate between the tests.

#### VigunCurrentTestBefore

Fold everything, except current test and all relevant setup code (e.g. before/beforeEach blocks).

#### VigunToggleOnly

Toggle `.only` for a current test/context/describe.

### Example bindings

Example bindings for user‑defined modes (here: `file`, `focus`, `debug-focus`):

```vim script
au FileType {ruby,javascript,typescript,cucumber} nnoremap <leader>t :VigunRun file<cr>
au FileType {ruby,javascript,typescript,cucumber} nnoremap <leader>T :VigunRun focus<cr>
au FileType {ruby,javascript,typescript,cucumber} nnoremap <leader>d :VigunRun debug-focus<cr>
```

## Configuration

### Treesitter

Vigun relies on Treesitter for test discovery and folding. Ensure Neovim has relevant parsers installed for your languages. Example:

```
:TSInstall javascript typescript ruby python
```

### Lua setup()

Configure frameworks with Lua. Call `setup()` once or multiple times; each call merges into previous configuration.

Example enabling rspec, pytest, and minitest_rails under the `runners` key with top‑level options. Command names are arbitrary and user‑defined:

```lua
require('vigun').setup({
  tmux_window_name = 'test',
  tmux_pane_orientation = 'vertical',
  remember_last_command = true,
  runners = {
    rspec = {
      enabled = function()
        return vim.fn.expand('%'):match('_spec%.rb$') ~= nil
      end,
      test_nodes = { 'it', 'xit' },
      context_nodes = { 'describe', 'context' },
      commands = {
        file = function(_)
          return 'rspec ' .. vim.fn.expand('%')
        end,
        focus = function(_)
          return 'rspec ' .. vim.fn.expand('%') .. ':' .. vim.fn.line('.')
        end,
      },
    },
    pytest = {
      enabled = function()
        return vim.fn.expand('%'):match('_test%.py$') ~= nil
      end,
      test_nodes = function(node, name)
        return node and node:type() == 'function_definition' and type(name) == 'string' and name:match('^test_') ~= nil
      end,
      context_nodes = function(node, _)
        return node and node:type() == 'class_definition'
      end,
      commands = {
        file = function(_)
          return 'pytest -s ' .. vim.fn.expand('%')
        end,
        focus = function(info)
          local quoted = vim.fn.shellescape(info.test_title)
          return 'pytest -k ' .. quoted .. ' -s ' .. vim.fn.expand('%')
        end,
        ['debug-file'] = function(_)
          return 'pytest -vv -s ' .. vim.fn.expand('%')
        end,
        ['debug-focus'] = function(info)
          local quoted = vim.fn.shellescape(info.test_title)
          return 'pytest -vv -k ' .. quoted .. ' -s ' .. vim.fn.expand('%')
        end,
      },
    },
    minitest_rails = {
      enabled = function()
        return vim.fn.expand('%'):match('_test%.rb$') ~= nil
      end,
      commands = {
        file = function(_)
          return 'rails test ' .. vim.fn.expand('%')
        end,
        focus = function(_)
          return 'rails test ' .. vim.fn.expand('%') .. ':' .. vim.fn.line('.')
        end,
      },
   },
  }
})
```

You can call `setup()` again (e.g., from a project `.exrc`) to override or add commands. Options are top‑level; runners live under `runners`:

```lua
require('vigun').setup({
  runners = {
  mocha = {
    commands = {
      file = function(_)
        return 'electron-mocha --renderer ' .. vim.fn.expand('%')
      end,
    },
  },
}})
```

### Options

Options are top‑level keys of `setup()`:

- `tmux_window_name`: name of the tmux window for tests (default: `test`).
- `tmux_pane_orientation`: `vertical` or `horizontal` for `:VigunToggleTestWindowToPane` (default: `vertical`).
- `remember_last_command`: rerun last command if no matching command is found (default: `true`).

### on_result callback

Attach a per‑runner `on_result` to react to a finished run.

`on_result` takes an `info` argument with the following fields:
  - `command`: exact command sent to tmux
  - `mode`: the exact mode name you invoked (whatever you defined)
  - `file`: current buffer filename at start
  - `output`: output of the command
  - `started_at`, `ended_at`: timestamps

Example: populate diagnostics from failures

```lua
require('vigun').setup({
  runners = {
    rspec = {
      -- ... other rspec config ...
      on_result = function(info)
        local ns = vim.api.nvim_create_namespace('vigun.tests')
        vim.diagnostic.reset(ns)
        local by_buf = {}
        for path, line, msg in info.output:gmatch("([%./%w%-%_%/]+):(%d+):%s*(.-)\n") do
          local bufnr = vim.fn.bufnr(vim.fn.fnamemodify(path, ':p'), true)
          by_buf[bufnr] = by_buf[bufnr] or {}
          table.insert(by_buf[bufnr], {
            lnum = tonumber(line) - 1,
            col = 0,
            message = msg ~= '' and msg or 'Test failure',
            severity = vim.diagnostic.severity.ERROR,
            source = 'vigun',
          })
        end
        for bufnr, items in pairs(by_buf) do
          vim.diagnostic.set(ns, bufnr, items, { underline = true, virtual_text = true })
        end
      end,
    },
  },
})
```

You can adapt the parser to your runner’s format (RSpec, Minitest, PyTest, etc.) or populate quickfix/loclist instead of diagnostics.

## Running Plugin Tests

- `./run_vader_test` — run Vader specs.
- `./run_vader_test test/run_ruby_tests.vader` — run a specific Vader file.
- `./run_vader_test 'test/regressions/*.vader'` — run a subset via glob.
- `./run_lua_tests` — run Lua tests (Plenary/Busted).
- `./run_tests` — run both suites in sequence.
