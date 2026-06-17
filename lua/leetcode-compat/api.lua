local M = {}

local config = require("leetcode-compat.config")
local auth = require("leetcode-compat.auth")

--- 内存缓存
local _problems_cache = nil
local _cache_ts = 0
local _problemset_cache = {}
local CACHE_TTL = 7 * 24 * 3600 -- 7 天（秒）

local function as_list(value)
  return type(value) == "table" and value or {}
end

--- 缓存文件路径
local function cache_path()
  local cookie_dir = vim.fn.fnamemodify(config.options.cookie_path, ":h")
  return cookie_dir .. "/problemlist.json"
end

--- 构建 HTTP 请求头
local function headers()
  local cookie = auth.get_cookie() or ""
  local csrf = auth.get_csrf() or ""
  return {
    "Content-Type: application/json",
    "Cookie: " .. cookie,
    "x-csrftoken: " .. csrf,
    "Referer: " .. config.base_url(),
    "Origin: " .. config.base_url(),
  }
end

--- 发送 HTTP 请求 (异步)
---@param opts {url: string, method?: string, body?: string, on_done: fun(err?: string, data?: table)}
local function request(opts)
  local cmd = { "curl", "-s", "-X", opts.method or "GET", opts.url }
  for _, h in ipairs(headers()) do
    table.insert(cmd, "-H")
    table.insert(cmd, h)
  end
  if opts.body then
    table.insert(cmd, "-d")
    table.insert(cmd, opts.body)
  end

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        opts.on_done("curl failed: " .. (result.stderr or "unknown error"))
        return
      end
      local ok, data = pcall(vim.json.decode, result.stdout)
      if not ok then
        opts.on_done("JSON parse error: " .. result.stdout:sub(1, 200))
        return
      end
      opts.on_done(nil, data)
    end)
  end)
end

--- 发送 GraphQL 请求
---@param query string
---@param variables? table
---@param callback fun(err?: string, data?: table)
function M.graphql(query, variables, callback)
  local body = vim.json.encode({
    query = query,
    variables = variables or {},
  })
  request({
    url = config.base_url() .. "/graphql",
    method = "POST",
    body = body,
    on_done = function(err, data)
      if err then
        callback(err)
        return
      end
      if data.errors then
        callback("GraphQL error: " .. vim.inspect(data.errors))
        return
      end
      callback(nil, data.data)
    end,
  })
end

--- 检查认证状态
function M.check_auth(callback)
  M.graphql([[
    query {
      userStatus {
        isSignedIn
        username
      }
    }
  ]], nil, function(err, data)
    if err then
      callback(false, nil)
      return
    end
    local status = data and data.userStatus
    if status and status.isSignedIn then
      callback(true, status.username)
    else
      callback(false, nil)
    end
  end)
end

--- 获取题目列表 (全量，通过 GraphQL 获取中文标题)
function M.fetch_problems(callback)
  M.graphql([[
    query allQuestions {
      allQuestionsBeta {
        questionId
        questionFrontendId
        title
        translatedTitle
        titleSlug
        difficulty
      }
    }
  ]], nil, function(err, data)
    if err then
      callback(err)
      return
    end
    local questions = data and data.allQuestionsBeta
    if not questions then
      callback("Invalid response: no allQuestionsBeta")
      return
    end
    local problems = {}
    for _, q in ipairs(as_list(questions)) do
      local id = tonumber(q.questionFrontendId)
      if id then
        table.insert(problems, {
          id = id,
          title = (config.options.cn and q.translatedTitle or q.title) or q.title,
          slug = q.titleSlug,
          difficulty = q.difficulty or "Unknown",
        })
      end
    end
    table.sort(problems, function(a, b) return a.id < b.id end)
    callback(nil, problems)
  end)
end

--- 读取本地文件缓存
---@return table|nil problems, number|nil timestamp
local function read_cache()
  local path = cache_path()
  if vim.fn.filereadable(path) ~= 1 then return nil, 0 end
  local ok, content = pcall(vim.fn.readfile, path)
  if not ok or #content == 0 then return nil, 0 end
  local parsed_ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
  if not parsed_ok or type(data) ~= "table" then return nil, 0 end
  return data.problems, data.timestamp or 0
end

