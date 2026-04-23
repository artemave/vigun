-- Executor for https://github.com/artemave/hop.
--
-- Wire protocol:
--   hop run --role <role> <cmd>   dispatches and prints a run id on stdout
--   hop tail <id>                 streams the run's combined output; exits
--                                 once the command completes
local M = {}

local function run_argv(cmd)
  local role = require('vigun.config').get_options().hop_role or 'test'
  return { 'hop', 'run', '--role', role, cmd }
end

function M.run(cmd, on_done)
  local opts = require('vigun.config').get_options()
  local argv = run_argv(cmd)

  if opts.dry_run then
    vim.api.nvim_echo({{ table.concat(argv, ' '), '' }}, true, {})
    return
  end

  if not on_done then
    vim.system(argv, { text = true }, function() end)
    return
  end

  vim.system(argv, { text = true }, function(dispatch)
    local id = (dispatch.stdout or ''):gsub('%s+$', '')
    if id == '' then
      return
    end
    vim.system({ 'hop', 'tail', id }, { text = true }, function(tail)
      on_done(tail.stdout or '')
    end)
  end)
end

return M
