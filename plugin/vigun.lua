-- Lua entrypoint: define user commands and route to Lua implementations

local create = vim.api.nvim_create_user_command

create('VigunRun', function(opts)
  -- Pass raw string to CLI runner, preserving quotes as in tests
  local ok, err = pcall(function()
    require('vigun.runner').cli(opts.args)
  end)
  if not ok then
    -- Re-throw as a Vimscript error without Lua stack prefixes
    vim.cmd('throw ' .. vim.fn.string(err))
  end
end, { nargs = 1, complete = function() return { 'all', 'nearest', 'debug-all', 'debug-nearest' } end })

create('VigunShowSpecIndex', function()
  require('vigun.commands').show_spec_index()
end, {})

create('VigunToggleOnly', function()
  require('vigun.commands').mocha_only()
end, {})

create('VigunCurrentTestBefore', function()
  require('vigun.commands').current_test_before()
end, {})

create('VigunToggleTestWindowToPane', function()
  require('vigun.commands').toggle_test_window_to_pane()
end, {})
