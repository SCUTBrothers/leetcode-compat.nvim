local M = {}

local config = require("leetcode-compat.config")

local profiles = {
  javascript = {
    label = "JavaScript",
    domain = "algorithm",
    ext = "js",
    filetype = "javascript",
    single = "//",
    block_start = "/*",
    block_end = " */",
    block_line = " *",
  },
  typescript = {
    label = "TypeScript",
    domain = "algorithm",
    ext = "ts",
    filetype = "typescript",
    single = "//",
    block_start = "/*",
    block_end = " */",
    block_line = " *",
  },
  python3 = {
    label = "Python3",
    domain = "algorithm",
    ext = "py",
    filetype = "python",
    single = "#",
    block_start = "#",
    block_end = "#",
    block_line = "#",
  },
  python = {
    label = "Python",
    domain = "algorithm",
    ext = "py",
    filetype = "python",
    single = "#",
    block_start = "#",
    block_end = "#",
    block_line = "#",
  },
  java = {
    label = "Java",
    domain = "algorithm",
    ext = "java",
    filetype = "java",
    single = "//",
    block_start = "/*",
    block_end = " */",
    block_line = " *",
  },
  cpp = {
    label = "C++",
    domain = "algorithm",
    ext = "cpp",
    filetype = "cpp",
    single = "//",
    block_start = "/*",
    block_end = " */",
    block_line = " *",
  },
  c = {
    label = "C",
    domain = "algorithm",
    ext = "c",
    filetype = "c",
    single = "//",
    block_start = "/*",
    block_end = " */",
    block_line = " *",
  },
  golang = {
    label = "Go",
    domain = "algorithm",
    ext = "go",
    filetype = "go",
    single = "//",
    block_start = "/*",
    block_end = " */",
    block_line = " *",
  },
  rust = {
    label = "Rust",
    domain = "algorithm",
    ext = "rs",
    filetype = "rust",
    single = "//",
    block_start = "/*",
    block_end = " */",
    block_line = " *",
  },
  ruby = {
    label = "Ruby",
    domain = "algorithm",
    ext = "rb",
    filetype = "ruby",
    single = "#",
    block_start = "#",
    block_end = "#",
    block_line = "#",
  },
  bash = {
    label = "Bash",
    domain = "algorithm",
    ext = "sh",
    filetype = "sh",
    single = "#",
    block_start = "#",
    block_end = "#",
    block_line = "#",
  },
  mysql = {
    label = "MySQL",
    domain = "database",
    ext = "sql",
    filetype = "sql",
    single = "--",
    block_start = "/*",
    block_end = " */",
    block_line = " *",
  },
  postgresql = {
    label = "PostgreSQL",
    domain = "database",
    ext = "sql",
    filetype = "sql",
    single = "--",
    block_start = "/*",
    block_end = " */",
    block_line = " *",
  },
  mssql = {
    label = "MS SQL Server",
    domain = "database",
    ext = "sql",
    filetype = "sql",
    single = "--",
    block_start = "/*",
    block_end = " */",
    block_line = " *",
  },
  oraclesql = {
    label = "Oracle SQL",
    domain = "database",
    ext = "sql",
    filetype = "sql",
    single = "--",
    block_start = "/*",
    block_end = " */",
    block_line = " *",
  },
  pythondata = {
    label = "Pandas",
    domain = "database",
    ext = "py",
    filetype = "python",
    single = "#",
    block_start = "#",
    block_end = "#",
    block_line = "#",
  },
}

local aliases = {
  js = "javascript",
  ts = "typescript",
  py = "python3",
  go = "golang",
  sql = "mysql",
  postgres = "postgresql",
  postgresql = "postgresql",
}

local preferred_by_domain = {
  algorithm = { "javascript", "typescript", "python3", "cpp", "java" },
  database = { "mysql", "postgresql", "mssql", "oraclesql", "pythondata" },
}

function M.normalize(lang)
  if not lang or lang == vim.NIL or lang == "" or type(lang) ~= "string" then return nil end
  return aliases[lang] or lang
end

function M.profile(lang)
  lang = M.normalize(lang)
  return lang and profiles[lang] or nil
end

function M.is_supported(lang)
  return M.profile(lang) ~= nil
end

function M.label(lang)
  local profile = M.profile(lang)
  return profile and profile.label or tostring(lang or "")
end

function M.domain(lang)
  local profile = M.profile(lang)
  return profile and profile.domain or "algorithm"
end

function M.ext(lang)
  lang = M.normalize(lang)
  if config.options.lang_ext and config.options.lang_ext[lang] then
    return config.options.lang_ext[lang]
  end
  local profile = profiles[lang]
  return profile and profile.ext or lang
end

function M.filetype(lang)
  local profile = M.profile(lang)
  return profile and profile.filetype or lang
end

