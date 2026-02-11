local M = {}

local api = require("leetcode-compat.api")
local file = require("leetcode-compat.file")
local config = require("leetcode-compat.config")

--- 获取当前 buffer 的题目信息
---@return table|nil meta
local function current_meta()
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then
    vim.notify("LeetCode: 当前 buffer 不是文件", vim.log.levels.WARN)
    return nil
  end
  local meta = file.parse_metadata(filepath)
  if not meta then
    vim.notify("LeetCode: 无法解析文件元数据", vim.log.levels.WARN)
    return nil
  end
  meta.filepath = filepath
  return meta
end

--- 获取当前 buffer 的代码
---@return string|nil code
local function current_code()
  local filepath = vim.api.nvim_buf_get_name(0)
  local code = file.extract_code(filepath)
  if not code then
    vim.notify("LeetCode: 无法提取代码（需要 @lc code=start/end 标记）", vim.log.levels.WARN)
    return nil
  end
  return code
end

--- 显示运行/提交结果
---@param result table
---@param is_submit boolean
local function show_result(result, is_submit)
  local lines = {}
  local title = is_submit and "Submit Result" or "Run Result"

  table.insert(lines, "# " .. title)
  table.insert(lines, "")

  if result.status_msg then
    local icon = result.status_msg == "Accepted" and "✅" or "❌"
    table.insert(lines, icon .. " **" .. result.status_msg .. "**")
    table.insert(lines, "")
  end

  if result.status_runtime then
    table.insert(lines, "- Runtime: " .. result.status_runtime)
  end
  if result.runtime_percentile then
    table.insert(lines, string.format("- Beats: %.1f%%", result.runtime_percentile))
  end
  if result.status_memory then
    table.insert(lines, "- Memory: " .. result.status_memory)
  end
  if result.memory_percentile then
    table.insert(lines, string.format("- Memory Beats: %.1f%%", result.memory_percentile))
  end

  -- 错误信息
  if result.compile_error then
    table.insert(lines, "")
    table.insert(lines, "## Compile Error")
    table.insert(lines, "```")
    table.insert(lines, result.full_compile_error or result.compile_error)
    table.insert(lines, "```")
  end

  if result.runtime_error then
    table.insert(lines, "")
    table.insert(lines, "## Runtime Error")
    table.insert(lines, "```")
    table.insert(lines, result.full_runtime_error or result.runtime_error)
    table.insert(lines, "```")
  end

  -- 测试用例详情（run 模式）
  if not is_submit and result.code_answer then
    table.insert(lines, "")
    table.insert(lines, "## Test Cases")
    local inputs = result.std_output_list or {}
    local expected = result.expected_code_answer or {}
    local actual = result.code_answer or {}
    for i = 1, #actual do
      table.insert(lines, "")
      table.insert(lines, "### Case " .. i)
      if expected[i] then
        table.insert(lines, "- Expected: `" .. expected[i] .. "`")
      end
      table.insert(lines, "- Output:   `" .. actual[i] .. "`")
      if inputs[i] and inputs[i] ~= "" then
        table.insert(lines, "- Stdout:   `" .. inputs[i] .. "`")
      end
      local match = expected[i] and actual[i] == expected[i]
      table.insert(lines, "- Status:   " .. (match and "✅ Pass" or "❌ Fail"))
    end
  end

  -- 用 floating window 显示结果
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"

  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 4)
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })

  -- q 关闭
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
end

--- 通过 ID 查找 slug，再执行回调
---@param id number
---@param callback fun(slug: string, question: table)
local function resolve_slug_and_question(id, callback)
  api.fetch_problems(function(err, problems)
    if err then
      vim.notify("LeetCode: 获取题目列表失败 - " .. err, vim.log.levels.ERROR)
      return
    end
    local slug
    for _, p in ipairs(problems) do
      if p.id == id then
        slug = p.slug
        break
      end
    end
    if not slug then
      vim.notify("LeetCode: 未找到题目 #" .. id, vim.log.levels.ERROR)
      return
    end
    api.fetch_question(slug, function(q_err, question)
      if q_err then
        vim.notify("LeetCode: 获取题目详情失败 - " .. q_err, vim.log.levels.ERROR)
        return
      end
      callback(slug, question)
    end)
  end)
end

--- 运行测试
function M.run()
  local meta = current_meta()
  if not meta then return end
  local code = current_code()
  if not code then return end

  vim.notify("LeetCode: 正在运行测试...", vim.log.levels.INFO)

  resolve_slug_and_question(meta.id, function(slug, question)
    local test_input = table.concat(question.exampleTestcaseList or {}, "\n")
    api.run_code(slug, meta.lang, code, test_input, function(run_err, result)
      if run_err then
        vim.notify("LeetCode: 运行失败 - " .. run_err, vim.log.levels.ERROR)
        return
      end
      show_result(result, false)
    end)
  end)
end

--- 提交代码
function M.submit()
  local meta = current_meta()
  if not meta then return end
  local code = current_code()
  if not code then return end

  vim.notify("LeetCode: 正在提交...", vim.log.levels.INFO)

  resolve_slug_and_question(meta.id, function(slug, question)
    api.submit_code(slug, meta.lang, code, question.questionId, function(s_err, result)
      if s_err then
        vim.notify("LeetCode: 提交失败 - " .. s_err, vim.log.levels.ERROR)
        return
      end
      show_result(result, true)
    end)
  end)
end

return M
