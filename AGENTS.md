# Repository Guidelines

## Project Structure & Module Organization
- `plugin/vigun.vim` — core Vimscript entry: user commands (`:VigunRun`, `:VigunShowSpecIndex`, etc.).
- `lua/vigun/treesitter.lua` — Lua helpers for test discovery and titles (Neovim Treesitter).
- `test/*.vader` — Vader specs; `test/vimrc` sets up the test environment.
- `run_tests` — test runner script (Neovim required); clones `vader.vim` on first run.
- `.circleci/config.yml` — CI pipeline running `./run_tests` on Neovim stable.

## Build, Test, and Development Commands
- `./run_tests` — run the full test suite.
- `./run_tests test/run_ruby_tests.vader` — run a specific file.
- `./run_tests 'test/regressions/*.vader'` — run a subset via glob.
- Local dev: open files in `plugin/` and `lua/` and reload the plugin or restart Neovim. For manual checks, use the provided `:Vigun*` commands in a tmux session.

## Coding Style & Naming Conventions
- Vimscript: 2‑space indentation. Use script‑local functions (`s:Name`) for private helpers and `vigun#Name` for public API. Keep commands and options grouped.
- Lua: 2‑space indentation, `local` by default, return a module table. Use snake_case for files and identifiers.
- Strings passed to shell commands must be properly escaped; follow the existing escaping in `RenderCmd` and Treesitter helpers.

## Testing Guidelines
- Framework: [Vader.vim]. Add `.vader` files under `test/` with descriptive names (e.g., `run_pytest_tests.vader`).
- Run tests with `./run_tests` (uses Neovim). Tests should be deterministic and not depend on external tmux state; set `let g:vigun_dry_run = 1` in tests when sending commands.
- When adding features that affect Treesitter behavior, cover JS/TS, Ruby, and Python paths where applicable.

## Commit & Pull Request Guidelines
- Commits: short, imperative, and scoped (e.g., “Fix context in test title”, “Add flutter test keywords”). Group related changes.
- PRs: include a clear description, rationale, and brief usage notes. Link issues when relevant and add before/after screenshots or GIFs for UX changes. Update `README.md` for new mappings, options, or commands, and include tests.

## Security & Configuration Tips
- Avoid shell injection: never concatenate untrusted input into command templates. Prefer placeholders `#{file}`, `#{line}`, `#{nearest_test}` and the existing render/escape path.
- User‑facing options live in `g:vigun_*` (e.g., `g:vigun_mappings`, `g:vigun_tmux_window_name`). Document new options in `README.md`.

