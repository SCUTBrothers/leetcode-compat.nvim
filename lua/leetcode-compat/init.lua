local M = {}

local config = require("leetcode-compat.config")
local api = require("leetcode-compat.api")
local file = require("leetcode-compat.file")

function M.setup(opts)
  config.setup(opts)
  M._setup_commands()
end

function M._setup_commands()
  local cmd = vim.api.nvim_create_user_command

  cmd("LCList", function() require("leetcode-compat.ui.picker").open() end, { desc = "Browse LeetCode problems" })
  cmd("LCOpen", function(o) require("leetcode-compat.ui.picker").open_by_id(tonumber(o.args)) end, { nargs = 1, desc = "Open problem by ID" })
  cmd("LCRun", function() require("leetcode-compat.runner").run() end, { desc = "Run test cases" })
  cmd("LCSubmit", function() require("leetcode-compat.runner").submit() end, { desc = "Submit solution" })
  cmd("LCDesc", function() require("leetcode-compat.ui.description").toggle() end, { desc = "Toggle problem description" })
  cmd("LCAuth", function() require("leetcode-compat.auth").prompt_cookie() end, { desc = "Set LeetCode cookie" })
  cmd("LCInfo", function() require("leetcode-compat.ui.info").show() end, { desc = "Show problem info" })
end

return M
