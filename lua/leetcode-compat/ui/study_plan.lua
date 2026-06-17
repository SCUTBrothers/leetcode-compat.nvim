local M = {}

local study_plan = require("leetcode-compat.study_plan")
local picker = require("leetcode-compat.ui.picker")
local language = require("leetcode-compat.language")

local function plan_url(slug)
  return require("leetcode-compat.config").base_url() .. "/studyplan/" .. slug .. "/"
end

local function question_url(slug)
  return require("leetcode-compat.config").base_url() .. "/problems/" .. slug .. "/"
end

local function format_plan_entry(plan)
  local suffix = plan.premium_only and "Plus" or (plan.description or "")
  return string.format("%-24s %-20s %s", plan.title or plan.slug, plan.slug, suffix)
end

local function format_question_entry(q, lang)
  local status = q.status == "SOLVED" and "✓" or " "
  local paid = q.paid_only and "Plus" or ""
  return string.format("[%s] %4d | %-6s | %-10s | %-5s | %s", status, q.id, q.difficulty, lang or "", paid, q.title)
end

local function fzf_navigation_keymap()
  return {
    fzf = {
      ["ctrl-n"] = "down",
      ["ctrl-j"] = "down",
      ["ctrl-p"] = "up",
      ["ctrl-k"] = "up",
    },
  }
end

local function show_premium_empty(plan)
  local msg = string.format("LeetCode: %s 是 Plus 学习计划，当前账号未返回题目分组", plan.title or plan.slug)
  vim.notify(msg, vim.log.levels.WARN)
end

local function open_question(q, lang, practice)
  if not q then return end
  if practice then
    picker.practice_by_id(q.slug, lang)
  else
    picker.open_by_id(q.slug, lang)
  end
end

function M.list()
  local entries = {}
  local by_entry = {}
  for _, plan in ipairs(study_plan.builtins) do
    local entry = format_plan_entry(plan)
    table.insert(entries, entry)
    by_entry[entry] = plan
  end

  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.ui.select(study_plan.builtins, {
      prompt = "LeetCode study plan:",
      format_item = function(plan) return format_plan_entry(plan) end,
    }, function(plan)
      if plan then M.open(plan.slug, plan.default_lang) end
    end)
    return
  end

  fzf.fzf_exec(entries, {
    prompt = "LCPlan> ",
    keymap = fzf_navigation_keymap(),
    winopts = {
      height = 0.6,
      width = 0.8,
      preview = { hidden = "hidden" },
    },
    fzf_opts = {
      ["--header"] = "enter: 打开计划 | ctrl-b: 浏览器打开",
    },
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then return end
        local plan = by_entry[selected[1]]
        if plan then M.open(plan.slug, plan.default_lang) end
      end,
      ["ctrl-b"] = function(selected)
        if not selected or #selected == 0 then return end
        local plan = by_entry[selected[1]]
        if plan then vim.ui.open(plan_url(plan.slug)) end
      end,
    },
  })
end

