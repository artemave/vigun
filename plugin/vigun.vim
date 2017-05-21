if exists("g:vigun_loaded")
  finish
endif
let g:vigun_loaded = 1

function! s:SetTestCase()
  let in_test_file = match(expand("%"), 'Spec.js$') != -1

  if in_test_file
    let t:grb_test_file=@%
    :wa

    let nearest_test_line_number = search(s:KeywordsRegexp().'(', 'bn')
    let t:nearest_test_title = escape(matchstr(getline(nearest_test_line_number), "['" . '"`]\zs[^"`' . "']" . '*\ze'), "'()?")
  end
endfunction

function! s:SendToTmux(command)
  call system('tmux select-window -t test || tmux new-window -n test')
  call system('tmux set-buffer "' . a:command . "\n\"")
  call system('tmux paste-buffer -d -t test')
endfunction

function! s:RunNearestMochaTest(mode)
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

function! s:RunTestFile(...)
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

function! s:RunNearestTest()
  let spec_line_number = line('.')
  call s:RunTestFile(":" . spec_line_number)
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

function! s:KeywordsRegexp()
  let keywords = ['[Ii]ts\?', '[Cc]ontext', '[Dd]escribe', 'xit', '[Ff]eature', '[Ss]cenario'] + g:vigun_extra_keywords
  return '^[ \t]*\<\('. join(keywords, '\|') .'\)'
endfunction

function! s:IsOnlySet()
  return search(s:KeywordsRegexp().'.only(', 'bnw')
endfunction

function! s:MochaOnly()
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

function! s:MochaCommand(mode)
  for cmd in g:vigun_mocha_commands
    if match(expand("%"), '\v' . cmd.pattern) != -1
      return cmd[a:mode]
    endif
  endfor
endfunction

function! s:ShowSpecIndex()
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

com ShowSpecIndex call s:ShowSpecIndex()
com MochaOnly call s:MochaOnly()|redraw!
com RunTestFile call s:RunTestFile()|redraw!
com RunNearestTest call s:RunNearestTest()|redraw!
com -nargs=1 RunNearestMochaTest call s:RunNearestMochaTest(<args>)|redraw!
