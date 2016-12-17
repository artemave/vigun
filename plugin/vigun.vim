if exists("g:vigun_loaded")
  break
endif
let g:vigun_loaded = 1

function! s:SetTestCase()
  let in_test_file = match(expand("%"), 'Spec.js$') != -1

  if in_test_file
    let t:grb_test_file=@%
    :wa

    let nearest_test_line_number = search('\<\(it\|context\|describe\)(', 'bn')
    let t:nearest_test_title = matchstr(getline(nearest_test_line_number), "['" . '"]\zs[^"' . "']" . '*\ze')
  end
endfunction

function! s:SendToTmux(command)
  call system('tmux select-window -t test || tmux new-window -n test')
  call system('tmux set-buffer "' . a:command . "\n\"")
  call system('tmux paste-buffer -d -t test')
endfunction

function! RunNearestMochaTest()
  call s:SetTestCase()

  if !exists("t:grb_test_file")
    return
  end

  let command = s:MochaCommand('normal') . " --fgrep '".t:nearest_test_title."' " . t:grb_test_file

  call s:SendToTmux(command)
endfunction

function! RunNearestMochaTestDebug()
  call s:SetTestCase()

  if !exists("t:grb_test_file")
    return
  end

  let command = s:MochaCommand('debug') . " --fgrep '".t:nearest_test_title."' " . t:grb_test_file

  call s:SendToTmux(command)

  call system('tmux capture-pane -J -b mocha-debug')
  call system('tmux save-buffer -b mocha-debug /tmp/vim-mocha-debug')

  let debug_url=system("grep chrome-devtools /tmp/vim-mocha-debug | tail -n 1 | sed -e 's/ *//'")
  let @*=debug_url " copy to osx clipboard
  let @+=debug_url " copy to linux clipboard
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

function! MochaOnly()
  let line_number = search('\<\(it\|context\|describe\|forExample\|scenario\|feature\)\(.only\)\=(', 'bn')
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

au FileType javascript nmap <buffer> <nowait> <Leader>o :call MochaOnly()<cr>

au FileType {ruby,javascript,cucumber} nmap <buffer> <nowait> <leader>t :call RunTestFile()<cr>
au FileType {ruby,cucumber} nmap <buffer> <nowait> <leader>T :call RunNearestTest()<cr>
au FileType javascript nmap <buffer> <nowait> <leader>T :call RunNearestMochaTest()<cr>
au FileType javascript nmap <buffer> <nowait> <leader>D :call RunNearestMochaTestDebug()<cr>

" for `bundle exec` in front of rspec/cucumber
if !exists('g:vigun_ruby_test_command_prefix')
  let g:vigun_ruby_test_command_prefix = ''
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