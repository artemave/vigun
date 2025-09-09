local M = {}

local Config = require('vigun.config')

local function with_buf(name, fn)
  vim.cmd('enew')
  vim.cmd('file ' .. name)
  local ok, err = pcall(fn)
  vim.cmd('bd!')
  if not ok then error(err) end
end

local function run_smoke()
  vim.g.vigun_config = nil
  with_buf('testSpec.js', function()
    local cmd = Config.get_command('all')
    assert(cmd == './node_modules/.bin/mocha testSpec.js', 'default mocha all')
  end)

  vim.g.vigun_config = {
    mocha = {
      commands = {
        all = function(_)
          return 'custom ' .. vim.fn.expand('%')
        end,
      },
    },
  }
  with_buf('testSpec.js', function()
    local cmd = Config.get_command('all')
    assert(cmd == 'custom testSpec.js', 'override all')
    local dbg = Config.get_command('debug-all')
    assert(dbg == './node_modules/.bin/mocha --inspect-brk --no-timeouts testSpec.js', 'keep default debug-all')
  end)
end

function M.run()
  run_smoke()
  print('Lua config smoke tests: OK')
end

return M

