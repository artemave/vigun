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

### Bonus

If you happen to run tests in karma, you may appreciate `<leader>o` binding. It toggles `.only` for a test under cursor.
