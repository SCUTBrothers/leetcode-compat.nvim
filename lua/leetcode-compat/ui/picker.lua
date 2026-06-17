local M = {}

local api = require("leetcode-compat.api")
local file = require("leetcode-compat.file")
local language = require("leetcode-compat.language")

--- 格式化题目显示行
---@param problem table
---@param local_ids table<number, boolean> 本地已有的题目 ID 集合
---@return string
local function format_entry(problem, local_ids)
  local mark = local_ids[problem.id] and "✓" or " "
  local domain = problem.domain == "database" and "SQL" or "Code"
  return string.format("[%s] %4d | %-6s | %-4s | %s", mark, problem.id, problem.difficulty, domain, problem.title)
end

--- 通过题目 ID 查找并打开本地文件
---@param id number
---@param local_files table[]
---@param lang? string
---@return boolean 是否找到并打开
local function open_local(id, local_files, lang)
  lang = language.normalize(lang)
  for _, f in ipairs(local_files) do
    if f.id == id and (not lang or f.lang == lang) then
      vim.cmd("edit " .. vim.fn.fnameescape(f.filepath))
      return true
    end
  end
  return false
end

--- 通过题目 ID 从远程获取并创建文件
---@param ref number|string|table
---@param problems? table[]
---@param lang? string
local function fetch_and_create(ref, problems, lang)
  local id = type(ref) == "table" and ref.id or tonumber(ref)
  local slug = type(ref) == "table" and ref.slug or (type(ref) == "string" and not tonumber(ref) and ref or nil)

  local function do_fetch(question_slug, context)
    vim.notify("LeetCode: 正在获取题目详情...", vim.log.levels.INFO)
    api.fetch_question(question_slug, function(err, question)
      if err then
        vim.notify("LeetCode: 获取题目详情失败 - " .. err, vim.log.levels.ERROR)
        return
      end
      local selected_lang, reason = language.select_for_question(question, vim.tbl_extend("force", context or {}, { lang = lang }))
      if not selected_lang then
        vim.notify("LeetCode: 无法选择语言 - " .. (reason or "unknown"), vim.log.levels.ERROR)
        return
      end
      file.get_or_create(question, selected_lang, function(filepath)
        vim.cmd("edit " .. vim.fn.fnameescape(filepath))
        vim.notify(string.format("LeetCode: 已打开 #%s (%s)", question.questionFrontendId, language.label(selected_lang)), vim.log.levels.INFO)
      end)
    end)
  end

  if slug then
    do_fetch(slug)
    return
  end

  if problems then
    for _, p in ipairs(problems) do
      if p.id == id then
        do_fetch(p.slug, { domain = p.domain })
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
        do_fetch(p.slug, { domain = p.domain })
        return
      end
    end
    vim.notify("LeetCode: 未找到题目 #" .. id, vim.log.levels.ERROR)
  end)
end

--- 远端获取 + create_fresh 的练习流程
---@param ref number|string|table
---@param problems? table[]
---@param lang? string
local function fetch_and_practice(ref, problems, lang)
  local id = type(ref) == "table" and ref.id or tonumber(ref)
  local slug = type(ref) == "table" and ref.slug or (type(ref) == "string" and not tonumber(ref) and ref or nil)

  local function do_fetch(question_slug, context)
    vim.notify("LeetCode: 正在获取题目详情（练习模式）...", vim.log.levels.INFO)
    api.fetch_question(question_slug, function(err, question)
      if err then
        vim.notify("LeetCode: 获取题目详情失败 - " .. err, vim.log.levels.ERROR)
        return
      end
      local selected_lang, reason = language.select_for_question(question, vim.tbl_extend("force", context or {}, { lang = lang }))
      if not selected_lang then
        vim.notify("LeetCode: 无法选择语言 - " .. (reason or "unknown"), vim.log.levels.ERROR)
        return
      end
      file.create_fresh(question, selected_lang, function(filepath)
        vim.cmd("edit " .. vim.fn.fnameescape(filepath))
        vim.notify(string.format("LeetCode: 已重置 #%s (%s)", question.questionFrontendId, language.label(selected_lang)), vim.log.levels.INFO)
      end)
    end)
  end

  if slug then
    do_fetch(slug)
    return
  end

  if problems then
    for _, p in ipairs(problems) do
      if p.id == id then
        do_fetch(p.slug, { domain = p.domain })
        return
      end
    end
    vim.notify("LeetCode: 未找到题目 #" .. id, vim.log.levels.ERROR)
    return
  end

  api.fetch_problems_cached(function(err, prob_list)
    if err then
      vim.notify("LeetCode: 获取题目列表失败 - " .. err, vim.log.levels.ERROR)
      return
    end
    for _, p in ipairs(prob_list) do
      if p.id == id then
        do_fetch(p.slug, { domain = p.domain })
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

local function fetch_problems_for_domain(domain, callback)
  if domain == "database" then
    api.fetch_problemset({ tag = "database" }, callback)
    return
  end

  if domain == "algorithm" then
    api.fetch_problems_cached(function(err, problems)
      if err then
        callback(err)
        return
      end
      api.fetch_problemset({ tag = "database" }, function(db_err, db_problems)
        if db_err then
          callback(nil, problems)
          return
        end
        local db_ids = {}
        for _, p in ipairs(db_problems or {}) do
          db_ids[p.id] = true
        end
        local filtered = {}
        for _, p in ipairs(problems) do
          if not db_ids[p.id] then table.insert(filtered, p) end
        end
        callback(nil, filtered)
      end)
    end)
    return
  end

  api.fetch_problems_cached(callback)
end

--- 打开题目列表浏览器（全部列表，本地已有置顶）
---@param domain? string algorithm|database|all
---@param lang? string
function M.open(domain, lang)
  if domain == "" then domain = nil end
  if domain == "all" then domain = nil end
  local local_files = file.scan_workspace()
  local local_ids = {}
  for _, f in ipairs(local_files) do
    local_ids[f.id] = true
  end

  fetch_problems_for_domain(domain, function(err, problems)
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
        if lang or not open_local(choice.id, local_files) then
          fetch_and_create(choice.id, problems, lang)
        end
      end)
      return
    end

    fzf.fzf_exec(entries, {
      prompt = "LeetCode> ",
      keymap = fzf_navigation_keymap(),
      winopts = {
        height = 0.8,
        width = 0.8,
        preview = { hidden = "hidden" },
      },
      fzf_opts = {
        ["--header"] = "enter: 打开 | alt-p: 练习模式 | ctrl-l: 选择语言 | ctrl-n/ctrl-p: 移动",
      },
      actions = {
        ["default"] = function(selected)
          if not selected or #selected == 0 then return end
          local id = parse_id_from_entry(selected[1])
          if not id then return end
          if not lang and open_local(id, local_files) then
            return
          end
          fetch_and_create(id, problems, lang)
        end,
        ["alt-p"] = function(selected)
          if not selected or #selected == 0 then return end
          local id = parse_id_from_entry(selected[1])
          if not id then return end
          fetch_and_practice(id, problems, lang)
        end,
        ["ctrl-l"] = function(selected)
          if not selected or #selected == 0 then return end
          local id = parse_id_from_entry(selected[1])
          if not id then return end
          M.choose_language(function(chosen)
            if chosen then fetch_and_create(id, problems, chosen) end
          end)
        end,
      },
    })
  end)
