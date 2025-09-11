# vigun [![CircleCI](https://circleci.com/gh/artemave/vigun.svg?style=svg)](https://circleci.com/gh/artemave/vigun)
Unclutter your test diet.

## What is this?

Vim plugin to run tests in a separate tmux window.

Out of the box it works with mocha, rspec and cucumber. Other test frameworks can be supported through some configuration.

Treesitter: Vigun uses Neovim Treesitter to find the nearest test, build precise test titles (optionally including context), toggle `.only`, and fold non‑relevant tests. For best results, use Neovim with Treesitter parsers installed (e.g., `:TSInstall javascript typescript ruby python`).

## Installation

Use [a plugin manager](https://github.com/junegunn/vim-plug):

```vim script
Plug 'artemave/vigun'
```

## Usage

Vigun comes with no mappings, but it does add the following commands:

#### VigunRun

Run test(s). Requires an argument matching a configured command (see Configuration).

For example, with default mappings, for mocha:

`:VigunRun all` runs all tests in a current file.

<img src="https://user-images.githubusercontent.com/23721/27877373-432ad0e2-61b2-11e7-947e-6c563b2275a0.gif" width=500>

`:VigunRun nearest` runs test under cursor.

<img src="https://user-images.githubusercontent.com/23721/27878507-582bfee0-61b6-11e7-902d-ddcccd952b2a.gif" width=500>

`:VigunRun debug-nearest` starts debug session for test under cursor. By default, for mocha, this will use `--inspect-brk` and copy the debug url into OS clipboard. Open new Chrome window/tab and paste it into the address bar.

If invoked from a non-test file, `VigunRun` (with any argument) will attempt to run the last command.

#### VigunToggleTestWindowToPane

Move tmux test window into a pane of the current vim window. And vice versa.

#### VigunShowSpecIndex

Open quickfix window to quickly navigate between the tests.

<img src="https://user-images.githubusercontent.com/23721/27877502-ce1cbde6-61b2-11e7-93f6-3115dc339266.gif" width=500>

#### VigunCurrentTestBefore

Fold everything, except current test and all relevant setup code (e.g. before/beforeEach blocks).

<img src="https://user-images.githubusercontent.com/23721/27878467-405c959a-61b6-11e7-9048-96f8d5e43011.gif" width=500>

#### VigunToggleOnly

Toggle `.only` for a current test/context/describe.

<img src="https://user-images.githubusercontent.com/23721/27878536-7ba3e8c4-61b6-11e7-9254-c0f4bb569f68.gif" width=500>

### Example bindings

```vim script
au FileType {ruby,javascript,typescript,cucumber} nnoremap <leader>t :VigunRun all<cr>
au FileType {ruby,javascript,typescript,cucumber} nnoremap <leader>T :VigunRun nearest<cr>
au FileType {ruby,javascript,typescript,cucumber} nnoremap <leader>d :VigunRun debug-nearest<cr>
au FileType {javascript,typescript} nnoremap <Leader>vo :VigunToggleOnly<cr>
au FileType {ruby,javascript,typescript,go} nnoremap <leader>vi :VigunShowSpecIndex<cr>
```

## Configuration

### Treesitter

Vigun relies on Treesitter for test discovery and folding. Ensure Neovim has relevant parsers installed for your languages. Example:

```
:TSInstall javascript typescript ruby python
```

If a parser is missing, features like `:VigunRun nearest`, `:VigunToggleOnly`, and `:VigunCurrentTestBefore` may not work as expected.

### Lua setup()

Configure frameworks with Lua. Call `setup()` once or multiple times; each call merges into previous configuration (lists overwrite, tables deep‑merge).

Example enabling mocha, rspec, pytest, and minitest_rails under the `runners` key with top‑level options:

```lua
require('vigun').setup({
  tmux_window_name = 'test',
  tmux_pane_orientation = 'vertical',
  remember_last_command = true,
  runners = {
  mocha = {
    enabled = function()
      return vim.fn.expand('%'):match('Spec%.js$') ~= nil
    end,
    test_nodes = { 'it', 'xit' },
    context_nodes = { 'context', 'describe' },
    commands = {
      all = function(_)
        return './node_modules/.bin/mocha ' .. vim.fn.expand('%')
      end,
      ['debug-all'] = function(_)
        return './node_modules/.bin/mocha --inspect-brk --no-timeouts ' .. vim.fn.expand('%')
      end,
      nearest = function(info)
        local parts = {}
        for _, c in ipairs(info.context_titles) do table.insert(parts, c) end
        table.insert(parts, info.test_title)
        local quoted = vim.fn.shellescape(table.concat(parts, ' '))
        return './node_modules/.bin/mocha --fgrep ' .. quoted .. ' ' .. vim.fn.expand('%')
      end,
      ['debug-nearest'] = function(info)
        local parts = {}
        for _, c in ipairs(info.context_titles) do table.insert(parts, c) end
        table.insert(parts, info.test_title)
        local quoted = vim.fn.shellescape(table.concat(parts, ' '))
        return './node_modules/.bin/mocha --inspect-brk --no-timeouts --fgrep ' .. quoted .. ' ' .. vim.fn.expand('%')
      end,
    },
  },

  rspec = {
    enabled = function()
      return vim.fn.expand('%'):match('_spec%.rb$') ~= nil
    end,
    test_nodes = { 'it', 'xit' },
    context_nodes = { 'describe', 'context' },
    commands = {
      all = function(_)
        return 'rspec ' .. vim.fn.expand('%')
      end,
      nearest = function(_)
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
      all = function(_)
        return 'pytest -s ' .. vim.fn.expand('%')
      end,
      nearest = function(info)
        local quoted = vim.fn.shellescape(info.test_title)
        return 'pytest -k ' .. quoted .. ' -s ' .. vim.fn.expand('%')
      end,
      ['debug-all'] = function(_)
        return 'pytest -vv -s ' .. vim.fn.expand('%')
      end,
      ['debug-nearest'] = function(info)
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
      all = function(_)
        return 'rails test ' .. vim.fn.expand('%')
      end,
      nearest = function(_)
        return 'rails test ' .. vim.fn.expand('%') .. ':' .. vim.fn.line('.')
      end,
    },
  },
}})
```

You can call `setup()` again (e.g., from a project `.exrc`) to override or add commands. Options are top‑level; runners live under `runners`:

```lua
require('vigun').setup({
  runners = {
  mocha = {
    commands = {
      all = function(_)
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

## Running Plugin Tests

```
./run_tests
```
