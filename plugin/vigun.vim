if exists("g:vigun_loaded")
  finish
endif
let g:vigun_loaded = 1

fun s:Debug(message)
  if exists("g:vigun_debug")
    echom a:message
  endif
endf

function s:SendToTmux(command)
  if exists("g:vigun_dry_run")
    echom a:command
    return
  endif

  call system('tmux select-window -t '.g:vigun_tmux_window_name.' || tmux new-window -n '.g:vigun_tmux_window_name)

  " only send C-c if something (e.g. entr) is running in the test window
  let number_of_procs = system("ps -o comm= -t \"$(tmux list-panes -t ".g:vigun_tmux_window_name." -F '#{pane_tty}')\" | wc -l")
  if number_of_procs > 1
    call system('tmux send-keys C-c')
  endif
  call system('tmux send-keys "'. a:command .'" Enter')
endfunction

" This will gracefully do nothing for any command other than `mocha --inspect-brk`
function s:CopyMochaDebugUrlToClipboard()
  let debug_url = ''
  let retry_count = 0

  while retry_count < 50
    call system('tmux capture-pane -J -b mocha-debug')
    call system('tmux save-buffer -b mocha-debug /tmp/vim-mocha-debug')

    let debug_url=system("grep chrome-devtools /tmp/vim-mocha-debug | tail -n 1 | sed -e 's/ *//'")
    let last_buffer_line=system("cat /tmp/vim-mocha-debug | grep -v -e '^$' | tail -n 1")

    if debug_url != "" && last_buffer_line =~ debug_url
      let @*=debug_url " copy to osx clipboard
      let @+=debug_url " copy to linux clipboard
      return
    endif

    sleep 20m
    let retry_count += 1
  endwhile
endfunction

function s:RunTests(mode)
  let config = s:GetConfigForCurrentFile()

  if !exists("config")
    return
  endif

  wa

  let cmd = get(config, a:mode, config.all)

  if (match(a:mode, 'nearest') > -1) && s:IsOnlySet()
    let cmd = get(config, substitute(a:mode, 'nearest', 'all', ''), cmd)
  endif

  let cmd = s:RenderCmd(cmd)

  call s:SendToTmux(cmd)

  if (match(a:mode, 'debug') > -1) && !exists('g:vigun_dry_run')
    call s:CopyMochaDebugUrlToClipboard()
  endif
endfunction

fun s:RenderCmd(cmd)
  let nearest_test_line_number = search(s:KeywordsRegexp().'(', 'bn')
  let nearest_test_title = escape(s:TestTitle(nearest_test_line_number), '()?')
  let nearest_test_title = substitute(nearest_test_title, '"', '\\\\\\\\\\\\"', 'g')

  let result = substitute(a:cmd, '#{file}', expand('%'), 'g')
  let result = substitute(result, '#{line}', line('.'), 'g')
  let result = substitute(result, '#{nearest_test}', '\\\"'.nearest_test_title.'\\\"', '')

  return result
endf

fun s:TestTitle(line_number)
  return matchstr(getline(a:line_number), "['".'"`]\zs.*\ze'."['".'"`][^"`'."']*$")
endf

function s:KeywordsRegexp(...)
  if a:0 && a:1 == 'context'
    let keywords = ['context', 'describe']
  else
    let keywords = g:vigun_test_keywords
  endif
  let search = '^[ \t]*\<\('. join(keywords, '\|') .'\)\>'
  return search
endfunction

function s:IsOnlySet()
  return search(s:KeywordsRegexp().'\.only(', 'nw')
endfunction

fun s:SubstituteAll(pattern, ...)
  let l = 1
  for line in getline(1, '$')
    if match(line, a:pattern)
      let replacement = ''
      if a:0
        replacement = a:0
      endif

      call setline(l, substitute(line, a:pattern, replacement, 'g'))
    endif
    let l = l + 1
  endfor
endf