end

--- 通过 ID 以练习模式打开题目（重置为默认代码模板）
---@param ref number|string
---@param lang? string
function M.practice_by_id(ref, lang)
  if not ref then
    vim.notify("LeetCode: 请提供题目 ID 或 slug", vim.log.levels.WARN)
    return
  end
  fetch_and_practice(ref, nil, lang)
end

--- 直接通过 ID 打开题目
---@param ref number|string
---@param lang? string
function M.open_by_id(ref, lang)
  if not ref then
    vim.notify("LeetCode: 请提供题目 ID 或 slug", vim.log.levels.WARN)
    return
  end
  -- 先检查本地
  local local_files = file.scan_workspace()
  local id = tonumber(ref)
  if id and open_local(id, local_files, lang) then return end
  -- 本地没有，远程获取
  fetch_and_create(ref, nil, lang)
end

--- 打开每日一题
---@param lang? string
function M.open_daily(lang)
  vim.notify("LeetCode: 正在获取每日一题...", vim.log.levels.INFO)
  api.fetch_daily(function(err, daily)
    if err then
      vim.notify("LeetCode: 获取每日一题失败 - " .. err, vim.log.levels.ERROR)
      return
    end
    vim.notify(string.format("LeetCode: 每日一题 #%d %s (%s)", daily.id, daily.title, daily.difficulty), vim.log.levels.INFO)
    local local_files = file.scan_workspace()
    if not lang and open_local(daily.id, local_files) then return end
    fetch_and_create(daily, nil, lang)
  end)
end

--- 随机打开一道题目
---@param difficulty? string "Easy"|"Medium"|"Hard"
---@param domain? string algorithm|database|all
---@param lang? string
function M.open_random(difficulty, domain, lang)
  fetch_problems_for_domain(domain, function(err, problems)
    if err then
      vim.notify("LeetCode: 获取题目列表失败 - " .. err, vim.log.levels.ERROR)
      return
    end
    local pool = problems
    if difficulty then
      pool = {}
      for _, p in ipairs(problems) do
        if p.difficulty == difficulty then
          table.insert(pool, p)
        end
      end
    end
    if #pool == 0 then
      vim.notify("LeetCode: 没有符合条件的题目", vim.log.levels.WARN)
      return
    end
    math.randomseed(os.time())
    local chosen = pool[math.random(#pool)]
    vim.notify(string.format("LeetCode: 随机题目 #%d %s (%s)", chosen.id, chosen.title, chosen.difficulty), vim.log.levels.INFO)
    local local_files = file.scan_workspace()
    if not lang and open_local(chosen.id, local_files) then return end
    fetch_and_create(chosen.id, problems, lang)
  end)
end

function M.choose_language(callback, domain)
  local langs = domain and language.by_domain(domain) or language.all()
  vim.ui.select(langs, {
    prompt = "LeetCode language:",
    format_item = function(lang)
      return string.format("%s (%s)", language.label(lang), lang)
    end,
  }, callback)
end

function M.set_or_open_language(lang)
  lang = language.normalize(lang)
  if not lang then
    M.choose_language(function(chosen)
      if chosen then M.set_or_open_language(chosen) end
    end)
    return
  end
  if not language.is_supported(lang) then
    vim.notify("LeetCode: 不支持的语言 " .. lang, vim.log.levels.ERROR)
    return
  end

  local filepath = vim.api.nvim_buf_get_name(0)
  local meta = filepath ~= "" and file.parse_metadata(filepath) or nil
  if meta then
    M.open_by_id(meta.id, lang)
    return
  end

  language.set_default(lang)
  vim.notify("LeetCode: 默认 " .. language.domain(lang) .. " 语言已设为 " .. language.label(lang), vim.log.levels.INFO)
end

return M
