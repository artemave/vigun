if exists("g:vigun_loaded")
  finish
endif
let g:vigun_loaded = 1

fun! s:EnsureTestWindow()
  if exists('s:tmux_pane_id')
    call system('tmux list-panes -t '.s:tmux_pane_id)
    if v:shell_error == 0
      return
    endif
  endif

  let win_name = luaeval("require('vigun.config').get_options().tmux_window_name")
  call system("tmux list-windows -F '#{window_name}' | grep -w ".win_name)
  if v:shell_error
    call system('tmux new-window -d -n '.win_name)
  endif
  let s:tmux_pane_id = system("tmux list-panes -F '#{pane_id}' -t ".win_name)
endf

function s:SendToTmux(command)
  if luaeval("require('vigun.config').get_options().dry_run")
    let msg = a:command
    " For display only: ensure inner quotes/backticks inside the fgrep payload are escaped
    let pat = '\V--fgrep \"'
    let fgpos = match(msg, pat)
    if fgpos >= 0
      let start_str = matchstr(msg, pat)
      let payload_start = fgpos + strlen(start_str)
      let rest = strpart(msg, payload_start)
      let endpat = '\V\"'
      let payload_end_rel = match(rest, endpat)
      if payload_end_rel >= 0
        let prefix = strpart(msg, 0, payload_start)
        let payload = strpart(rest, 0, payload_end_rel)
        let suffix = strpart(rest, payload_end_rel)
        " Normalize and then escape inner quotes/backticks in payload
        let payload = substitute(payload, '\\\"', '"', 'g')
        let payload = substitute(payload, '"', '\\\"', 'g')
        let payload = substitute(payload, '\\\`', '`', 'g')
        let payload = substitute(payload, '`', '\\\`', 'g')
        let msg = prefix . payload . suffix
      endif
    endif
    echom msg
    return
  endif

  call s:EnsureTestWindow()

  let win_name = luaeval("require('vigun.config').get_options().tmux_window_name")
  call system('tmux select-window -t '.win_name)
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
  let l:mode = a:mode

  let l:effective = l:mode
  if (match(l:mode, 'nearest') > -1) && s:IsOnlySet()
    let l:effective = substitute(l:mode, 'nearest', 'all', '')
  endif

  let cmd = luaeval("require('vigun.config').get_command(_A)", l:effective)
  if type(cmd) != v:t_string || cmd ==# ''
    if exists('s:last_command') && luaeval("require('vigun.config').get_options().remember_last_command")
      let cmd = s:last_command
    else
      if luaeval("require('vigun.config').get_active() == nil")
        throw 'Vigun: no enabled config for ' . expand('%')
      else
        throw "Vigun: no command '" . l:effective . "' for current file"
      endif
    endif
  endif

  wa
  call s:SendToTmux(cmd)
  let s:last_command = cmd
endfunction

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
  if luaeval("require('vigun.config').get_options().tmux_pane_orientation") ==# 'horizontal'
    let orientation = '-v'
  else
    let orientation = '-h'
  endif

  let win_name = luaeval("require('vigun.config').get_options().tmux_window_name")
  call system('tmux join-pane -d '.orientation.' -p 30 -s '.win_name)
  if v:shell_error && exists('s:tmux_pane_id')
    call system('tmux break-pane -d -n '.win_name.' -s '.s:tmux_pane_id)
  endif
endf

" Default options are provided via Lua config; see README

com -nargs=1 VigunRun call s:RunTests(<q-args>)
com VigunShowSpecIndex call s:ShowSpecIndex()
com VigunToggleOnly call s:MochaOnly()
com VigunCurrentTestBefore call s:CurrentTestBefore()
com VigunToggleTestWindowToPane call s:ToggleTestWindowToPane()