function s:MochaOnly()
  let current_test_line_number = search(s:KeywordsRegexp().'\(\.only\)\?(', 'bnw')

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
  throw "There is no command to run ".expand('%').". Please set one up in g:vigun_mappings"
endfunction

function s:ShowSpecIndex()
  let qflist_entries = []

  for line_number in range(1,line('$'))
    let line = getline(line_number)
    if line =~ s:KeywordsRegexp()
      let indent = substitute(line, '^\([ \t]*\).*', '\=submatch(1)', '')
      let indent = substitute(indent, '[ \t]', nr2char(160), 'g')
      call add(qflist_entries, {'filename': expand('%'), 'lnum': line_number, 'text': indent . s:TestTitle(line_number)})
    endif
  endfor

  call setqflist([], 'r', {'title': 'Spec index', 'items': qflist_entries})
  copen

  " hide filename and linenumber
  set conceallevel=2 concealcursor=nc
  syntax match llFileName /^[^|]*|[^|]*| / transparent conceal
endfunction

fun s:CurrentTestBefore(...)
  if a:0
    let nearest_test_start = a:1
    let nearest_test_end = a:2
    call cursor(nearest_test_start, 1)
  else
    let starting_pos = getpos('.')
    call cursor(starting_pos[0], 1000)
    normal zE

    let nearest_test_start = search(s:KeywordsRegexp().'(', 'bWe')
    let nearest_test_end = searchpair('(', '', ')')
  endif
  call s:Debug("nearest_test_start: ".nearest_test_start)
  call s:Debug("nearest_test_end: ".nearest_test_end)

  if nearest_test_start && nearest_test_end
    let context_start = search(s:KeywordsRegexp('context').'(', 'bWe')
    call s:Debug("context_start: ".context_start)
    let context_end = searchpair('(', '', ')', 'n')
    call s:Debug("context_end: ".context_end)

    while context_end && context_end < nearest_test_start
      call cursor(context_start, 1)
      let context_start = search(s:KeywordsRegexp('context').'(', 'bWe')
      call s:Debug("context_start: ".context_start)
      let context_end = searchpair('(', '', ')', 'n')
      call s:Debug("context_end: ".context_end)
    endwhile

    let next_test_start = search(s:KeywordsRegexp().'(', 'e')
    while next_test_start && next_test_start < context_end
      call s:Debug("next_test_start: ".next_test_start)
      if next_test_start < nearest_test_start || next_test_start > nearest_test_end
        let next_test_end = searchpair('(', '', ')')
        call s:Debug("next_test_end: ".next_test_end)
        execute next_test_start.",".next_test_end.' fold'
        normal zC
      endif
      let next_test_start = search(s:KeywordsRegexp().'(', 'eW')
    endwhile

    call s:CurrentTestBefore(context_start, context_end)
  endif

  if !a:0
    call setpos('.', starting_pos)
  endif
endf

if !exists('g:vigun_tmux_window_name')
  let g:vigun_tmux_window_name = 'test'
endif

if !exists('g:vigun_test_keywords')
  let g:vigun_test_keywords = ['[Ii]ts\?', '[Cc]ontext', '[Dd]escribe', 'xit', '[Ff]eature', '[Ss]cenario', 'test']
endif

if !exists('g:vigun_mappings')
  let g:vigun_mappings = [
        \ {
        \   'pattern': 'Spec.js$',
        \   'all': './node_modules/.bin/mocha #{file}',
        \   'nearest': './node_modules/.bin/mocha --fgrep #{nearest_test} #{file}',
        \   'debug-all': './node_modules/.bin/mocha --inspect-brk --no-timeouts #{file}',
        \   'debug-nearest': './node_modules/.bin/mocha --inspect-brk --no-timeouts --fgrep #{nearest_test} #{file}',
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
com VigunMochaOnly call s:MochaOnly()
com VigunCurrentTestBefore call s:CurrentTestBefore()
