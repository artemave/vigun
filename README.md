# vigun [![CircleCI](https://circleci.com/gh/artemave/vigun.svg?style=svg)](https://circleci.com/gh/artemave/vigun)
Unclutter your test diet

## What is this?

Vim plugin to run tests in a separate tmux window.

Out of the box it works with mocha, rspec and cucumber. A lot more can be supported through custom config.

## Installation

Use [a plugin manager](https://github.com/VundleVim/Vundle.vim):

```vim script
Plugin 'artemave/vigun'
```

## Usage

Vigun comes with no bindings, but does add the following commands:

**`:VigunRunTestFile`** - run all tests in a current file.

<img src="https://user-images.githubusercontent.com/23721/27877373-432ad0e2-61b2-11e7-947e-6c563b2275a0.gif" width=500>

**`:VigunRunNearestTest`** - run test under cursor.

<img src="https://user-images.githubusercontent.com/23721/27878507-582bfee0-61b6-11e7-902d-ddcccd952b2a.gif" width=500>

**`:VigunRunNearesTestDebug`** - start debug session for test under cursor. By default, for mocha, this will use `--inspect-brk` and copy the debug url into OS clipboard. Open new Chrome window/tab and paste it into the address bar.

**`:VigunShowSpecIndex`** - open quickfix window to quickly navigate between the tests.

<img src="https://user-images.githubusercontent.com/23721/27877502-ce1cbde6-61b2-11e7-93f6-3115dc339266.gif" width=500>

**`:VigunCurrentTestBefore`** - fold everything, except current test and all relevant setup code (e.g. before/beforeEach blocks).

<img src="https://user-images.githubusercontent.com/23721/27878467-405c959a-61b6-11e7-9048-96f8d5e43011.gif" width=500>

**`:VigunMochaOnly`** - toggle `.only` for a current test/context/describe.

<img src="https://user-images.githubusercontent.com/23721/27878536-7ba3e8c4-61b6-11e7-9254-c0f4bb569f68.gif" width=500>

### Example bindings

```vim script
au FileType {ruby,javascript,cucumber} nnoremap <leader>t :VigunRunTestFile<cr>
au FileType {ruby,javascript,cucumber} nnoremap <leader>T :VigunRunNearestTest<cr>
au FileType javascript nnoremap <leader>D :VigunRunNearestTestDebug<cr>
au FileType javascript nnoremap <Leader>o :VigunMochaOnly<cr>
au FileType {ruby,javascript} nnoremap <leader>i :VigunShowSpecIndex<cr>
```

## Custom test commands

The default commands are `mocha` for javascript, `rspec` for ruby and `cucumber` for cucumber. Those can be changed. For example if some of your tests are DOM tests, then you may want to use [electron-mocha](https://github.com/jprichardson/electron-mocha) and [cucumber-electron](https://github.com/cucumber/cucumber-electron) instead of mocha and cucumber. The following setting (best kept in [project vimrc](https://andrew.stwrt.ca/posts/project-specific-vimrc/)) will do the trick:

```vim script
let g:vigun_commands = [
      \ {
      \   'pattern': 'browser/.*Spec.js$',
      \   'normal': 'electron-mocha --renderer',
      \   'debug': 'electron-mocha --interactive --no-timeouts',
      \ },
      \ {
      \   'pattern': '.feature$',
      \   'normal': 'cucumber-electron',
      \   'debug': 'cucumber-electron --electron-debug',
      \ },
      \ {
      \   'pattern': 'Spec.js$',
      \   'normal': 'mocha',
      \   'debug': 'electron-mocha --interactive --no-timeouts',
      \ },
      \]
```

Note that `pattern` is a regular expression (not glob). Also note that match order matters, so it should go from more specific to less specific.


By default lines that start with `it(`, `describe(`, `context(` are considered test boundaries. This can be extended:

```vim script
let g:vigun_extra_keywords = ['feature', 'scenario', 'example']
```

Both of the above combined can be used to run a lot of different types of tests.

## Running Plugin Tests

```
git clone https://github.com/junegunn/vader.vim.git
./run_tests
```
