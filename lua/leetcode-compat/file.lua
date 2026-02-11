local M = {}

local config = require("leetcode-compat.config")

--- VSCode LeetCode 文件格式解析
--- 文件格式示例:
--- /*
---  * @lc app=leetcode.cn id=1 lang=javascript
---  *
---  * [1] 两数之和
---  */
--- // @lc code=start
--- {code}
--- // @lc code=end

--- 解析文件名获取题目 ID
---@param filename string
---@return number|nil id
function M.parse_id_from_filename(filename)
  local basename = vim.fn.fnamemodify(filename, ":t")
  local id = basename:match("^(%d+)%.")
  return id and tonumber(id)
end

--- 解析文件名获取题目 ID 和标题
--- 文件名格式: {id}.{title}.{ext} 例如 "1.两数之和.js"
---@param filename string
---@return number|nil id, string|nil title
function M.parse_filename(filename)
  local basename = vim.fn.fnamemodify(filename, ":t:r") -- 去掉路径和扩展名
  local id_str, title = basename:match("^(%d+)%.(.+)$")
  if id_str then
    return tonumber(id_str), title
  end
  -- fallback: 只有 id
  local id = basename:match("^(%d+)")
  return id and tonumber(id), nil
end

--- 解析文件内容获取元数据
---@param filepath string
---@return table|nil metadata {id, lang, app, title}
function M.parse_metadata(filepath)
  if vim.fn.filereadable(filepath) ~= 1 then return nil end
  local lines = vim.fn.readfile(filepath, "", 10) -- 只读前 10 行

  local meta = {}
  for _, line in ipairs(lines) do
    -- @lc app=leetcode.cn id=1 lang=javascript
    local app, id, lang = line:match("@lc%s+app=(%S+)%s+id=(%d+)%s+lang=(%S+)")
    if app and id and lang then
      meta.app = app
      meta.id = tonumber(id)
      meta.lang = lang
    end
    -- [1] 两数之和
    local bracket_id, title = line:match("%[(%d+)%]%s+(.+)")
    if bracket_id and title then
      meta.title = title:match("^(.-)%s*$") -- trim trailing
    end
  end

  return meta.id and meta or nil
end

--- 从文件中提取用户代码（@lc code=start 到 @lc code=end 之间）
---@param filepath string
---@return string|nil code, number|nil start_line, number|nil end_line
function M.extract_code(filepath)
  if vim.fn.filereadable(filepath) ~= 1 then return nil end
  local lines = vim.fn.readfile(filepath)

  local start_idx, end_idx
  for i, line in ipairs(lines) do
    if line:match("@lc%s+code=start") then
      start_idx = i
    elseif line:match("@lc%s+code=end") then
      end_idx = i
      break
    end
  end

  if start_idx and end_idx and end_idx > start_idx + 1 then
    local code_lines = {}
    for i = start_idx + 1, end_idx - 1 do
      table.insert(code_lines, lines[i])
    end
    return table.concat(code_lines, "\n"), start_idx + 1, end_idx - 1
  end

  return nil
end

--- 扫描 workspace 目录，获取所有解题文件
---@return table[] files [{id, filepath, lang, title}]
function M.scan_workspace()
  local dir = config.options.workspace
  if vim.fn.isdirectory(dir) ~= 1 then return {} end

  local files = {}
  local entries = vim.fn.globpath(dir, "*", false, true)
  for _, filepath in ipairs(entries) do
    local meta = M.parse_metadata(filepath)
    if meta then
      meta.filepath = filepath
      -- 补充从文件名解析的标题（如果 metadata 中没有）
      if not meta.title then
        local _, title = M.parse_filename(filepath)
        meta.title = title
      end
      table.insert(files, meta)
    else
      -- 从文件名解析 ID 和标题
      local id, title = M.parse_filename(filepath)
      if id then
        local ext = vim.fn.fnamemodify(filepath, ":e")
        table.insert(files, {
          id = id,
          filepath = filepath,
          lang = M.ext_to_lang(ext),
          title = title,
        })
      end
    end
  end

  table.sort(files, function(a, b) return a.id < b.id end)
  return files
end

--- 文件扩展名转语言 slug
local ext_lang_map = {
  js = "javascript",
  ts = "typescript",
  py = "python3",
  java = "java",
  cpp = "cpp",
  c = "c",
  go = "golang",
  rs = "rust",
  rb = "ruby",
  swift = "swift",
  kt = "kotlin",
  scala = "scala",
  php = "php",
  cs = "csharp",
  sh = "bash",
}

function M.ext_to_lang(ext)
  return ext_lang_map[ext] or ext
end

