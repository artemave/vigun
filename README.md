# vigun
Unclutter your test diet.

## What is this?

Runs mocha tests from vim in a separate tmux window.

[![demo](https://img.youtube.com/vi/zFPePu4K_U0/0.jpg)](https://www.youtube.com/watch?v=zFPePu4K_U0)

Comes in three flavors:

`<leader>t` - run all tests in a current file

`<leader>T` - run test under cursor

`<leader>D` - start debug session for test under cursor. This copies the debug url into OS clipboard. Open new Chrome window/tab and paste it into the address bar.

Also supports rspec and cucumber/cucumberjs for good measure.

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

By default lines that start with `it(`, `describe(`, `context(` are considered test boundaries. This can be extended:

```
let g:vigun_extra_keywords = ['feature', 'scenario', 'example']
```

Things to note: `pattern` is a regular expression, not glob; match order matters, so it should go from more specific to less specific.

## Gotcha

Assumes `mocha` is in the `$PATH`.

I always add the entire `node_modules/.bin` into the `$PATH` using [direnv](https://direnv.net/). Give it a try. It is useful well beyond this plugin.

## Bonus

If you happen to run tests in karma, you may appreciate `<leader>o` binding. It toggles `.only` for a test under cursor.
