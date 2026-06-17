# leetcode-compat.nvim

A Neovim plugin for LeetCode that is **fully compatible with the VSCode LeetCode extension** file format. Work on your existing solution files directly — no migration needed.

## Features

- **VSCode Compatible** — Reads and writes the same `@lc` header and `code=start`/`code=end` markers used by the [VSCode LeetCode extension](https://github.com/LeetCode-OpenSource/vscode-leetcode)
- **Use Your Existing Workspace** — Opens solution files from your current workspace directory (e.g. `{id}.{title}.js`)
- **No External CLI** — Communicates directly with LeetCode's GraphQL API via `curl`
- **Problem Browser** — Browse and search problems with [fzf-lua](https://github.com/ibhagwan/fzf-lua) integration
- **Run & Submit** — Run test cases and submit solutions without leaving Neovim
- **Problem Description** — View problem descriptions in a split window
- **SQL Practice** — Open database problems as MySQL or PostgreSQL solution files
- **Study Plans** — Browse built-in study plans such as SQL 50 directly from Neovim
- **Dual Site Support** — Works with both `leetcode.cn` and `leetcode.com`

## Requirements

- Neovim >= 0.10
- `curl` (for HTTP requests)
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) (for the problem picker)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "your-username/leetcode-compat.nvim",
  dependencies = { "ibhagwan/fzf-lua" },
  cmd = {
    "LCList", "LCOpen", "LCPractice", "LCRun", "LCSubmit", "LCDesc", "LCAuth", "LCInfo",
    "LCLang", "LCPlan", "LCPlanList", "LCPlanNext", "LCPlanRefresh", "LCPlanProgress",
  },
  keys = {
    { "<leader>ll", "<cmd>LCList<cr>",   desc = "LeetCode: Browse problems" },
    { "<leader>lp", "<cmd>LCPlan<cr>",   desc = "LeetCode: Study plans" },
    { "<leader>lq", "<cmd>LCPlan sql-free-50<cr>", desc = "LeetCode: SQL 50" },
    { "<leader>ln", "<cmd>LCPlanNext sql-free-50<cr>", desc = "LeetCode: Next SQL" },
    { "<leader>ly", "<cmd>LCLang<cr>",   desc = "LeetCode: Switch language" },
    { "<leader>lr", "<cmd>LCRun<cr>",    desc = "LeetCode: Run test cases" },
    { "<leader>ls", "<cmd>LCSubmit<cr>", desc = "LeetCode: Submit solution" },
    { "<leader>ld", "<cmd>LCDesc<cr>",   desc = "LeetCode: Problem description" },
    { "<leader>li", "<cmd>LCInfo<cr>",   desc = "LeetCode: Problem info" },
  },
  opts = {
    -- see Configuration below
  },
}
```

For local development, use `dir` instead of the GitHub URL:

```lua
{
  dir = "~/Documents/leetcode-nvim",
  -- ... same config as above
}
```

## Configuration

All options with their default values:

```lua
{
  -- Path to your solution files directory
  -- Compatible with VSCode LeetCode extension's workspace
  workspace = vim.fn.expand("~/leetcode"),

  -- Backward-compatible default algorithm language
  lang = "javascript",

  -- Domain-specific default language for new files
  default_lang = {
    algorithm = "javascript",
    database = "mysql",
  },

  -- Use leetcode.cn (China) instead of leetcode.com
  cn = true,

  -- Path to store the authentication cookie
  cookie_path = vim.fn.stdpath("data") .. "/leetcode-compat/cookie",

  -- File naming pattern
  -- Available variables: ${id}, ${slug}, ${title}, ${cn_title}, ${lang}, ${ext}
  file_pattern = "${id}.${cn_title}.${ext}",

  -- Use language marker for SQL so MySQL/PostgreSQL files can coexist
  file_pattern_by_domain = {
    algorithm = "${id}.${cn_title}.${ext}",
    database = "${id}.${cn_title}.${lang}.${ext}",
  },

  -- Language to file extension mapping
  lang_ext = {
    javascript = "js",
    typescript = "ts",
    python3 = "py",
    java = "java",
    cpp = "cpp",
    c = "c",
    golang = "go",
    rust = "rs",
    mysql = "sql",
    postgresql = "sql",
    -- ... and more
  },

  -- Picker type: "fzf" | "telescope" | "vim_select"
  picker = "fzf",

  -- Problem description window position and width
  desc_position = "right",
  desc_width = 80,
}
```

## Commands

| Command       | Description                          |
| ------------- | ------------------------------------ |
| `:LCList [algorithm\|database\|all]` | Browse problems |
| `:LCOpen {id_or_slug} [lang]` | Open problem by number or slug |
| `:LCPractice {id_or_slug} [lang]` | Reset/open a problem from its default template |
| `:LCLang [lang]` | Open current problem in another language or set session default |
| `:LCRun`      | Run test cases for current file      |
| `:LCSubmit`   | Submit solution for current file     |
| `:LCDesc`     | Toggle problem description window    |
| `:LCAuth`     | Set LeetCode authentication cookie   |
| `:LCInfo`     | Show current problem info            |
| `:LCPlan [slug] [lang]` | Browse a study plan, e.g. `:LCPlan sql-free-50` |
| `:LCPlanNext [slug] [lang]` | Open the first unsolved problem in a study plan |
| `:LCPlanRefresh [slug]` | Refresh a study plan from LeetCode |
| `:LCPlanProgress [slug]` | Show study plan progress |

## JavaScript and SQL Workflows

Algorithm problems default to JavaScript:

```vim
:LCOpen 1
```

Database problems default to MySQL:

```vim
:LCOpen 1757
```

Open a SQL problem in PostgreSQL explicitly:

```vim
:LCOpen 1757 postgresql
```

MySQL and PostgreSQL files can coexist:

```text
1757.可回收且低脂的产品.mysql.sql
1757.可回收且低脂的产品.postgresql.sql
```

SQL files still use the VSCode-compatible `@lc` metadata header, but the code
markers use SQL comments:

```sql
/*
 * @lc app=leetcode.cn id=1757 lang=mysql
 *
 * [1757] 可回收且低脂的产品
 */

