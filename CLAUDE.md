# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**vigun** is a Vim/Neovim plugin that runs tests in separate tmux windows to "unclutter your test diet". It supports multiple test frameworks including Mocha, RSpec, Cucumber, pytest, and Node.js test runner.

## Development Commands

### Running Tests
```bash
./run_tests                    # Run all tests using Vader.vim
./run_tests test/specific.vader # Run specific test file
```

The test runner uses Vader.vim testing framework and automatically clones it if not present. Tests are run with Neovim in CI and locally.

### Development Environment
- Requires Vim/Neovim and tmux for full functionality
- Tests use Vader.vim framework (included as git submodule)
- CircleCI for continuous integration

## Code Architecture

### Core Plugin Structure
- **`plugin/vigun.vim`** (380 lines): Main plugin file containing all functionality
- **`test/`**: Comprehensive test suite with Vader.vim tests and regression tests
- **`run_tests`**: Bash script that handles test execution

### Key Components

**Test Execution Engine** (`s:RunTests()`, lines 76+):
- Pattern matching system maps file types to test commands via `g:vigun_mappings`
- Supports command interpolation with `#{file}`, `#{line}`, `#{nearest_test}` placeholders
- Handles "magic" behavior where `.only` presence switches `nearest` to `all` commands

**tmux Integration** (`s:SendToTmux()`, `s:EnsureTestWindow()`):
- Creates/manages dedicated tmux test windows
- Supports both separate windows and panes within current window
- Handles window-to-pane toggling via `VigunToggleTestWindowToPane`

**Test Name Parsing** (`vigun#TestTitle()`, various functions):
- Extracts test names from multiple frameworks using configurable keywords
- Supports nested test contexts (describe/context blocks)
- Special handling for different test naming patterns

### Default Test Framework Mappings

```vim
" Node.js test runner: .(spec|test).js$
" Mocha: Spec.js$
" pytest: _test.py$
" RSpec: _spec.rb$
" Cucumber: .feature$
```

Each mapping defines `all`, `nearest`, and optional `debug-*` commands.

### Configuration System

Key global variables:
- `g:vigun_mappings`: Test framework configurations
- `g:vigun_test_keywords`: Keywords that identify test lines
- `g:vigun_tmux_window_name`: Name of tmux test window (default: 'test')
- `g:vigun_tmux_pane_orientation`: Pane split direction

### Commands Available
- `VigunRun <mode>`: Execute tests with specified mode
- `VigunShowSpecIndex`: Generate QuickFix navigation for tests
- `VigunToggleOnly`: Toggle `.only` for focused testing
- `VigunCurrentTestBefore`: Fold code to show only current test + setup
- `VigunToggleTestWindowToPane`: Switch between tmux window/pane modes

## Testing Strategy

The plugin has comprehensive test coverage including:
- Framework integration tests (Mocha, pytest, RSpec)
- Test name parsing and extraction
- Context handling and nested describe blocks
- Regression tests for specific bug fixes
- tmux integration and command execution

When making changes, always run the full test suite with `./run_tests` to ensure compatibility across supported test frameworks.
