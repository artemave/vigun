# Repository Guidelines

## Project Structure & Module Organization
- `plugin/vigun.vim` — core Vimscript entry: user commands (`:VigunRun`, `:VigunShowSpecIndex`, etc.).
- `lua/vigun/treesitter.lua` — Lua helpers for test discovery and titles (Neovim Treesitter).
- `test/*.vader` — Vader specs; `test/vimrc` sets up the test environment and clones deps.
- `run_vader_test` — run only Vader specs.
- `run_lua_tests` — run only Lua (Plenary/Busted) tests.
- `run_tests` — aggregate runner that executes both suites.

## Build, Test, and Development Commands
- `./run_vader_test` — run Vader suite.
- `./run_vader_test test/run_ruby_tests.vader` — run a specific Vader file.
- `./run_vader_test 'test/regressions/*.vader'` — run a subset via glob.
- `./run_lua_tests` — run Lua (Plenary/Busted) tests.
- `./run_tests` — run both Vader and Lua tests.
- Local dev: open files in `plugin/` and `lua/` and reload the plugin or restart Neovim. For manual checks, use the provided `:Vigun*` commands in a tmux session.

## Coding Style & Naming Conventions
- Vimscript: 2‑space indentation. Use script‑local functions (`s:Name`) for private helpers and `vigun#Name` for public API. Keep commands and options grouped.
- Lua: 2‑space indentation, `local` by default, return a module table. Use snake_case for files and identifiers.
- Strings passed to shell commands must be properly escaped; follow the existing escaping in `RenderCmd` and Treesitter helpers.

## Testing Guidelines
- Framework: [Vader.vim]. Add `.vader` files under `test/` with descriptive names (e.g., `run_pytest_tests.vader`).
- Run tests with `./run_vader_test` (Vader) and `./run_lua_tests` (Lua). `./run_tests` runs both. Tests should be deterministic and not depend on external tmux state.
- When adding features that affect Treesitter behavior, cover JS/TS, Ruby, and Python paths where applicable.

## Commit & Pull Request Guidelines
- Don't commit anything

## IMPORTANT
- Do not remove comments that start with -- TODO:
- Avoid defensive conditional such as `if xyz == nil then retrun end`. I really want to see errors early.
- Don't join lines with `;`. Use separate lines
