local M = {}

function M.main()
  -- Try plenary first
  local has_plenary, _ = pcall(require, 'plenary.test_harness')
  if has_plenary then
    -- Use the user command to ensure proper reporting
    vim.cmd("PlenaryBustedDirectory lua/vigun/tests { sequential = true }")
    local code = vim.v.shell_error or 0
    vim.cmd('cquit ' .. code)
    return
  end

  -- Fallback: smoke tests without plenary
  local ok, err = pcall(function()
    require('vigun.tests.config_smoke').run()
  end)
  if not ok then
    print('Lua config smoke tests FAILED: ' .. tostring(err))
    vim.cmd('cquit 1')
  else
    vim.cmd('qall!')
  end
end

return M

