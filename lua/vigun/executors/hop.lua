local M = {}

local function hop_argv(cmd)
  local role = require('vigun.config').get_options().hop_role or 'test'
  return { 'hop', 'run', '--role', role, cmd }
end

function M.run(cmd, on_done)
  local opts = require('vigun.config').get_options()
  local argv = hop_argv(cmd)

  if opts.dry_run then
    vim.api.nvim_echo({{ table.concat(argv, ' '), '' }}, true, {})
    return
  end

  if not on_done then
    vim.system(argv, { text = true }, function() end)
    return
  end

  vim.system(argv, { text = true }, function(res)
    on_done((res.stdout or '') .. (res.stderr or ''))
  end)
end

return M
