if exists("g:vigun_loaded")
  finish
endif
let g:vigun_loaded = 1
let g:vigun_remember_last_command = 1

fun! s:EnsureTestWindow()
  if exists('s:tmux_pane_id')
    call system('tmux list-panes -t '.s:tmux_pane_id)
    if v:shell_error == 0
      return
    endif
  endif

  call system("tmux list-windows -F '#{window_name}' | grep -w ".g:vigun_tmux_window_name)
  if v:shell_error
    call system('tmux new-window -d -n '.g:vigun_tmux_window_name)
  endif
  let s:tmux_pane_id = system("tmux list-panes -F '#{pane_id}' -t ".g:vigun_tmux_window_name)
endf

function s:SendToTmux(command)
  if exists("g:vigun_dry_run")
    echom a:command
    return
  endif

  call s:EnsureTestWindow()

  call system('tmux select-window -t '.g:vigun_tmux_window_name)
  if v:shell_error " -> we can't select test window because there isn't any since it's been moved to a pane next to vim
    let vim_pane_id = system("echo -n $TMUX_PANE")
    call system('tmux select-pane -t '.s:tmux_pane_id)
  endif

  " send C-c in case something (e.g. entr) is running in the test window
  call system('tmux send-keys C-c')

  call system('tmux send-keys "'. a:command .'" Enter')

  " focus back to vim pane if test pane is in the same window
  if exists('vim_pane_id')
    call system('tmux select-pane -t '.vim_pane_id)
  endif
endfunction

function s:RunTests(mode)
  let config = s:GetConfigForCurrentFile()

  if !empty(config)
    wa
    let cmd = get(config, a:mode, config.all)

    if (match(a:mode, 'nearest') > -1) && s:IsOnlySet()
      let cmd = get(config, substitute(a:mode, 'nearest', 'all', ''), cmd)
    endif

    let nearest_test_title = get(config, 'test-title-includes-context', 0) ? vigun#TestTitleWithContext() : vigun#TestTitle()
    let cmd = s:RenderCmd(cmd, nearest_test_title)
  else
    if exists('s:last_command') && g:vigun_remember_last_command
      let cmd = s:last_command
    else
      throw "There is no command to run ".expand('%').". Please set one up in g:vigun_mappings"
    endif
  endif

  call s:SendToTmux(cmd)
  let s:last_command = cmd
endfunction

fun s:RenderCmd(cmd, nearest_test_title)
  let nearest_test_title = escape(a:nearest_test_title, '()?')
  let nearest_test_title = substitute(nearest_test_title, '"', '\\\\\\\\\\\\"', 'g')
  let nearest_test_title = substitute(nearest_test_title, '`', '\\\\\\\\\\\\`', 'g')

  let result = substitute(a:cmd, '#{file}', expand('%'), 'g')
  let result = substitute(result, '#{line}', line('.'), 'g')
  let result = substitute(result, '#{nearest_test}', '\\\"'.nearest_test_title.'\\\"', '')

  return result
endf

fun vigun#TestTitleWithContext()
  let treesitter_title = luaeval('require("vigun.treesitter").get_test_title_with_context()')
  return treesitter_title
endf

fun vigun#TestTitle(...)
  let line_number = a:0 ? a:1 : line('.')
  let treesitter_title = luaeval('require("vigun.treesitter").get_test_title(_A)', line_number)

  return treesitter_title
endf

" Treesitter migration: legacy keyword regex removed

function s:IsOnlySet()
  return luaeval('require("vigun.treesitter").has_only_tests()')
endfunction

fun s:SubstituteAll(pattern, ...)
  let l = 1
  for line in getline(1, '$')
    if match(line, a:pattern)
      let new_text = ''
      if a:0
        new_text = a:0
      endif

      call setline(l, substitute(line, a:pattern, new_text, 'g'))
    endif
    let l = l + 1
  endfor
endf