function M.comment_style(lang)
  local profile = M.profile(lang) or profiles.javascript
  return {
    single = profile.single,
    block_start = profile.block_start,
    block_end = profile.block_end,
    block_line = profile.block_line,
  }
end

function M.all()
  local langs = {}
  for lang, _ in pairs(profiles) do
    table.insert(langs, lang)
  end
  table.sort(langs)
  return langs
end

function M.by_domain(domain)
  local langs = vim.deepcopy(preferred_by_domain[domain] or {})
  local seen = {}
  for _, lang in ipairs(langs) do
    seen[lang] = true
  end
  for lang, profile in pairs(profiles) do
    if profile.domain == domain and not seen[lang] then
      table.insert(langs, lang)
    end
  end
  return langs
end

function M.set_default(lang)
  lang = M.normalize(lang)
  if not M.is_supported(lang) then return false end
  local domain = M.domain(lang)
  config.options.default_lang = config.options.default_lang or {}
  config.options.default_lang[domain] = lang
  if domain == "algorithm" then
    config.options.lang = lang
  end
  return true
end

function M.default_for_domain(domain)
  local defaults = config.options.default_lang or {}
  if defaults[domain] then return M.normalize(defaults[domain]) end
  if domain == "database" then return "mysql" end
  return M.normalize(config.options.lang) or "javascript"
end

local function snippet_langs(question)
  local langs = {}
  local set = {}
  for _, snippet in ipairs(question and question.codeSnippets or {}) do
    local lang = M.normalize(snippet.langSlug)
    if lang and not set[lang] then
      table.insert(langs, lang)
      set[lang] = true
    end
  end
  return langs, set
end

function M.question_has_lang(question, lang)
  lang = M.normalize(lang)
  if not lang then return false end
  local _, set = snippet_langs(question)
  return set[lang] == true
end

function M.available_for_question(question, domain)
  local langs = {}
  local question_langs, set = snippet_langs(question)
  local preferred = domain and M.by_domain(domain) or nil
  if preferred then
    for _, lang in ipairs(preferred) do
      if set[lang] then table.insert(langs, lang) end
    end
  end
  local already = {}
  for _, lang in ipairs(langs) do
    already[lang] = true
  end
  for _, lang in ipairs(question_langs) do
    if not already[lang] then table.insert(langs, lang) end
  end
  return langs
end

function M.is_database_question(question, context)
  if context and context.domain == "database" then return true end
  if context and context.plan_slug and context.plan_slug:match("^sql%-") then return true end

  for _, tag in ipairs(question and question.topicTags or {}) do
    local slug = tag.slug
    local name = tag.name or tag.translatedName or tag.nameTranslated
    if slug == "database" or name == "Database" or name == "数据库" then
      return true
    end
  end

  local langs = M.available_for_question(question)
  local has_database, has_algorithm = false, false
  for _, lang in ipairs(langs) do
    if M.domain(lang) == "database" then
      has_database = true
    elseif M.domain(lang) == "algorithm" then
      has_algorithm = true
    end
  end
  return has_database and not has_algorithm
end

function M.domain_for_question(question, context)
  return M.is_database_question(question, context) and "database" or "algorithm"
end

function M.select_for_question(question, opts)
  opts = opts or {}
  local explicit = M.normalize(opts.lang)
  if explicit then
    if not M.is_supported(explicit) then
      return nil, string.format("unsupported language: %s", explicit)
    end
    if M.question_has_lang(question, explicit) then
      return explicit
    end
    return nil, string.format("question does not provide a %s snippet", M.label(explicit))
  end

  local domain = opts.domain or M.domain_for_question(question, opts)
  local candidates = {}
  if opts.plan_default_lang then table.insert(candidates, opts.plan_default_lang) end
  table.insert(candidates, M.default_for_domain(domain))
  for _, lang in ipairs(M.by_domain(domain)) do
    table.insert(candidates, lang)
  end
  for _, lang in ipairs(candidates) do
    lang = M.normalize(lang)
    if lang and M.question_has_lang(question, lang) then
      return lang
    end
  end

  local available = M.available_for_question(question, domain)
  if #available > 0 then return available[1] end
  return M.default_for_domain(domain)
end

function M.infer_from_filename(filepath)
  local basename = vim.fn.fnamemodify(filepath, ":t")
  for _, lang in ipairs(M.all()) do
    if basename:match("%." .. vim.pesc(lang) .. "%.[^.]+$") then
      return lang
    end
  end
  local ext = vim.fn.fnamemodify(filepath, ":e")
  return aliases[ext] or ext
end

function M.strip_lang_marker(name)
  for _, lang in ipairs(M.all()) do
    local suffix = "." .. lang
    if name:sub(-#suffix) == suffix then
      return name:sub(1, #name - #suffix)
    end
  end
  return name
end

return M
