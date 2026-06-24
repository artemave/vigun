-- Executor for https://github.com/artemave/hop.
--
-- Wire protocol:
--   hop run --focus --role <role> <cmd>   dispatches, focuses the role's
--                                         window, and prints a run id on
--                                         stdout
--   hop tail <id>                         streams the run's combined output;
--                                         exits once the command completes
local M = {}

local function run_argv(cmd)
  local role = require('vigun.config').get_options().hop_role or 'test'
  return { 'hop', 'run', '--focus', '--role', role, cmd }
end

-- A failed `hop` call (e.g. the bridge can't resolve the session because the
-- focused window isn't the hop editor) only signals via exit code + stderr.
-- Surface it: a silent no-op leaves the user with no idea the run never
-- dispatched. vim.system callbacks run in a fast event context where the API
-- is mostly off-limits, so defer onto the main loop.
local function report_failure(argv, result)
  vim.schedule(function()
    local stderr = vim.trim(result.stderr or '')
    local detail = stderr ~= '' and stderr or ('exited with code ' .. tostring(result.code))
    vim.notify(table.concat(argv, ' ') .. ': ' .. detail, vim.log.levels.ERROR)
  end)
end

function M.run(cmd, on_done)
  local opts = require('vigun.config').get_options()
  local argv = run_argv(cmd)

  if opts.dry_run then
    vim.api.nvim_echo({{ table.concat(argv, ' '), '' }}, true, {})
    return
  end

  vim.system(argv, { text = true }, function(dispatch)
    if dispatch.code ~= 0 then
      report_failure(argv, dispatch)
      return
    end
    if not on_done then
      return
    end

    local id = (dispatch.stdout or ''):gsub('%s+$', '')
    if id == '' then
      return
    end

    local tail_argv = { 'hop', 'tail', id }
    vim.system(tail_argv, { text = true }, function(tail)
      if tail.code ~= 0 then
        report_failure(tail_argv, tail)
        return
      end
      on_done(tail.stdout or '')
    end)
  end)
end

return M
