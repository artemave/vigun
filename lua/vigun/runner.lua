local M = {}
M._last = nil

local function has_only()
  return require('vigun.treesitter').has_only_tests()
end

local function effective_mode(mode)
  if mode:find('nearest', 1, true) and has_only() then
    return (mode:gsub('nearest', 'all'))
  end
  return mode
end

function M.get_executor()
  local ex = require('vigun.config').get_options().executor
  if type(ex) == 'table' then return ex end
  return require('vigun.executors.' .. ex)
end

function M.run(mode)
  local emode = effective_mode(mode)
  local cmd = require('vigun.config').get_command(emode)
  local config = require('vigun.config').get_active()

  if not config then
    error('Vigun: no enabled config for ' .. vim.fn.expand('%'))
  end
  if not emode then
    error("Vigun: no command '" .. emode .. "' for current file")
  end

  local executor = M.get_executor()
  local opts = require('vigun.config').get_options()

  if not config.on_result or opts.dry_run then
    executor.run(cmd)
    M._last = cmd
    return
  end

  local file = vim.fn.expand('%')
  local started_at = os.time()

  executor.run(cmd, function(output)
    local ended_at = os.time()
    vim.schedule(function()
      config.on_result({
        command = cmd,
        mode = mode,
        file = file,
        output = output,
        started_at = started_at,
        ended_at = ended_at,
      })
    end)
  end)
  M._last = cmd
end

-- CLI entry used by :VigunRun <mode>
function M.cli(mode)
  local ok, val = pcall(function() return M.run(mode) end)
  if not ok then
    local opts = require('vigun.config').get_options()
    if opts.remember_last_command and M._last then
      M.get_executor().run(M._last)
    else
      error(val)
    end
  end
end

return M
