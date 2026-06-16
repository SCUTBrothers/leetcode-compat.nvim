local M = {}

local config = require("leetcode-compat.config")
local language = require("leetcode-compat.language")

local function split_args(args)
  if not args or args == "" then return {} end
  return vim.split(args, "%s+", { trimempty = true })
end

local function parse_random_args(args)
  local parsed = { difficulty = nil, domain = nil, lang = nil }
  for _, arg in ipairs(args) do
    if arg == "Easy" or arg == "Medium" or arg == "Hard" then
      parsed.difficulty = arg
    elseif arg == "algorithm" or arg == "database" or arg == "all" then
      parsed.domain = arg
    elseif language.is_supported(arg) then
      parsed.lang = arg
    end
  end
  return parsed
end

local function complete_languages()
  return language.all()
end

local function complete_domains()
  return { "algorithm", "database", "all" }
end

local function complete_plans()
  return require("leetcode-compat.ui.study_plan").complete_plans()
end

function M.setup(opts)
  config.setup(opts)
  M._setup_commands()
end

function M._setup_commands()
  local cmd = vim.api.nvim_create_user_command

  cmd("LCList", function(o)
    local args = split_args(o.args)
    require("leetcode-compat.ui.picker").open(args[1], args[2])
  end, { nargs = "*", complete = complete_domains, desc = "Browse LeetCode problems" })
  cmd("LCOpen", function(o)
    local args = split_args(o.args)
    require("leetcode-compat.ui.picker").open_by_id(args[1], args[2])
  end, { nargs = "+", complete = complete_languages, desc = "Open problem by ID or slug" })
  cmd("LCRun", function() require("leetcode-compat.runner").run() end, { desc = "Run test cases" })
  cmd("LCSubmit", function() require("leetcode-compat.runner").submit() end, { desc = "Submit solution" })
  cmd("LCDesc", function() require("leetcode-compat.ui.description").toggle() end, { desc = "Toggle problem description" })
  cmd("LCAuth", function() require("leetcode-compat.auth").prompt_cookie() end, { desc = "Set LeetCode cookie" })
  cmd("LCInfo", function() require("leetcode-compat.ui.info").show() end, { desc = "Show problem info" })
  cmd("LCPractice", function(o)
    local args = split_args(o.args)
    require("leetcode-compat.ui.picker").practice_by_id(args[1], args[2])
  end, { nargs = "+", complete = complete_languages, desc = "Practice problem by ID or slug (reset to default template)" })
  cmd("LCDaily", function(o)
    local args = split_args(o.args)
    require("leetcode-compat.ui.picker").open_daily(args[1])
  end, { nargs = "?", complete = complete_languages, desc = "Open daily challenge" })
  cmd("LCRandom", function(o)
    local parsed = parse_random_args(split_args(o.args))
    require("leetcode-compat.ui.picker").open_random(parsed.difficulty, parsed.domain, parsed.lang)
  end, { nargs = "*", desc = "Open random problem (optional: Easy/Medium/Hard algorithm/database lang)" })
  cmd("LCLang", function(o)
    local args = split_args(o.args)
    require("leetcode-compat.ui.picker").set_or_open_language(args[1])
  end, { nargs = "?", complete = complete_languages, desc = "Switch current problem language or set default language" })
  cmd("LCPlan", function(o)
    local args = split_args(o.args)
    require("leetcode-compat.ui.study_plan").open(args[1], args[2])
  end, { nargs = "*", complete = complete_plans, desc = "Browse a LeetCode study plan" })
  cmd("LCPlanList", function() require("leetcode-compat.ui.study_plan").list() end, { desc = "Browse built-in LeetCode study plans" })
  cmd("LCPlanNext", function(o)
    local args = split_args(o.args)
    require("leetcode-compat.ui.study_plan").next(args[1], args[2])
  end, { nargs = "*", complete = complete_plans, desc = "Open the next unsolved study plan problem" })
  cmd("LCPlanRefresh", function(o)
    local args = split_args(o.args)
    require("leetcode-compat.ui.study_plan").refresh(args[1], args[2])
  end, { nargs = "*", complete = complete_plans, desc = "Refresh and browse a study plan" })
  cmd("LCPlanProgress", function(o)
    local args = split_args(o.args)
    require("leetcode-compat.ui.study_plan").progress(args[1])
  end, { nargs = "?", complete = complete_plans, desc = "Show study plan progress" })
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
