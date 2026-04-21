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
  cmd("LCPractice", function(o) require("leetcode-compat.ui.picker").practice_by_id(tonumber(o.args)) end, { nargs = 1, desc = "Practice problem by ID (reset to default template)" })
  cmd("LCDaily", function() require("leetcode-compat.ui.picker").open_daily() end, { desc = "Open daily challenge" })
  cmd("LCRandom", function(o)
    local diff = o.args ~= "" and o.args or nil
    require("leetcode-compat.ui.picker").open_random(diff)
  end, { nargs = "?", desc = "Open random problem (optional: Easy/Medium/Hard)" })
  cmd("LCReview", function() require("leetcode-compat.review").show_review_list() end, { desc = "Show due review problems" })
  cmd("LCReviewRate", function(o)
    require("leetcode-compat.review").rate_current(tonumber(o.args))
  end, { nargs = 1, desc = "Rate current problem (1=Again 2=Hard 3=Good 4=Easy)" })
  cmd("LCReviewStats", function() require("leetcode-compat.review").show_stats() end, { desc = "Show review statistics" })
  cmd("LCReviewInit", function()
    local n = require("leetcode-compat.review").init_from_workspace()
    vim.notify(string.format("LeetCode: 已同步，新增 %d 张卡片", n), vim.log.levels.INFO)
  end, { desc = "Init/sync review cards from workspace" })
end

return M
