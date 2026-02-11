local M = {}

local api = require("leetcode-compat.api")
local file = require("leetcode-compat.file")
local config = require("leetcode-compat.config")

--- 难度颜色映射
local difficulty_hl = {
  Easy = "DiagnosticOk",
  Medium = "DiagnosticWarn",
  Hard = "DiagnosticError",
}

--- 格式化题目显示行
---@param problem table
---@param local_ids table<number, boolean> 本地已有的题目 ID 集合
---@return string
local function format_entry(problem, local_ids)
  local mark = local_ids[problem.id] and "✓" or " "
  local status = problem.status == "ac" and "AC" or (problem.status == "notac" and "WA" or "  ")
  return string.format("[%s] %4d | %-6s | %s | %s", mark, problem.id, problem.difficulty, status, problem.title)
end

--- 通过题目 ID 查找 slug 并打开文件
---@param id number
---@param problems? table[] 可选，已有的题目列表缓存
local function open_problem(id, problems)
  -- 先检查本地文件是否存在
  local local_files = file.scan_workspace()
  for _, f in ipairs(local_files) do
    if f.id == id then
      vim.cmd("edit " .. vim.fn.fnameescape(f.filepath))
      return
    end
  end

  -- 本地没有，需要获取题目详情并创建
  local function fetch_and_open(slug)
    vim.notify("LeetCode: 正在获取题目详情...", vim.log.levels.INFO)
    api.fetch_question(slug, function(err, question)
      if err then
        vim.notify("LeetCode: 获取题目详情失败 - " .. err, vim.log.levels.ERROR)
        return
      end
      file.get_or_create(question, config.options.lang, function(filepath)
        vim.cmd("edit " .. vim.fn.fnameescape(filepath))
        vim.notify("LeetCode: 已打开 #" .. id, vim.log.levels.INFO)
      end)
    end)
  end

  -- 如果已有题目列表，直接查找 slug
  if problems then
    for _, p in ipairs(problems) do
      if p.id == id then
        fetch_and_open(p.slug)
        return
      end
    end
    vim.notify("LeetCode: 未找到题目 #" .. id, vim.log.levels.ERROR)
    return
  end

  -- 没有缓存，先获取题目列表
  vim.notify("LeetCode: 正在获取题目列表...", vim.log.levels.INFO)
  api.fetch_problems(function(err, prob_list)
    if err then
      vim.notify("LeetCode: 获取题目列表失败 - " .. err, vim.log.levels.ERROR)
      return
    end
    for _, p in ipairs(prob_list) do
      if p.id == id then
        fetch_and_open(p.slug)
        return
      end
    end
    vim.notify("LeetCode: 未找到题目 #" .. id, vim.log.levels.ERROR)
  end)
end

--- 使用 fzf-lua 打开题目选择器
---@param problems table[]
---@param local_ids table<number, boolean>
local function open_fzf(problems, local_ids)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    return false
  end

  -- 构建显示列表，本地题目置顶
  local local_entries = {}
  local remote_entries = {}
  for _, p in ipairs(problems) do
    local entry = format_entry(p, local_ids)
    if local_ids[p.id] then
      table.insert(local_entries, entry)
    else
      table.insert(remote_entries, entry)
    end
  end

  local entries = {}
  vim.list_extend(entries, local_entries)
  vim.list_extend(entries, remote_entries)

  fzf.fzf_exec(entries, {
    prompt = "LeetCode> ",
    winopts = {
      height = 0.8,
      width = 0.8,
      preview = { hidden = "hidden" },
    },
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then return end
        local line = selected[1]
        local id = tonumber(line:match("%]%s*(%d+)"))
        if id then
          open_problem(id, problems)
        end
      end,
    },
  })

  return true
end

--- 使用 vim.ui.select 作为 fallback
---@param problems table[]
---@param local_ids table<number, boolean>
local function open_vim_select(problems, local_ids)
  -- 本地题目置顶
  local sorted = {}
  local rest = {}
  for _, p in ipairs(problems) do
    if local_ids[p.id] then
      table.insert(sorted, p)
    else
      table.insert(rest, p)
    end
  end
  vim.list_extend(sorted, rest)

  vim.ui.select(sorted, {
    prompt = "LeetCode - 选择题目:",
    format_item = function(p)
      return format_entry(p, local_ids)
    end,
  }, function(choice)
    if not choice then return end
    open_problem(choice.id, problems)
  end)
end

--- 打开题目列表浏览器
function M.open()
  vim.notify("LeetCode: 正在加载题目列表...", vim.log.levels.INFO)

  -- 收集本地文件 ID
  local local_files = file.scan_workspace()
  local local_ids = {}
  for _, f in ipairs(local_files) do
    local_ids[f.id] = true
  end

  api.fetch_problems(function(err, problems)
    if err then
      vim.notify("LeetCode: 获取题目列表失败 - " .. err, vim.log.levels.ERROR)
      return
    end

    -- 尝试使用 fzf-lua
    if not open_fzf(problems, local_ids) then
      -- fallback 到 vim.ui.select
      open_vim_select(problems, local_ids)
    end
  end)
end

--- 直接通过 ID 打开题目
---@param id number
function M.open_by_id(id)
  if not id then
    vim.notify("LeetCode: 请提供题目 ID", vim.log.levels.WARN)
    return
  end
  open_problem(id)
end

return M
