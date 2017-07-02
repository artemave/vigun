if exists("g:vigun_loaded")
  finish
endif
let g:vigun_loaded = 1

fun s:Debug(message)
  if exists("g:vigun_debug")
    echom message
  endif
endf

function s:SendToTmux(command)
  if exists("g:vigun_dry_run")
    echom a:command
    return
  endif

  call system('tmux select-window -t test || tmux new-window -n test')

  let tmux_set_buffer = 'tmux set-buffer -b vigun "' . a:command . "\n\""
  call system(tmux_set_buffer)
  if v:shell_error
    echom 'Failed to set-buffer: '.tmux_set_buffer
  else
    call system('tmux paste-buffer -b vigun -d -t test')
  endif
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

function s:GetCurrentTestMethod(config)
  if get(a:config, 'current')
    return a:config.current
  endif

  if &filetype == 'javascript'
    return 'grep'
  else
    return 'line_number'
  endif
endfunction

function s:RunTests(mode, ...)
  let config = s:GetConfigForCurrentFile()

  if !exists("config")
    return
  endif

  wa

  let is_debug = exists("a:1") && a:1 == 'debug'

  if is_debug
    let cmd = get(config, 'debug', config.normal)
  else
    let cmd = config.normal
  endif

  if a:mode == 'current'
    let current_test_method = s:GetCurrentTestMethod(config)

    if current_test_method == 'line_number'
      let formatted_cmd = cmd .' '. expand('%').':'.line('.')
    else
      if s:IsOnlySet()
        let formatted_cmd = cmd .' '. expand('%')
      else
        let nearest_test_line_number = search(s:KeywordsRegexp().'(', 'bn')
        let nearest_test_title = escape(matchstr(getline(nearest_test_line_number), "['".'"`]\zs.*\ze'."['".'"`][^"`'."']*$"), '()?')
        let nearest_test_title = substitute(nearest_test_title, '"', '\\\\\\"', 'g')

        let formatted_cmd = cmd . ' --fgrep \"'.nearest_test_title.'\" ' . expand('%')
      endif
    endif
  else
    let formatted_cmd = cmd .' '. expand('%')
  endif

  call s:SendToTmux(formatted_cmd)

  if is_debug && !exists('g:vigun_dry_run')
    call s:CopyMochaDebugUrlToClipboard()
  endif
endfunction

function s:KeywordsRegexp(...)
  if a:0 && a:1 == 'context'
    let keywords = ['context', 'describe']
  else
    let keywords = ['[Ii]ts\?', '[Cc]ontext', '[Dd]escribe', 'xit', '[Ff]eature', '[Ss]cenario'] + g:vigun_extra_keywords
  endif
  let search = '^[ \t]*\<\('. join(keywords, '\|') .'\)\>'
  return search
endfunction

function s:IsOnlySet()
  return search(s:KeywordsRegexp().'.only(', 'bnw')
endfunction

function s:MochaOnly()
  let line_number = search(s:KeywordsRegexp().'\(.only\)\?(', 'bnw')

  if !line_number
    return
  endif

  let line = getline(line_number)

  if match(line, '\<\i\+\.only\>') >= 0
    let newline = substitute(line, '\<\(\i\+\)\.only\>', '\1', '')
    call setline(line_number, newline)
  else
    let newline = substitute(line, '\<\i\+\>', '&.only', '')
    call setline(line_number, newline)
  endif

  if line_number < line("w0")
    call cursor(line_number, 1)
    normal! f(
  endif
endfunction

function s:GetConfigForCurrentFile()
  for cmd in g:vigun_commands
    if match(expand("%"), '\v' . cmd.pattern) != -1
      return cmd
    endif
  endfor
  throw "There is no command to run ".expand('%').". Please set one up in g:vigun_commands"
endfunction

function s:ShowSpecIndex()
  call setqflist([])

  for line_number in range(1,line('$'))
    if getline(line_number) =~ s:KeywordsRegexp()
      let expr = printf('%s:%s:%s', expand("%"), line_number, substitute(getline(line_number), '[ \t]', nr2char(160), 'g'))
      caddexpr expr
    endif
  endfor

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
      call cursor(context_start - 1, 1)
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

if !exists('g:vigun_extra_keywords')
  let g:vigun_extra_keywords = []
endif

if !exists('g:vigun_commands')
  let g:vigun_commands = [
        \ {
        \   'pattern': 'Spec.js$',
        \   'normal': 'mocha',
        \   'debug': 'mocha --inspect-brk --no-timeouts',
        \ },
        \ {
        \   'pattern': '_spec.rb$',
        \   'normal': 'rspec',
        \ },
        \ {
        \   'pattern': '.feature$',
        \   'normal': 'cucumber',
        \ },
        \]
endif

com RunTestFile call s:RunTests('all')|redraw!
com RunNearestTest call s:RunTests('current')|redraw!
com RunNearestTestDebug call s:RunTests('current', 'debug')|redraw!

com ShowSpecIndex call s:ShowSpecIndex()
com MochaOnly call s:MochaOnly()|redraw!
com CurrentTestBefore call s:CurrentTestBefore()