--- 获取语言对应的注释样式
---@param lang string
---@return {single: string, block_start: string, block_end: string, block_line: string}
function M.comment_style(lang)
  local styles = {
    javascript = { single = "//", block_start = "/*", block_end = " */", block_line = " *" },
    typescript = { single = "//", block_start = "/*", block_end = " */", block_line = " *" },
    java = { single = "//", block_start = "/*", block_end = " */", block_line = " *" },
    cpp = { single = "//", block_start = "/*", block_end = " */", block_line = " *" },
    c = { single = "//", block_start = "/*", block_end = " */", block_line = " *" },
    golang = { single = "//", block_start = "/*", block_end = " */", block_line = " *" },
    rust = { single = "//", block_start = "/*", block_end = " */", block_line = " *" },
    swift = { single = "//", block_start = "/*", block_end = " */", block_line = " *" },
    kotlin = { single = "//", block_start = "/*", block_end = " */", block_line = " *" },
    scala = { single = "//", block_start = "/*", block_end = " */", block_line = " *" },
    csharp = { single = "//", block_start = "/*", block_end = " */", block_line = " *" },
    php = { single = "//", block_start = "/*", block_end = " */", block_line = " *" },
    python3 = { single = "#", block_start = "#", block_end = "#", block_line = "#" },
    python = { single = "#", block_start = "#", block_end = "#", block_line = "#" },
    ruby = { single = "#", block_start = "#", block_end = "#", block_line = "#" },
    bash = { single = "#", block_start = "#", block_end = "#", block_line = "#" },
  }
  return styles[lang] or styles.javascript
end

--- 生成新的解题文件内容
---@param question table {questionFrontendId, titleSlug, translatedTitle, title, codeSnippets}
---@param lang string
---@return string content
function M.generate_file_content(question, lang)
  local style = M.comment_style(lang)
  local id = question.questionFrontendId
  local title = question.translatedTitle or question.title
  local app = config.options.cn and "leetcode.cn" or "leetcode"

  -- 查找对应语言的代码模板
  local code_template = ""
  if question.codeSnippets then
    for _, snippet in ipairs(question.codeSnippets) do
      if snippet.langSlug == lang then
        code_template = snippet.code
        break
      end
    end
  end

  local lines = {}

  -- 块注释头部（兼容 VSCode 格式）
  if style.block_start == "/*" then
    table.insert(lines, style.block_start)
    table.insert(lines, string.format("%s @lc app=%s id=%s lang=%s", style.block_line, app, id, lang))
    table.insert(lines, style.block_line)
    table.insert(lines, string.format("%s [%s] %s", style.block_line, id, title))
    table.insert(lines, style.block_end)
  else
    table.insert(lines, string.format("%s @lc app=%s id=%s lang=%s", style.single, app, id, lang))
    table.insert(lines, string.format("%s [%s] %s", style.single, id, title))
  end

  table.insert(lines, "")
  table.insert(lines, style.single .. " @lc code=start")
  -- 代码模板
  for code_line in code_template:gmatch("([^\n]*)\n?") do
    table.insert(lines, code_line)
  end
  -- 去掉最后可能的空行
  if lines[#lines] == "" then table.remove(lines) end
  table.insert(lines, style.single .. " @lc code=end")
  table.insert(lines, "")

  return table.concat(lines, "\n")
end

--- 构建文件名
---@param question table
---@param lang string
---@return string filename
function M.build_filename(question, lang)
  local id = question.questionFrontendId
  local title = question.translatedTitle or question.title
  local ext = config.ext(lang)

  -- VSCode LeetCode 中国站格式: {id}.{中文标题}.{ext}
  -- 替换文件名中的非法字符
  title = title:gsub("[/\\:*?\"<>|]", "-")
  -- 空格转为 -
  title = title:gsub("%s+", "-")

  local pattern = config.options.file_pattern
  local filename = pattern
    :gsub("${id}", tostring(id))
    :gsub("${cn_title}", title)
    :gsub("${title}", question.title or "")
    :gsub("${slug}", question.titleSlug or "")
    :gsub("${ext}", ext)

  return filename
end

--- 获取或创建题目文件
---@param question table 题目详情
---@param lang string 语言
---@param callback fun(filepath: string)
function M.get_or_create(question, lang, callback)
  local dir = config.options.workspace
  vim.fn.mkdir(dir, "p")

  local id = tonumber(question.questionFrontendId)

  -- 先查找已有文件
  local existing = M.scan_workspace()
  for _, f in ipairs(existing) do
    if f.id == id then
      callback(f.filepath)
      return
    end
  end

  -- 创建新文件
  local filename = M.build_filename(question, lang)
  local filepath = dir .. "/" .. filename
  local content = M.generate_file_content(question, lang)
  vim.fn.writefile(vim.split(content, "\n"), filepath)
  callback(filepath)
end

return M
