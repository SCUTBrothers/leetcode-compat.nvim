local M = {}

local config = require("leetcode-compat.config")
local auth = require("leetcode-compat.auth")

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

--- 获取题目列表 (全量)
function M.fetch_problems(callback)
  request({
    url = config.base_url() .. "/api/problems/algorithms/",
    on_done = function(err, data)
      if err then
        callback(err)
        return
      end
      if not data or not data.stat_status_pairs then
        callback("Invalid response")
        return
      end
      local problems = {}
      for _, pair in ipairs(data.stat_status_pairs) do
        local stat = pair.stat
        table.insert(problems, {
          id = stat.frontend_question_id,
          title = stat.question__title,
          slug = stat.question__title_slug,
          difficulty = ({ [1] = "Easy", [2] = "Medium", [3] = "Hard" })[pair.difficulty.level] or "Unknown",
          paid_only = pair.paid_only,
          status = pair.status, -- "ac", "notac", nil
          ac_rate = stat.total_acs > 0 and math.floor(stat.total_acs / stat.total_submitted * 100) or 0,
        })
      end
      -- 按 ID 排序
      table.sort(problems, function(a, b) return a.id < b.id end)
      callback(nil, problems)
    end,
  })
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
        topicTags { name translatedName }
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
        elseif data and data.state == "PENDING" or data.state == "STARTED" then
          M._poll_result(id, callback, attempts + 1)
        else
          callback(nil, data)
        end
      end,
    })
  end, delay)
end

return M