function M.open(slug, lang, opts)
  opts = opts or {}
  if not slug or slug == "" then
    M.list()
    return
  end
  lang = language.normalize(lang)

  vim.notify("LeetCode: 正在获取学习计划 " .. slug .. "...", vim.log.levels.INFO)
  study_plan.fetch(slug, { force = opts.force }, function(err, plan)
    if err then
      vim.notify("LeetCode: 获取学习计划失败 - " .. err, vim.log.levels.ERROR)
      return
    end
    if plan.premium_only and #plan.groups == 0 then
      show_premium_empty(plan)
      return
    end

    local plan_lang = lang or plan.default_lang or language.default_for_domain(plan.domain)
    local entries = {}
    local by_entry = {}
    local question_count = 0
    for _, group in ipairs(plan.groups or {}) do
      table.insert(entries, "")
      table.insert(entries, "## " .. (group.title or group.slug))
      for _, q in ipairs(group.questions or {}) do
        local entry = format_question_entry(q, plan_lang)
        table.insert(entries, entry)
        by_entry[entry] = q
        question_count = question_count + 1
      end
    end

    if question_count == 0 then
      vim.notify("LeetCode: 学习计划没有可打开的题目", vim.log.levels.WARN)
      return
    end

    local ok, fzf = pcall(require, "fzf-lua")
    if not ok then
      local questions = study_plan.flatten(plan)
      vim.ui.select(questions, {
        prompt = plan.title .. ":",
        format_item = function(q) return format_question_entry(q, plan_lang) end,
      }, function(q)
        open_question(q, plan_lang, false)
      end)
      return
    end

    fzf.fzf_exec(entries, {
      prompt = "LCPlan " .. slug .. "> ",
      keymap = fzf_navigation_keymap(),
      winopts = {
        height = 0.8,
        width = 0.9,
        preview = { hidden = "hidden" },
      },
      fzf_opts = {
        ["--header"] = string.format("%s | lang=%s | enter: 打开 | alt-p: 练习 | ctrl-l: MySQL/PostgreSQL | alt-n: 下一题 | ctrl-r: 刷新 | ctrl-b: 浏览器 | ctrl-n/ctrl-p: 移动", plan.title, plan_lang),
      },
      actions = {
        ["default"] = function(selected)
          if not selected or #selected == 0 then return end
          open_question(by_entry[selected[1]], plan_lang, false)
        end,
        ["alt-p"] = function(selected)
          if not selected or #selected == 0 then return end
          open_question(by_entry[selected[1]], plan_lang, true)
        end,
        ["ctrl-l"] = function()
          local next_lang = plan_lang == "postgresql" and "mysql" or "postgresql"
          M.open(slug, next_lang)
        end,
        ["alt-n"] = function()
          M.next(slug, plan_lang)
        end,
        ["ctrl-r"] = function()
          M.open(slug, plan_lang, { force = true })
        end,
        ["ctrl-b"] = function(selected)
          if selected and #selected > 0 and by_entry[selected[1]] then
            vim.ui.open(question_url(by_entry[selected[1]].slug))
          else
            vim.ui.open(plan_url(slug))
          end
        end,
      },
    })
  end)
end

function M.next(slug, lang)
  if not slug or slug == "" then slug = "sql-free-50" end
  study_plan.fetch(slug, {}, function(err, plan)
    if err then
      vim.notify("LeetCode: 获取学习计划失败 - " .. err, vim.log.levels.ERROR)
      return
    end
    if plan.premium_only and #plan.groups == 0 then
      show_premium_empty(plan)
      return
    end
    local q = study_plan.next_question(plan)
    if not q then
      vim.notify("LeetCode: 学习计划没有题目", vim.log.levels.WARN)
      return
    end
    open_question(q, language.normalize(lang) or plan.default_lang or language.default_for_domain(plan.domain), false)
  end)
end

function M.refresh(slug, lang)
  if not slug or slug == "" then slug = "sql-free-50" end
  M.open(slug, lang, { force = true })
end

function M.progress(slug)
  if not slug or slug == "" then slug = "sql-free-50" end
  study_plan.fetch(slug, {}, function(err, plan)
    if err then
      vim.notify("LeetCode: 获取学习计划失败 - " .. err, vim.log.levels.ERROR)
      return
    end
    if plan.premium_only and #plan.groups == 0 then
      show_premium_empty(plan)
      return
    end

    local progress = study_plan.progress(plan)
    local lines = {
      "# " .. (plan.title or plan.slug),
      "",
      string.format("Progress: %d / %d", progress.done, progress.total),
      "",
    }
    for _, group in ipairs(progress.groups) do
      table.insert(lines, string.format("- %s: %d / %d", group.title, group.done, group.total))
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].bufhidden = "wipe"

    local width = math.min(80, vim.o.columns - 4)
    local height = math.min(#lines + 2, vim.o.lines - 4)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      style = "minimal",
      border = "rounded",
      title = " LCPlan Progress ",
      title_pos = "center",
    })
    vim.keymap.set("n", "q", function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end, { buffer = buf, nowait = true })
  end)
end

function M.complete_plans()
  local items = {}
  for _, plan in ipairs(study_plan.builtins) do
    table.insert(items, plan.slug)
  end
  return items
end

return M
