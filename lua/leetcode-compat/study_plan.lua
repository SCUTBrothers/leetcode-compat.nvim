local M = {}

local api = require("leetcode-compat.api")
local config = require("leetcode-compat.config")

local PLAN_TTL = 24 * 3600
local EMPTY_PREMIUM_TTL = 30 * 60

M.builtins = {
  {
    slug = "sql-free-50",
    title = "高频 SQL 50 题（基础版）",
    description = "数据库面试基础题单",
    premium_only = false,
    domain = "database",
    default_lang = "mysql",
  },
  {
    slug = "sql-premium-50",
    title = "高频 SQL 50 题（进阶版）",
    description = "Plus SQL 进阶题单",
    premium_only = true,
    domain = "database",
    default_lang = "mysql",
  },
}

local function cache_dir()
  return vim.fn.fnamemodify(config.options.cookie_path, ":h") .. "/studyplans"
end

local function cache_path(slug)
  return cache_dir() .. "/" .. slug .. ".json"
end

local function read_cache(slug)
  local path = cache_path(slug)
  if vim.fn.filereadable(path) ~= 1 then return nil end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or #lines == 0 then return nil end
  local parsed_ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not parsed_ok or type(data) ~= "table" then return nil end
  return data
end

local function write_cache(slug, plan)
  vim.fn.mkdir(cache_dir(), "p")
  vim.fn.writefile({ vim.json.encode({ timestamp = os.time(), plan = plan }) }, cache_path(slug))
end

local function normalize_difficulty(difficulty)
  local map = {
    EASY = "Easy",
    MEDIUM = "Medium",
    HARD = "Hard",
  }
  return map[difficulty] or difficulty or "Unknown"
end

local function builtin(slug)
  for _, plan in ipairs(M.builtins) do
    if plan.slug == slug then return plan end
  end
  return nil
end

local function not_null(value)
  if value == vim.NIL then return nil end
  return value
end

local function is_database_plan(slug, raw)
  if slug and slug:match("^sql%-") then return true end
  for _, group in ipairs(raw and raw.planSubGroups or {}) do
    for _, q in ipairs(group.questions or {}) do
      for _, tag in ipairs(q.topicTags or {}) do
        if tag.slug == "database" or tag.name == "Database" or tag.nameTranslated == "数据库" then
          return true
        end
      end
    end
  end
  return false
end

function M.normalize(raw, requested_slug)
  raw = raw or {}
  local known = builtin(requested_slug or raw.slug)
  local domain = is_database_plan(requested_slug or raw.slug, raw) and "database" or "algorithm"
  local plan = {
    slug = not_null(raw.slug) or requested_slug,
    title = not_null(raw.name) or (known and known.title) or requested_slug,
    highlight = not_null(raw.highlight),
    description = not_null(raw.description) or (known and known.description),
    premium_only = raw.premiumOnly == true or (known and known.premium_only == true),
    default_lang = not_null(raw.defaultLanguage) or (known and known.default_lang),
    domain = domain,
    groups = {},
  }

  for _, group in ipairs(raw.planSubGroups or {}) do
    local normalized_group = {
      slug = group.slug,
      title = not_null(group.name) or group.slug,
      premium_only = group.premiumOnly == true,
      question_num = group.questionNum or #(group.questions or {}),
      questions = {},
    }
    for _, q in ipairs(group.questions or {}) do
      table.insert(normalized_group.questions, {
        id = tonumber(q.questionFrontendId),
        question_id = not_null(q.id),
        slug = not_null(q.titleSlug),
        title = (config.options.cn and not_null(q.translatedTitle) or not_null(q.title)) or not_null(q.title),
        raw_title = not_null(q.title),
        difficulty = normalize_difficulty(q.difficulty),
        paid_only = q.paidOnly == true,
        status = q.status or "TO_DO",
        topicTags = q.topicTags or {},
        domain = domain,
        plan_slug = plan.slug,
        group_slug = normalized_group.slug,
        group_title = normalized_group.title,
      })
    end
    table.insert(plan.groups, normalized_group)
  end

  return plan
end

---@param slug string
---@param opts? {force?: boolean}
---@param callback fun(err?: string, plan?: table)
function M.fetch(slug, opts, callback)
  opts = opts or {}
  local cached = read_cache(slug)
  local now = os.time()

  if cached and cached.plan and not opts.force then
    local age = now - (cached.timestamp or 0)
    local ttl = cached.plan.premium_only and #cached.plan.groups == 0 and EMPTY_PREMIUM_TTL or PLAN_TTL
    if age < ttl then
      callback(nil, cached.plan)
      return
    end
  end

  api.fetch_study_plan(slug, function(err, raw)
    if err then
      if cached and cached.plan then
        callback(nil, cached.plan)
      else
        callback(err)
      end
      return
    end

    local plan = M.normalize(raw, slug)
    if #plan.groups == 0 and plan.premium_only and cached and cached.plan and #cached.plan.groups > 0 and not opts.force then
      callback(nil, cached.plan)
      return
    end
    write_cache(slug, plan)
    callback(nil, plan)
  end)
end

function M.flatten(plan)
  local questions = {}
  for _, group in ipairs(plan.groups or {}) do
    for _, q in ipairs(group.questions or {}) do
      table.insert(questions, q)
    end
  end
  return questions
end

function M.progress(plan)
  local total, done = 0, 0
  local groups = {}
  for _, group in ipairs(plan.groups or {}) do
    local g_total, g_done = 0, 0
    for _, q in ipairs(group.questions or {}) do
      total = total + 1
      g_total = g_total + 1
      if q.status == "SOLVED" or q.status == "AC" or q.status == "ACCEPTED" then
        done = done + 1
        g_done = g_done + 1
      end
    end
    table.insert(groups, {
      title = group.title,
      done = g_done,
      total = g_total,
    })
  end
  return { done = done, total = total, groups = groups }
end

function M.next_question(plan)
  local fallback = nil
  for _, q in ipairs(M.flatten(plan)) do
    fallback = fallback or q
    if q.status ~= "SOLVED" and q.status ~= "AC" and q.status ~= "ACCEPTED" then
      return q
    end
  end
  return fallback
end

function M.builtin_by_slug(slug)
  return builtin(slug)
end

return M
