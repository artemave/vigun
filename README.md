# vigun [![CircleCI](https://circleci.com/gh/artemave/vigun.svg?style=svg)](https://circleci.com/gh/artemave/vigun)
Unclutter your test diet.

## What is this?

Vim plugin to run tests in a separate tmux window.

Out of the box it works with mocha, rspec and cucumber. Other test frameworks can be supported through some configuration.

## Installation

Use [a plugin manager](https://github.com/junegunn/vim-plug):

```vim script
Plug 'artemave/vigun'
```

## Usage

Vigun comes with no mappings, but it does add the following commands:

#### VigunRun

Run test(s). Requires an argument that refers to one of the commands from [g:vigun_mappings](#gvigun_mappings).

For example, with default mappings, for mocha:

`:VigunRun 'all'` runs all tests in a current file.

<img src="https://user-images.githubusercontent.com/23721/27877373-432ad0e2-61b2-11e7-947e-6c563b2275a0.gif" width=500>

`:VigunRun 'nearest'` runs test under cursor.

<img src="https://user-images.githubusercontent.com/23721/27878507-582bfee0-61b6-11e7-902d-ddcccd952b2a.gif" width=500>

`:VigunRun 'debug-nearest'` starts debug session for test under cursor. By default, for mocha, this will use `--inspect-brk` and copy the debug url into OS clipboard. Open new Chrome window/tab and paste it into the address bar.

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
au FileType {ruby,javascript,typescript,cucumber} nnoremap <leader>t :VigunRun 'all'<cr>
au FileType {ruby,javascript,typescript,cucumber} nnoremap <leader>T :VigunRun 'nearest'<cr>
au FileType {ruby,javascript,typescript,cucumber} nnoremap <leader>d :VigunRun 'debug-nearest'<cr>
au FileType {javascript,typescript} nnoremap <Leader>vo :VigunToggleOnly<cr>
au FileType {ruby,javascript,typescript,go} nnoremap <leader>vi :VigunShowSpecIndex<cr>
```

## Configuration

### g:vigun_mappings

Out of the box, vigun runs mocha, rspec and cucumber. You can add support for new frameworks or modify the default ones:

```vim script
let g:vigun_mappings = [
      \ {
      \   'pattern': 'Spec.js$',
      \   'all': './node_modules/.bin/mocha #{file}',
      \   'nearest': './node_modules/.bin/mocha --fgrep #{nearest_test} #{file}',
      \   'debug-all': './node_modules/.bin/mocha --inspect-brk --no-timeouts #{file}',
      \   'debug-nearest': './node_modules/.bin/mocha --inspect-brk --no-timeouts --fgrep #{nearest_test} #{file}',
      \ },
      \ {
      \   'pattern': '_spec.rb$',
      \   'all': 'rspec #{file}',
      \   'nearest': 'rspec #{file}:#{line}',
      \ },
      \ {
      \   'pattern': '.feature$',
      \   'all': 'cucumber #{file}',
      \   'nearest': 'cucumber #{file}:#{line}',
      \ },
      \]
```

Each mapping has a `pattern` property that will be tested against the current file name. Note that `pattern` is a regular expression, not a glob. Also note that the match order matters - the block with the first matched `pattern` is selected to run tests.

All other properties represent various ways to run tests. All occurances of `#{file}`, `#{line}` and `#{nearest_test}` in the property value are interpolated based on the current cursor position. You can name the properties whatever you like and then invoke commands via `VigunRun 'your-key'`. For example, let's add watch commands:

```vim script
" Note: requires ripgrep and entr
fun! s:watch(cmd)
  return "rg --files | entr -r -d -c sh -c 'echo ".escape('"'.a:cmd.'"', '"')." && ".a:cmd."'"
endf

let g:vigun_mappings = [
      \ {
      \   'pattern': '_spec.rb$',
      \   'all': 'rspec #{file}',
      \   'nearest': 'rspec #{file}:#{line}',
      \   'watch-all': s:watch('rspec #{file}'),
      \   'watch-nearest': s:watch('rspec #{file}:#{line}'),
      \ },
      \]

au FileType {ruby} nnoremap <leader>tw :VigunRun 'watch-all'<cr>
au FileType {ruby} nnoremap <leader>Tw :VigunRun 'watch-nearest'<cr>
```

#### Magic property names

Mapping property names are arbitrary. However, there is one name based vigun feature that applies to Mocha (or anything else that makes use of .only). If vigun detects that there is `.only` test in the current file, it uses `*all` command instead of `*nearest` (e.g., `VigunRun 'debug-nearest'` will run `debug-all` command instead). This is because mocha applies both `.only` and `--fgrep` and the result is likely to be empty.

### g:vigun_test_keywords

A line that starts with one of the following, is considered a start of the test and is used to work out `#{nearest_test}`:

```vim script
let g:vigun_test_keywords = ['[Ii]ts\?', '[Cc]ontext', '[Dd]escribe', 'xit', '[Ff]eature', '[Ss]cenario', 'test']
```

Overwrie `g:vigun_test_keywords` to suit your needs.

### g:vigun_tmux_window_name

Name of the tmux window where tests commands are sent. Defaults to `test`.

## Running Plugin Tests

```
git clone https://github.com/junegunn/vader.vim.git
./run_tests
```
