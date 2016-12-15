# vigun
Unclutter your test diet

## What is this?

Runs mocha tests from vim in a separate tmux window.

There are three ways to do it: all tests in current file, test under cursor and test under cursor in debug mode (chrome devtools).

Also supports rspec and cucumber/cucumberjs for good measure.

Comes with mappings that you can't overwrite:

`<leader>t` - run all tests in current file

`<leader>T` - run test under cursor

`<leader>D` - run test under cursor in debug mode

### Gotcha

Assumes `mocha` is in the `$PATH`.

I always add the entire `node_modules/.bin` into the `$PATH` using [direnv](https://direnv.net/). Give it a try. It is useful well beyond this plugin.

### Bonus

If you happen to run tests in karma, you may appreciate `<leader>o` binding. It toggles `.only` for a test under cursor.
