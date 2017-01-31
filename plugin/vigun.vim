if exists("g:vigun_loaded")
  finish
endif
let g:vigun_loaded = 1

function! s:SetTestCase()
  let in_test_file = match(expand("%"), 'Spec.js$') != -1

  if in_test_file
    let t:grb_test_file=@%
    :wa

    let keywords = join(s:Keywords(), '\|')
    let nearest_test_line_number = search('\<\('.keywords.'\)(', 'bn')
    let t:nearest_test_title = escape(matchstr(getline(nearest_test_line_number), "['" . '"`]\zs[^"`' . "']" . '*\ze'), "'()?")
  end
endfunction

function! s:SendToTmux(command)
  call system('tmux select-window -t test || tmux new-window -n test')
  call system('tmux set-buffer "' . a:command . "\n\"")
  call system('tmux paste-buffer -d -t test')
endfunction

function! RunNearestMochaTest(mode)
  call s:SetTestCase()

  if !exists("t:grb_test_file")
    return
  end

  if s:IsOnlySet()
    let command = s:MochaCommand(a:mode) . " " . t:grb_test_file
  else
    let command = s:MochaCommand(a:mode) . " --fgrep '".t:nearest_test_title."' " . t:grb_test_file
  endif

  call s:SendToTmux(command)

  if a:mode == 'debug'
    call s:CopyMochaDebugUrlToClipboard()
  endif
endfunction

" This will gracefully do nothing for any command other than `mocha --inspect
" --debug-brk`
function! s:CopyMochaDebugUrlToClipboard()
  let debug_url = ''
  let retry_count = 0

  while debug_url == ''
    if retry_count > 10
      return
    endif

    call system('tmux capture-pane -J -b mocha-debug')
    call system('tmux save-buffer -b mocha-debug /tmp/vim-mocha-debug')

    let debug_url=system("grep chrome-devtools /tmp/vim-mocha-debug | tail -n 1 | sed -e 's/ *//'")

    if debug_url == ''
      sleep 20m
      let retry_count += 1
    endif
  endwhile

  if debug_url != ''
    let @*=debug_url " copy to osx clipboard
    let @+=debug_url " copy to linux clipboard
  endif
endfunction

function! RunTestFile(...)
  if a:0
    let command_suffix = a:1
  else
    let command_suffix = ""
  endif

  " Run the tests for the previously-marked file.
  let in_test_file = match(expand("%"), '\(.feature\|_spec.rb\|Spec.js\)$') != -1
  if in_test_file
    let t:grb_test_file=@%
  elseif !exists("t:grb_test_file")
    return
  end
  call s:RunTests(t:grb_test_file . command_suffix)
endfunction

function! RunNearestTest()
  let spec_line_number = line('.')
  call RunTestFile(":" . spec_line_number)
endfunction

function! s:RunTests(filename)
  :wa
  if match(a:filename, '\.feature') != -1
    if filereadable(expand("./features/support/env.rb"))
      let l:command = g:vigun_ruby_test_command_prefix . " cucumber " . a:filename
    else
      let l:command = "cucumberjs " . a:filename
    endif
  else
    if &filetype == 'javascript'
      let l:command = s:MochaCommand('normal') . ' ' . a:filename
    else
      let l:command = g:vigun_ruby_test_command_prefix . " rspec -c " . a:filename
    endif
  end
  call s:SendToTmux(command)
endfunction

function! s:Keywords()
  return ['it', 'context', 'describe'] + g:vigun_extra_keywords
endfunction

function! s:IsOnlySet()
  let keywords = join(s:Keywords(), '\|')
  return search('\<\('.keywords.'\).only(', 'bn')
endfunction

function! MochaOnly()
  let keywords = join(s:Keywords(), '\|')
  let line_number = search('\<\('.keywords.'\)\(.only\)\?(', 'bn')

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

function! s:MochaCommand(mode)
  for cmd in g:vigun_mocha_commands
    if match(expand("%"), '\v' . cmd.pattern) != -1
      return cmd[a:mode]
    endif
  endfor
endfunction

au FileType javascript nmap <buffer> <silent> <nowait> <Leader>o :call MochaOnly()\|redraw!<cr>

au FileType {ruby,javascript,cucumber} nmap <buffer> <silent> <nowait> <leader>t :call RunTestFile()\|redraw!<cr>
au FileType {ruby,cucumber} nmap <buffer> <silent> <nowait> <leader>T :call RunNearestTest()\|redraw!<cr>
au FileType javascript nmap <buffer> <silent> <nowait> <leader>T :call RunNearestMochaTest('normal')\|redraw!<cr>
au FileType javascript nmap <buffer> <silent> <nowait> <leader>D :call RunNearestMochaTest('debug')\|redraw!<cr>

" for `bundle exec` in front of rspec/cucumber
if !exists('g:vigun_ruby_test_command_prefix')
  let g:vigun_ruby_test_command_prefix = ''
endif

if !exists('g:vigun_extra_keywords')
  let g:vigun_extra_keywords = []
endif

if !exists('g:vigun_mocha_commands')
  let g:vigun_mocha_commands = [
        \ {
        \   'pattern': 'Spec.js$',
        \   'normal': 'mocha',
        \   'debug': 'mocha --inspect --debug-brk --no-timeouts',
        \ },
        \]
endif