--- 写入本地文件缓存
---@param problems table
local function write_cache(problems)
  local path = cache_path()
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")
  local data = vim.json.encode({ timestamp = os.time(), problems = problems })
  vim.fn.writefile({ data }, path)
end

--- 获取题目列表（带缓存）
--- 优先返回内存/文件缓存，后台刷新过期缓存
---@param callback fun(err?: string, problems?: table)
function M.fetch_problems_cached(callback)
  local now = os.time()

  -- 1. 内存缓存有效
  if _problems_cache and (now - _cache_ts) < CACHE_TTL then
    callback(nil, _problems_cache)
    return
  end

  -- 2. 尝试文件缓存
  local cached, ts = read_cache()
  if cached and (now - ts) < CACHE_TTL then
    _problems_cache = cached
    _cache_ts = ts
    callback(nil, cached)
    return
  end

  -- 3. 缓存过期但存在：先返回旧缓存，后台刷新
  if cached then
    _problems_cache = cached
    _cache_ts = ts
    callback(nil, cached)
    -- 后台刷新
    M.fetch_problems(function(err, problems)
      if not err and problems then
        _problems_cache = problems
        _cache_ts = os.time()
        write_cache(problems)
      end
    end)
    return
  end

  -- 4. 无缓存：网络请求
  M.fetch_problems(function(err, problems)
    if err then
      callback(err)
      return
    end
    _problems_cache = problems
    _cache_ts = os.time()
    write_cache(problems)
    callback(nil, problems)
  end)
end

--- 获取每日一题
function M.fetch_daily(callback)
  local is_cn = config.options.cn
  local query, extract

  if is_cn then
    query = [[
      query questionOfToday {
        todayRecord {
          date
          question {
            questionFrontendId
            titleSlug
            translatedTitle
            title
            difficulty
          }
        }
      }
    ]]
    extract = function(data)
      local records = data and data.todayRecord
      if not records or #records == 0 then return nil end
      local q = records[1].question
      return {
        id = tonumber(q.questionFrontendId),
        slug = q.titleSlug,
        title = q.translatedTitle or q.title,
        difficulty = q.difficulty,
        date = records[1].date,
      }
    end
  else
    query = [[
      query questionOfToday {
        activeDailyCodingChallengeQuestion {
          date
          question {
            questionFrontendId
            titleSlug
            title
            difficulty
          }
        }
      }
    ]]
    extract = function(data)
      local rec = data and data.activeDailyCodingChallengeQuestion
      if not rec then return nil end
      local q = rec.question
      return {
        id = tonumber(q.questionFrontendId),
        slug = q.titleSlug,
        title = q.title,
        difficulty = q.difficulty,
        date = rec.date,
      }
    end
  end

  M.graphql(query, nil, function(err, data)
    if err then
      callback(err)
      return
    end
    local daily = extract(data)
    if not daily then
      callback("Failed to parse daily question")
      return
    end
    callback(nil, daily)
  end)
end

--- 获取题目详情 (GraphQL)
function M.fetch_question(slug, callback)
  M.graphql([[
    query questionData($titleSlug: String!) {
      question(titleSlug: $titleSlug) {
        questionId
        questionFrontendId
        title
        translatedTitle
        titleSlug
        content
        translatedContent
        difficulty
        isPaidOnly
        topicTags { name slug translatedName }
        codeSnippets { lang langSlug code }
        exampleTestcaseList
        sampleTestCase
        metaData
        hints
        stats
      }
    }
  ]], { titleSlug = slug }, function(err, data)
    if err then
      callback(err)
      return
    end
    callback(nil, data and data.question)
  end)
end

