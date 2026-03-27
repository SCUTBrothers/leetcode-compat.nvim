local M = {}

local api = require("leetcode-compat.api")
local file = require("leetcode-compat.file")
local config = require("leetcode-compat.config")

--- 记录描述窗口状态
local state = {
  buf = nil,
  win = nil,
}

--- 简单的 HTML 转 markdown
--- 使用多遍扫描确保嵌套标签和多行内容正确处理
---@param html string
---@return string
local function html_to_markdown(html)
  if not html or html == "" then return "" end
  local text = html

  -- 统一换行符
  text = text:gsub("\r\n", "\n")
  text = text:gsub("\r", "\n")

  -- 代码块（pre 可能包含多行和嵌套标签，必须最先处理）
  text = text:gsub("<pre>(.-)</pre>", function(code)
    code = code:gsub("<[^>]+>", "")
    -- 先解码实体再包裹
    code = code:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"):gsub("&quot;", '"')
    return "\n```\n" .. code .. "\n```\n"
  end)

  -- 内联代码（处理跨行和嵌套实体）
  text = text:gsub("<code>(.-)</code>", function(code)
    code = code:gsub("<[^>]+>", "")
    return "`" .. code .. "`"
  end)

  -- 图片
  text = text:gsub('<img[^>]-src="([^"]+)"[^>]-/?>', '![img](%1)')

  -- 强调（在去标签之前处理）
  text = text:gsub("<strong>(.-)</strong>", "**%1**")
  text = text:gsub("<b>(.-)</b>", "**%1**")
  text = text:gsub("<em>(.-)</em>", "*%1*")
  text = text:gsub("<i>(.-)</i>", "*%1*")
  text = text:gsub("<sup>(.-)</sup>", "^%1")
  text = text:gsub("<sub>(.-)</sub>", "_%1")

  -- 块级元素转换为换行标记
  text = text:gsub("<h1[^>]*>(.-)</h1>", "\n# %1\n\n")
  text = text:gsub("<h2[^>]*>(.-)</h2>", "\n## %1\n\n")
  text = text:gsub("<h3[^>]*>(.-)</h3>", "\n### %1\n\n")
  text = text:gsub("<br%s*/?>", "\n")

  -- 列表项
  text = text:gsub("<li[^>]*>(.-)</li>", "- %1\n")
  text = text:gsub("<ul[^>]*>", "\n")
  text = text:gsub("</ul>", "\n")
  text = text:gsub("<ol[^>]*>", "\n")
  text = text:gsub("</ol>", "\n")

  -- p 和 div 作为段落分隔（用开闭标签各自替换，避免跨行匹配失败）
  text = text:gsub("<p[^>]*>", "")
  text = text:gsub("</p>", "\n\n")
  text = text:gsub("<div[^>]*>", "")
  text = text:gsub("</div>", "\n")

  -- HTML 实体
  text = text:gsub("&nbsp;", " ")
  text = text:gsub("&lt;", "<")
  text = text:gsub("&gt;", ">")
  text = text:gsub("&amp;", "&")
  text = text:gsub("&quot;", '"')
  text = text:gsub("&#39;", "'")
  text = text:gsub("&le;", "<=")
  text = text:gsub("&ge;", ">=")
  text = text:gsub("&times;", "×")
  text = text:gsub("&minus;", "-")
  text = text:gsub("&#(%d+);", function(n)
    local num = tonumber(n)
    if num and num < 128 then return string.char(num) end
    return "&#" .. n .. ";"
  end)

  -- 去掉剩余 HTML 标签
  text = text:gsub("<[^>]+>", "")

  -- 清理多余空行和空白
  text = text:gsub("[ \t]+\n", "\n")
  text = text:gsub("\n\n\n+", "\n\n")
  text = text:gsub("^\n+", "")
  text = text:gsub("\n+$", "")

  return text
end

--- 构建题目描述内容
---@param question table
---@return string[]
local function build_content(question)
  local lines = {}

  -- 标题
  local title = question.translatedTitle or question.title or ""
  local id = question.questionFrontendId or ""
  table.insert(lines, "# [" .. id .. "] " .. title)
  table.insert(lines, "")

  -- 难度
  local difficulty = question.difficulty or ""
  table.insert(lines, "**难度:** " .. difficulty)
  table.insert(lines, "")

  -- 标签
  if question.topicTags and #question.topicTags > 0 then
    local tags = {}
    for _, tag in ipairs(question.topicTags) do
      table.insert(tags, tag.translatedName or tag.name)
    end
    table.insert(lines, "**标签:** " .. table.concat(tags, ", "))
    table.insert(lines, "")
  end

  -- 通过率
  if question.stats then
    local ok_stats, stats = pcall(vim.json.decode, question.stats)
    if ok_stats and stats then
      local rate = stats.acRate or stats.totalAccepted
      if rate then
        table.insert(lines, "**通过率:** " .. rate)
        table.insert(lines, "")
      end
    end
  end

  table.insert(lines, "---")
  table.insert(lines, "")

  -- 题目内容
  local content = question.translatedContent or question.content or ""
  local md_content = html_to_markdown(content)
  for line in (md_content .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, line)
  end

  return lines
end

--- 关闭描述窗口
local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
end

--- 描述窗口是否可见
---@return boolean
local function is_visible()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- 在右侧 split 窗口显示题目描述
---@param question table
function M.show(question)
  -- 如果已经显示，先关闭
  close()

  local content_lines = build_content(question)

  -- 创建 buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content_lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false

  -- 打开右侧 split
  local width = config.options.desc_width or 80
  vim.cmd("botright vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, width)

  -- 窗口选项
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].cursorline = false
  vim.wo[win].conceallevel = 0

  -- 按 q 关闭
  vim.keymap.set("n", "q", function() close() end, { buffer = buf, nowait = true })

  state.buf = buf
  state.win = win

  -- 焦点回到之前的窗口
  vim.cmd("wincmd p")
end

--- 切换显示/隐藏题目描述
function M.toggle()
  if is_visible() then
    close()
    return
  end

  -- 解析当前文件获取题目 ID
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then
    vim.notify("LeetCode: 当前 buffer 不是文件", vim.log.levels.WARN)
    return
  end

  local meta = file.parse_metadata(filepath)
  if not meta then
    vim.notify("LeetCode: 无法解析文件元数据", vim.log.levels.WARN)
    return
  end

  vim.notify("LeetCode: 正在加载题目描述...", vim.log.levels.INFO)

  -- 通过 ID 查找 slug，再获取详情
  api.fetch_problems_cached(function(err, problems)
    if err then
      vim.notify("LeetCode: 获取题目列表失败 - " .. err, vim.log.levels.ERROR)
      return
    end

    local slug
    for _, p in ipairs(problems) do
      if p.id == meta.id then
        slug = p.slug
        break
      end
    end

    if not slug then
      vim.notify("LeetCode: 未找到题目 #" .. meta.id, vim.log.levels.ERROR)
      return
    end

    api.fetch_question(slug, function(q_err, question)
      if q_err then
        vim.notify("LeetCode: 获取题目详情失败 - " .. q_err, vim.log.levels.ERROR)
        return
      end
      M.show(question)
    end)
  end)
end

return M
