local M = {}

local api = require("leetcode-compat.api")
local file = require("leetcode-compat.file")
local config = require("leetcode-compat.config")

--- 格式化题目显示行
---@param problem table
---@param local_ids table<number, boolean> 本地已有的题目 ID 集合
---@return string
local function format_entry(problem, local_ids)
  local mark = local_ids[problem.id] and "✓" or " "
  return string.format("[%s] %4d | %-6s | %s", mark, problem.id, problem.difficulty, problem.title)
end

--- 通过题目 ID 查找并打开本地文件
---@param id number
---@param local_files table[]
---@return boolean 是否找到并打开
local function open_local(id, local_files)
  for _, f in ipairs(local_files) do
    if f.id == id then
      vim.cmd("edit " .. vim.fn.fnameescape(f.filepath))
      return true
    end
  end
  return false
end

--- 通过题目 ID 从远程获取并创建文件
---@param id number
---@param problems? table[]
local function fetch_and_create(id, problems)
  local function do_fetch(slug)
    vim.notify("LeetCode: 正在获取题目详情...", vim.log.levels.INFO)
    api.fetch_question(slug, function(err, question)
      if err then
        vim.notify("LeetCode: 获取题目详情失败 - " .. err, vim.log.levels.ERROR)
        return
      end
      file.get_or_create(question, config.options.lang, function(filepath)
        vim.cmd("edit " .. vim.fn.fnameescape(filepath))
        vim.notify("LeetCode: 已创建并打开 #" .. id, vim.log.levels.INFO)
      end)
    end)
  end

  if problems then
    for _, p in ipairs(problems) do
      if p.id == id then
        do_fetch(p.slug)
        return
      end
    end
    vim.notify("LeetCode: 未找到题目 #" .. id, vim.log.levels.ERROR)
    return
  end

  -- 没有 problems 列表，先获取
  api.fetch_problems_cached(function(err, prob_list)
    if err then
      vim.notify("LeetCode: 获取题目列表失败 - " .. err, vim.log.levels.ERROR)
      return
    end
    for _, p in ipairs(prob_list) do
      if p.id == id then
        do_fetch(p.slug)
        return
      end
    end
    vim.notify("LeetCode: 未找到题目 #" .. id, vim.log.levels.ERROR)
  end)
end

--- 从 fzf 条目行中提取 ID
---@param line string
---@return number|nil
local function parse_id_from_entry(line)
  return tonumber(line:match("%]%s*(%d+)"))
end

--- 打开题目列表浏览器（全部列表，本地已有置顶）
function M.open()
  local local_files = file.scan_workspace()
  local local_ids = {}
  for _, f in ipairs(local_files) do
    local_ids[f.id] = true
  end

  api.fetch_problems_cached(function(err, problems)
    if err then
      vim.notify("LeetCode: 获取题目列表失败 - " .. err, vim.log.levels.ERROR)
      return
    end

    -- 本地已有的置顶
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

    local ok, fzf = pcall(require, "fzf-lua")
    if not ok then
      -- fallback: vim.ui.select
      vim.ui.select(problems, {
        prompt = "LeetCode:",
        format_item = function(p)
          return format_entry(p, local_ids)
        end,
      }, function(choice)
        if not choice then return end
        if not open_local(choice.id, local_files) then
          fetch_and_create(choice.id, problems)
        end
      end)
      return
    end

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
          local id = parse_id_from_entry(selected[1])
          if not id then return end
          if not open_local(id, local_files) then
            fetch_and_create(id, problems)
          end
        end,
      },
    })
  end)
end

--- 直接通过 ID 打开题目
---@param id number
function M.open_by_id(id)
  if not id then
    vim.notify("LeetCode: 请提供题目 ID", vim.log.levels.WARN)
    return
  end
  -- 先检查本地
  local local_files = file.scan_workspace()
  if open_local(id, local_files) then return end
  -- 本地没有，远程获取
  fetch_and_create(id)
end

return M