-- @lc code=start
SELECT product_id
FROM Products
WHERE low_fats = 'Y' AND recyclable = 'Y';
-- @lc code=end
```

## Study Plans

Built-in study plans:

- `sql-free-50` — 高频 SQL 50 题（基础版）
- `sql-premium-50` — 高频 SQL 50 题（进阶版, Plus）

Examples:

```vim
:LCPlan
:LCPlan sql-free-50
:LCPlan sql-free-50 postgresql
:LCPlanNext sql-free-50
:LCPlanProgress sql-free-50
```

Inside the fzf study-plan picker:

```text
Enter   open/create selected problem
alt-p   reset selected problem to template
ctrl-l  switch between MySQL and PostgreSQL
alt-n   open next unsolved problem
ctrl-r  refresh the plan
ctrl-b  open the problem/plan in browser
ctrl-n  move down
ctrl-p  move up
```

## Authentication

This plugin requires a LeetCode session cookie for API access.

### How to Get Your Cookie

1. Log in to [leetcode.cn](https://leetcode.cn) (or [leetcode.com](https://leetcode.com)) in your browser
2. Open DevTools (F12) → Application → Cookies
3. Copy the values of `LEETCODE_SESSION` and `csrftoken`
4. Run `:LCAuth` in Neovim and paste in this format:
   ```
   LEETCODE_SESSION=xxx; csrftoken=xxx
   ```

The cookie is stored locally at `~/.local/share/nvim/leetcode-compat/cookie`.

## VSCode Compatibility

This plugin reads and writes the same file format as the [VSCode LeetCode extension](https://github.com/LeetCode-OpenSource/vscode-leetcode):

```javascript
/*
 * @lc app=leetcode.cn id=1 lang=javascript
 *
 * [1] Two Sum
 */
// @lc code=start
var twoSum = function(nums, target) {
    // your solution
};
// @lc code=end
```

- The `@lc` header stores problem metadata (site, ID, language)
- Code between `// @lc code=start` and `// @lc code=end` is extracted for submission
- File naming follows the same `{id}.{title}.{ext}` convention

You can seamlessly switch between VSCode and Neovim — both tools read the same files.

## License

MIT
