-- Executor for https://github.com/artemave/hop.
--
-- Wire protocol:
--   hop run --focus --role <role> <cmd>   dispatches, focuses the role's
--                                         window, and prints a run id on
--                                         stdout
--   hop wait <id>                          blocks until the run finishes, then
--                                         writes its output to stdout and
--                                         exits with the command's own status
--                                         (124 if hop gives up waiting)
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

    local wait_argv = { 'hop', 'wait', id }
    vim.system(wait_argv, { text = true }, function(wait)
      -- `hop wait` exits with the test command's own status, so a non-zero
      -- code is the normal "tests failed" outcome — hand the output to
      -- on_done regardless. Only 124 (hop gave up waiting) is a
      -- dispatch-level failure worth surfacing.
      if wait.code == 124 then
        report_failure(wait_argv, wait)
        return
      end
      on_done(wait.stdout or '')
    end)
  end)
end

return M