function s:MochaOnly()
  let current_test_line_number = luaeval('require("vigun.treesitter").find_nearest_test(_A)', line('.'))

  if !current_test_line_number
    return
  endif

  let line = getline(current_test_line_number)
  call s:SubstituteAll('\.only')

  if match(line, '\<\i\+\.only\>') == -1
    let newline = substitute(line, '\<\i\+\>', '&.only', '')
    call setline(current_test_line_number, newline)
  endif

  if current_test_line_number < line("w0")
    call cursor(current_test_line_number, 1)
    normal! f(
  endif
endfunction

function s:GetConfigForCurrentFile()
  for cmd in g:vigun_mappings
    if match(expand("%"), '\v' . cmd.pattern) != -1
      return cmd
    endif
  endfor
endfunction

function s:ShowSpecIndex()
  let qflist_entries = []

  let test_nodes = luaeval('require("vigun.treesitter").get_test_nodes()')
  for test_node in test_nodes
    let indent = repeat(nr2char(160), test_node.depth * 2)
    call add(qflist_entries, {'filename': expand('%'), 'lnum': test_node.line, 'text': indent . test_node.title})
  endfor

  call setqflist([], 'r', {'title': 'Spec index', 'items': qflist_entries})
  copen

  " hide filename and linenumber
  set conceallevel=2 concealcursor=nc
  syntax match llFileName /^[^|]*|[^|]*| / conceal display contains=NONE
endfunction

fun s:CurrentTestBefore(...)
  let starting_pos = getpos('.')
  call cursor(starting_pos[0], 1000)
  normal zE

  let folds = luaeval('require("vigun.treesitter").get_fold_ranges_for_line(_A)', line('.'))
  for fold in folds
    execute fold.start.",".fold["end"].' fold'
    call cursor(fold.start, 1)
    normal zC
  endfor

  call setpos('.', starting_pos)
endf

fun! s:ToggleTestWindowToPane()
  if g:vigun_tmux_pane_orientation == 'horizontal'
    let orientation = '-v'
  else
    let orientation = '-h'
  endif

  call system('tmux join-pane -d '.orientation.' -p 30 -s '.g:vigun_tmux_window_name)
  if v:shell_error && exists('s:tmux_pane_id')
    call system('tmux break-pane -d -n '.g:vigun_tmux_window_name.' -s '.s:tmux_pane_id)
  endif
endf

if !exists('g:vigun_tmux_pane_orientation')
  let g:vigun_tmux_pane_orientation = 'vertical'
endif

if !exists('g:vigun_tmux_window_name')
  let g:vigun_tmux_window_name = 'test'
endif

if !exists('g:vigun_mappings')
  let g:vigun_mappings = [
        \ {
        \   'pattern': '.(spec|test).js$',
        \   'all': 'node --test #{file}',
        \   'nearest': 'node --test --test-name-pattern=#{nearest_test} #{file}',
        \ },
        \ {
        \   'pattern': 'Spec.js$',
        \   'all': './node_modules/.bin/mocha #{file}',
        \   'nearest': './node_modules/.bin/mocha --fgrep #{nearest_test} #{file}',
        \   'debug-all': './node_modules/.bin/mocha --inspect-brk --no-timeouts #{file}',
        \   'debug-nearest': './node_modules/.bin/mocha --inspect-brk --no-timeouts --fgrep #{nearest_test} #{file}',
        \   'test-title-includes-context': 1
        \ },
        \ {
        \   'pattern': '_test.py$',
        \   'all': 'pytest -s #{file}',
        \   'nearest': 'pytest -k #{nearest_test} -s #{file}',
        \   'debug-all': 'pytest -vv -s #{file}',
        \   'debug-nearest': 'pytest -vv -k #{nearest_test} -s #{file}',
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
endif

com -nargs=1 VigunRun call s:RunTests(<args>)
com VigunShowSpecIndex call s:ShowSpecIndex()
com VigunToggleOnly call s:MochaOnly()
com VigunCurrentTestBefore call s:CurrentTestBefore()
com VigunToggleTestWindowToPane call s:ToggleTestWindowToPane()
