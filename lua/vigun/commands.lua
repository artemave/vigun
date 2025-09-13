local M = {}

local function get_opts()
  return require('vigun.config').get_options()
end

function M.mocha_only()
  local ts = require('vigun.treesitter')
  local lnum = ts.find_nearest_test(vim.fn.line('.'))
  if not lnum or lnum == 0 then return end

  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i = 1, #lines do
    lines[i] = lines[i]:gsub('%.only', '')
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  if not line then return end
  if line:find('%.only') then return end

  -- Append .only to the first identifier on the line
  local replaced, n = line:gsub('([%a_][%w_]*)', '%1.only', 1)
  if n and n > 0 then
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { replaced })
  end

  -- If test line is above window, move cursor to it and place at first (
  local w0 = vim.fn.line('w0')
  if lnum < w0 then
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
    vim.cmd('normal! f(')
  end
end

function M.show_spec_index()
  local bufnr = vim.api.nvim_get_current_buf()
  local tests = require('vigun.treesitter').get_test_nodes()
  local nbsp = vim.fn.nr2char(160)
  local items = {}
  local fname = vim.fn.expand('%')
  for _, t in ipairs(tests) do
    local indent = string.rep(nbsp, t.depth * 2)
    table.insert(items, { filename = fname, lnum = t.line, text = indent .. t.title })
  end
  vim.fn.setqflist({}, 'r', { title = 'Spec index', items = items })
  vim.cmd('copen')

  -- Visual tweaks similar to legacy Vimscript
  vim.opt.conceallevel = 2
  vim.opt.concealcursor = 'nc'
  vim.cmd([[syntax match llFileName /^[^|]*|[^|]*| / conceal display contains=NONE]])
end

function M.current_test_before()
  local pos = vim.api.nvim_win_get_cursor(0)
  vim.cmd('normal! zE')
  local line = vim.fn.line('.')
  local folds = require('vigun.treesitter').get_fold_ranges_for_line(line)
  for _, r in ipairs(folds) do
    vim.cmd(string.format('%d,%d fold', r.start, r["end"]))
    vim.api.nvim_win_set_cursor(0, { r.start, 0 })
    vim.cmd('normal! zC')
  end
  vim.api.nvim_win_set_cursor(0, pos)
end

function M.toggle_test_window_to_pane()
  local opts = get_opts()
  local orientation
  if opts.tmux_pane_orientation == 'horizontal' then
    orientation = '-v'
  else
    orientation = '-h'
  end
  local win = opts.tmux_window_name

  local pane_id = require('vigun.runner').get_tmux_pane_id()
  vim.fn.system('tmux join-pane -d ' .. orientation .. ' -l 30 -s ' .. win)

  -- error means there was no pane, and then can only mean that it's already inside nvim window,
  -- so we are at the "break pane back into window" part of the toggle
  if vim.v.shell_error ~= 0 then
    vim.fn.system('tmux break-pane -d -n ' .. win .. ' -s ' .. pane_id_to_break_out)
  else
    pane_id_to_break_out = pane_id
  end
end

return M
