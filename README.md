# vigun
Unclutter your test diet.

## What is this?

Vim plugin to run mocha tests from vim in a separate tmux window.

[![demo](https://img.youtube.com/vi/zFPePu4K_U0/0.jpg)](https://www.youtube.com/watch?v=zFPePu4K_U0)

Also supports rspec and cucumber/cucumberjs for good measure.

## Installation

Use your [favourite pluging manager](https://github.com/VundleVim/Vundle.vim):

```
Plugin 'artemave/vigun'
```

Then drop in these mappings:

```
au FileType {ruby,javascript,cucumber} nnoremap <leader>t :RunTestFile<cr>
au FileType {ruby,cucumber} nnoremap <leader>T :RunNearestTest<cr>
au FileType javascript nnoremap <leader>T :RunNearestMochaTest 'normal'<cr>
au FileType javascript nnoremap <leader>D :RunNearestMochaTest 'debug'<cr>
```

And this will add the following:

`<leader>t` - run all tests in a current file

`<leader>T` - run test under cursor

`<leader>D` - start debug session for test under cursor. This copies the debug url into OS clipboard. Open new Chrome window/tab and paste it into the address bar.

## More

The default command is `mocha`. This can be changed. For example if some of your tests are DOM tests that run through [electron-mocha](https://github.com/jprichardson/electron-mocha), then the following setting in your [project vimrc](https://andrew.stwrt.ca/posts/project-specific-vimrc/) will make any test in `test/browser` run via electron-mocha:

```
let g:vigun_mocha_commands = [
      \ {
      \   'pattern': 'browser/.*Spec.js$',
      \   'normal': 'electron-mocha --renderer',
      \   'debug': 'electron-mocha --interactive --no-timeouts',
      \ },
      \ {
      \   'pattern': 'Spec.js$',
      \   'normal': 'mocha',
      \   'debug': 'mocha --inspect --debug-brk --no-timeouts',
      \ },
      \]
```

Note that `pattern` is a regular expression (not glob). Also note that match order matters, so it should go from more specific to less specific.


By default lines that start with `it(`, `describe(`, `context(` are considered test boundaries. This can be extended:

```
let g:vigun_extra_keywords = ['feature', 'scenario', 'example']
```

## Gotcha

Assumes `mocha` is in the `$PATH`.

I always add the entire `node_modules/.bin` into the `$PATH` using [direnv](https://direnv.net/). Give it a try. It is useful well beyond this plugin.

## Bonus

If you happen to run tests in karma, you may appreciate `MochaOnly` command. It toggles `.only` for a test under cursor. I am mapping it to `<leader>o`:

```
au FileType javascript nnoremap <Leader>o :MochaOnly<cr>
```

Another useful command is `ShowSpecIndex`. It opens up quickfix window with describe/it/context/etc titles so you can quickly navigate between different tests. It looks like this:

<img src="https://cloud.githubusercontent.com/assets/23721/22613634/d5b7bb2c-ea71-11e6-8937-5f36bf61030d.png" width=500>

I am mapping it to `<leader>i`

```
nnoremap <Leader>i :ShowSpecIndex<cr>
```
