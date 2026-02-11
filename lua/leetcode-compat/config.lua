local M = {}

---@class LCConfig
---@field workspace string Path to solution files directory
---@field lang string Default language (javascript, typescript, python3, etc.)
---@field cn boolean Use leetcode.cn instead of leetcode.com
---@field cookie_path string Path to cookie file
---@field file_pattern string File naming pattern
M.defaults = {
  -- 解题文件目录（兼容 VSCode LeetCode 插件的 workspace）
  workspace = vim.fn.expand("~/Documents/obsidian-workspace/programming/leetcode/workspace"),
  -- 默认语言
  lang = "javascript",
  -- 使用力扣中国站
  cn = true,
  -- Cookie 存储路径
  cookie_path = vim.fn.stdpath("data") .. "/leetcode-compat/cookie",
  -- 文件命名模式: vscode 兼容模式使用 {id}.{cn_title}.{ext}
  -- 支持变量: ${id}, ${slug}, ${title}, ${cn_title}, ${ext}
  file_pattern = "${id}.${cn_title}.${ext}",
  -- 语言文件扩展名映射
  lang_ext = {
    javascript = "js",
    typescript = "ts",
    python3 = "py",
    python = "py",
    java = "java",
    cpp = "cpp",
    c = "c",
    golang = "go",
    rust = "rs",
    ruby = "rb",
    swift = "swift",
    kotlin = "kt",
    scala = "scala",
    php = "php",
    csharp = "cs",
    bash = "sh",
  },
  -- picker 类型: "fzf" | "telescope" | "vim_select"
  picker = "fzf",
  -- 描述窗口位置
  desc_position = "right",
  desc_width = 80,
}

---@type LCConfig
M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  -- 确保 cookie 目录存在
  local cookie_dir = vim.fn.fnamemodify(M.options.cookie_path, ":h")
  vim.fn.mkdir(cookie_dir, "p")
end

--- 获取当前站点域名
function M.domain()
  return M.options.cn and "leetcode.cn" or "leetcode.com"
end

--- 获取当前站点 base URL
function M.base_url()
  return "https://" .. M.domain()
end

--- 获取语言对应的文件扩展名
function M.ext(lang)
  lang = lang or M.options.lang
  return M.options.lang_ext[lang] or lang
end

return M