--- 获取题库轻量列表，可按标签过滤
---@param opts? {tag?: string, limit?: number}
---@param callback fun(err?: string, problems?: table[])
function M.fetch_problemset(opts, callback)
  opts = opts or {}
  local tag = opts.tag
  local limit = opts.limit or 100
  local cache_key = tag or "__all__"
  local cached = _problemset_cache[cache_key]
  if cached and (os.time() - cached.ts) < CACHE_TTL then
    callback(nil, cached.problems)
    return
  end

  local query = [[
    query problemsetQuestionList($categorySlug: String, $limit: Int, $skip: Int, $filters: QuestionListFilterInput) {
      problemsetQuestionList(categorySlug: $categorySlug, limit: $limit, skip: $skip, filters: $filters) {
        total
        questions {
          frontendQuestionId
          title
          titleCn
          titleSlug
          difficulty
          paidOnly
          status
          topicTags { name slug nameTranslated }
        }
      }
    }
  ]]

  local all = {}
  local function fetch_page(skip)
    local filters = {}
    if tag then filters.tags = { tag } end
    M.graphql(query, {
      categorySlug = "all-code-essentials",
      limit = limit,
      skip = skip,
      filters = filters,
    }, function(err, data)
      if err then
        callback(err)
        return
      end
      local list = data and data.problemsetQuestionList
      if not list then
        callback("Invalid response: no problemsetQuestionList")
        return
      end
      for _, q in ipairs(as_list(list.questions)) do
        local id = tonumber(q.frontendQuestionId)
        if id then
          table.insert(all, {
            id = id,
            title = (config.options.cn and q.titleCn or q.title) or q.title,
            slug = q.titleSlug,
            difficulty = q.difficulty or "Unknown",
            paid_only = q.paidOnly,
            status = q.status,
            topicTags = q.topicTags or {},
            domain = tag == "database" and "database" or nil,
          })
        end
      end
      if #all < tonumber(list.total or 0) then
        fetch_page(skip + limit)
      else
        table.sort(all, function(a, b) return a.id < b.id end)
        _problemset_cache[cache_key] = { ts = os.time(), problems = all }
        callback(nil, all)
      end
    end)
  end

  fetch_page(0)
end

--- 获取学习计划详情
---@param slug string
---@param callback fun(err?: string, plan?: table)
function M.fetch_study_plan(slug, callback)
  M.graphql([[
    query studyPlanDetail($slug: String!) {
      studyPlanV2Detail(planSlug: $slug) {
        slug
        name
        highlight
        description
        premiumOnly
        defaultLanguage
        planSubGroups {
          slug
          name
          premiumOnly
          questionNum
          questions {
            translatedTitle
            titleSlug
            title
            questionFrontendId
            paidOnly
            id
            difficulty
            status
            topicTags {
              slug
              nameTranslated
              name
            }
          }
        }
      }
    }
  ]], { slug = slug }, function(err, data)
    if err then
      callback(err)
      return
    end
    callback(nil, data and data.studyPlanV2Detail)
  end)
end

--- 运行代码 (测试)
function M.run_code(slug, lang, code, test_input, callback)
  local body = vim.json.encode({
    lang = lang,
    question_id = slug,
    typed_code = code,
    data_input = test_input,
  })
  request({
    url = config.base_url() .. "/problems/" .. slug .. "/interpret_solution/",
    method = "POST",
    body = body,
    on_done = function(err, data)
      if err then
        callback(err)
        return
      end
      if data and data.interpret_id then
        M._poll_result(data.interpret_id, callback)
      else
        callback("Failed to run: " .. vim.inspect(data))
      end
    end,
  })
end

--- 提交代码
function M.submit_code(slug, lang, code, question_id, callback)
  local body = vim.json.encode({
    lang = lang,
    question_id = question_id,
    typed_code = code,
  })
  request({
    url = config.base_url() .. "/problems/" .. slug .. "/submit/",
    method = "POST",
    body = body,
    on_done = function(err, data)
      if err then
        callback(err)
        return
      end
      if data and data.submission_id then
        M._poll_result(data.submission_id, callback)
      else
        callback("Failed to submit: " .. vim.inspect(data))
      end
    end,
  })
end

--- 轮询结果
function M._poll_result(id, callback, attempts)
  attempts = attempts or 0
  if attempts > 30 then
    callback("Timeout waiting for result")
    return
  end
  local delay = attempts < 3 and 500 or 1000
  vim.defer_fn(function()
    request({
      url = config.base_url() .. "/submissions/detail/" .. id .. "/check/",
      on_done = function(err, data)
        if err then
          callback(err)
          return
        end
        if data and data.state == "SUCCESS" then
          callback(nil, data)
        elseif data and (data.state == "PENDING" or data.state == "STARTED") then
          M._poll_result(id, callback, attempts + 1)
        else
          callback(nil, data)
        end
      end,
    })
  end, delay)
end

return M
