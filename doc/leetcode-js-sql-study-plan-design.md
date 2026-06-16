# JavaScript, SQL, and Study Plan Support Design

This document designs first-class support for:

- LeetCode algorithm problems, primarily JavaScript.
- LeetCode database problems, primarily MySQL and PostgreSQL.
- LeetCode study plans such as `sql-free-50` and `sql-premium-50`.
- A Neovim command and picker workflow that stays compatible with the current
  VSCode LeetCode file format.

## Current Baseline

The existing plugin already has the right core shape:

- `api.lua` fetches question detail with `codeSnippets { lang langSlug code }`.
- `runner.lua` submits `lang` and `typed_code` to LeetCode directly.
- `file.lua` stores `@lc app=... id=... lang=...` in each solution file.
- `picker.lua` opens local files first and creates files from remote templates.

The missing pieces are not the run/submit endpoints. They are language
selection, SQL file metadata, study plan data, and user-facing workflows.

## Product Model

Use three user concepts:

1. Problem
   A LeetCode question, opened by id, slug, daily challenge, random picker, or
   study plan row.

2. Language profile
   A local profile for a LeetCode `langSlug`. It controls label, filetype,
   file extension, comment markers, and default selection priority.

3. Study plan
   A named LeetCode plan slug with grouped questions, plan-level metadata, and
   optional progress/status.

The plugin should keep the existing single-problem workflow intact while adding
study plans as another source of question rows.

## Language Profiles

Add a small language module, for example `lua/leetcode-compat/language.lua`.
It should own all language behavior that is currently split between
`config.lua` and `file.lua`.

Recommended built-in profiles:

```lua
{
  javascript = {
    label = "JavaScript",
    domain = "algorithm",
    ext = "js",
    filetype = "javascript",
    single_comment = "//",
    block_start = "/*",
    block_line = " *",
    block_end = " */",
  },
  mysql = {
    label = "MySQL",
    domain = "database",
    ext = "sql",
    filetype = "sql",
    single_comment = "--",
    block_start = "/*",
    block_line = " *",
    block_end = " */",
  },
  postgresql = {
    label = "PostgreSQL",
    domain = "database",
    ext = "sql",
    filetype = "sql",
    single_comment = "--",
    block_start = "/*",
    block_line = " *",
    block_end = " */",
  },
}
```

Keep `mssql` and `oraclesql` optional but supported by the same SQL comment
style, because LeetCode SQL questions commonly expose those snippets too.

### Default Language Rules

Replace the single `config.options.lang` decision with a language selection
function:

```lua
select_language(question, opts)
```

Priority:

1. Explicit command argument, for example `:LCOpen 1757 postgresql`.
2. Current file metadata, when running/submitting an existing file.
3. Existing local file for the same question and requested domain.
4. Plan default language, if LeetCode provides one.
5. Domain default:
   - algorithm: `config.options.default_lang.algorithm`, default `javascript`
   - database: `config.options.default_lang.database`, default `mysql`
6. First supported snippet in `question.codeSnippets`.
7. User picker if multiple snippets exist and no safe default is available.

Domain detection:

- Treat a question as database when one of these is true:
  - `topicTags` contains `database`.
  - code snippets include `mysql`, `postgresql`, `mssql`, or `oraclesql` and do
    not include normal algorithm languages.
  - the current study plan slug is configured as a database plan, for example
    `sql-free-50`.
- Otherwise treat it as algorithm.

This keeps `:LCOpen 1` opening JavaScript by default and lets `:LCOpen 1757`
open MySQL by default.

### File Names

The current default pattern `${id}.${cn_title}.${ext}` works for one solution
per problem, but MySQL and PostgreSQL both use `.sql`. To avoid collisions,
support language-aware file patterns:

```lua
file_pattern = "${id}.${cn_title}.${ext}",
file_pattern_by_domain = {
  algorithm = "${id}.${cn_title}.${ext}",
  database = "${id}.${cn_title}.${lang}.${ext}",
}
```

Examples:

```text
1.两数之和.js
1757.可回收且低脂的产品.mysql.sql
1757.可回收且低脂的产品.postgresql.sql
```

The file header remains the authoritative source:

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

For compatibility with existing files, `scan_workspace()` should continue to
parse metadata first. If metadata is missing, it can infer:

- `*.js` -> `javascript`
- `*.mysql.sql` -> `mysql`
- `*.postgresql.sql` -> `postgresql`
- plain `*.sql` -> `config.options.default_lang.database`

### Run and Submit

Do not add separate SQL submission endpoints. `runner.lua` should continue to
parse the current file metadata and call:

```lua
api.run_code(slug, meta.lang, code, test_input, callback)
api.submit_code(slug, meta.lang, code, question.questionId, callback)
```

For SQL files, `meta.lang` is `mysql` or `postgresql`, so the existing endpoint
shape remains valid.

Improve the result display for database problems:

- Prefer table-like output when LeetCode returns rows/columns as text.
- Keep raw error blocks unchanged for SQL syntax/runtime errors.
- On accepted submission, refresh the active study plan cache if the question
  was opened from a plan.

## Study Plan API

Add `lua/leetcode-compat/study_plan.lua` for plan-specific data and cache, or
keep the HTTP call in `api.lua` and put normalization/cache in `study_plan.lua`.

The current LeetCode CN study plan page uses `studyPlanV2Detail(planSlug)`.
The useful query shape is:

```graphql
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
```

Verified assumptions as of 2026-06-16:

- `sql-free-50` returns grouped questions through `studyPlanV2Detail(planSlug)`.
- `sql-premium-50` can return `premiumOnly = true` and an empty
  `planSubGroups` list when the current session lacks access.
- SQL question snippets expose LeetCode language slugs such as `mysql`,
  `postgresql`, `mssql`, and `oraclesql`.

Normalize it into:

```lua
{
  slug = "sql-free-50",
  title = "高频 SQL 50 题（基础版）",
  premium_only = false,
  default_lang = nil,
  groups = {
    {
      slug = "sql-free-50-66-e4w9",
      title = "查询",
      premium_only = false,
      questions = {
        {
          id = 1757,
          slug = "recyclable-and-low-fat-products",
          title = "可回收且低脂的产品",
          difficulty = "EASY",
          paid_only = false,
          status = "TO_DO",
          domain = "database",
          plan_slug = "sql-free-50",
          group_slug = "sql-free-50-66-e4w9",
        },
      },
    },
  },
}
```

Premium behavior:

- If a plan returns `premiumOnly = true` and `planSubGroups = {}`, show a clear
  message instead of treating it as an empty plan.
- Cache the metadata with a short TTL, but do not overwrite a previously useful
  cache with an empty premium response unless the user explicitly refreshes.

Recommended cache files:

```text
{cookie_dir}/problemlist.json
{cookie_dir}/studyplans/sql-free-50.json
{cookie_dir}/studyplans/sql-premium-50.json
```

Recommended TTL:

- Full problem list: keep current 7 days.
- Study plan detail: 24 hours.
- Premium/permission-empty response: 30 minutes.

## Commands

Keep existing commands stable and extend them rather than replacing them.

### Core Problem Commands

```text
:LCList [algorithm|database|all]
:LCOpen {id_or_slug} [lang]
:LCPractice {id_or_slug} [lang]
:LCRun
:LCSubmit
:LCDesc
:LCInfo
:LCDaily [lang]
:LCRandom [Easy|Medium|Hard] [algorithm|database]
:LCLang [javascript|mysql|postgresql]
```

Behavior:

- `:LCOpen 1` opens problem 1 in JavaScript by default.
- `:LCOpen 1757` opens problem 1757 in MySQL by default.
- `:LCOpen 1757 postgresql` opens or creates the PostgreSQL version.
- `:LCLang mysql` changes the preferred language for the current buffer when
  safe, and otherwise updates the default language for new database files in the
  current Neovim session.

### Study Plan Commands

```text
:LCPlan [slug] [lang]
:LCPlanList
:LCPlanNext [slug] [lang]
:LCPlanRefresh [slug]
:LCPlanProgress [slug]
```

Behavior:

- `:LCPlan` opens a plan picker. Include built-ins first:
  - `sql-free-50`
  - `sql-premium-50`
- `:LCPlan sql-free-50` opens that plan's grouped question picker.
- `:LCPlan sql-free-50 postgresql` opens the same picker with PostgreSQL as the
  plan language.
- `:LCPlanNext sql-free-50` opens the first unsolved item in plan order.
- `:LCPlanRefresh sql-free-50` bypasses the plan cache.
- `:LCPlanProgress sql-free-50` shows completed/todo counts per group and total.

Do not make a separate `:LCSQL` command necessary. SQL is a language/domain,
not a separate product mode. A convenience alias can be added later if users ask
for it:

```text
:LCSQL [mysql|postgresql] -> :LCPlan sql-free-50 [lang]
```

## Picker Interaction

### `:LCList`

Rows:

```text
[✓] 0001 | Easy   | JS       | 两数之和
[ ] 1757 | Easy   | SQL      | 可回收且低脂的产品
```

Actions:

```text
Enter   open existing file or create with selected/default language
Ctrl-p  practice mode: reset to remote template
Ctrl-l  choose language before opening
Ctrl-d  open/toggle description preview
Ctrl-b  open problem in browser
```

Filters:

- `algorithm`: hide database-only questions.
- `database`: show database questions.
- `all`: current behavior.

### `:LCPlan`

Plan picker rows:

```text
SQL 50 基础版      sql-free-50       0/50
SQL 50 进阶版      sql-premium-50    Plus
```

Plan detail rows:

```text
查询
[ ] 1757 | Easy   | mysql | 可回收且低脂的产品
[ ] 0584 | Easy   | mysql | 寻找用户推荐人

连接
[ ] 1378 | Easy   | mysql | 使用唯一标识码替换员工ID
```

Actions:

```text
Enter   open/create selected problem
Ctrl-p  reset selected problem to template
Ctrl-l  switch plan language between MySQL/PostgreSQL
Ctrl-n  open next unsolved item
Ctrl-r  refresh plan from LeetCode
Ctrl-b  open plan or problem in browser
```

When switching MySQL/PostgreSQL, update the picker header and new file language;
do not rewrite already opened files.

## Recommended Keymaps

Do not force keymaps by default. Document recommended lazy.nvim bindings:

```lua
keys = {
  { "<leader>ll", "<cmd>LCList<cr>", desc = "LeetCode: problems" },
  { "<leader>lo", "<cmd>LCOpen ", desc = "LeetCode: open by id" },
  { "<leader>lp", "<cmd>LCPlan<cr>", desc = "LeetCode: plans" },
  { "<leader>lq", "<cmd>LCPlan sql-free-50<cr>", desc = "LeetCode: SQL 50" },
  { "<leader>ln", "<cmd>LCPlanNext sql-free-50<cr>", desc = "LeetCode: next SQL" },
  { "<leader>ly", "<cmd>LCLang<cr>", desc = "LeetCode: language" },
  { "<leader>lr", "<cmd>LCRun<cr>", desc = "LeetCode: run" },
  { "<leader>ls", "<cmd>LCSubmit<cr>", desc = "LeetCode: submit" },
  { "<leader>ld", "<cmd>LCDesc<cr>", desc = "LeetCode: description" },
  { "<leader>li", "<cmd>LCInfo<cr>", desc = "LeetCode: info" },
}
```

Rationale:

- `ll`, `lo`, `lr`, `ls`, `ld`, `li` preserve the current mental model.
- `lp` is the general study plan entry.
- `lq` is a fast path for the user's main SQL plan.
- `ln` supports daily progress through a plan without reopening the picker.
- `ly` avoids overloading `l` and gives language/dialect a stable place.

## Implementation Phases

### Phase 1: Language Profiles

- Add `language.lua`.
- Add SQL profiles for `mysql` and `postgresql`.
- Add optional `mssql`, `oraclesql`, and `pythondata` mappings.
- Update `config.lua` defaults:
  - `default_lang = { algorithm = "javascript", database = "mysql" }`
  - `file_pattern_by_domain.database = "${id}.${cn_title}.${lang}.${ext}"`
- Update `file.lua` to use language profiles for extension and comments.
- Update `picker.lua` and `init.lua` so `:LCOpen` and `:LCPractice` accept an
  optional language argument.

Verification:

- `:LCOpen 1` creates JavaScript.
- `:LCOpen 1757 mysql` creates `*.mysql.sql` with `-- @lc code=start`.
- `:LCOpen 1757 postgresql` creates a separate `*.postgresql.sql`.
- `:LCRun` and `:LCSubmit` read `lang` from metadata.

### Phase 2: Study Plan Fetch and Picker

- Add `api.fetch_study_plan(slug, callback)` or equivalent.
- Add `study_plan.lua` for cache and normalization.
- Add `ui/study_plan.lua` for plan and plan-detail pickers.
- Register `:LCPlan`, `:LCPlanList`, `:LCPlanNext`, `:LCPlanRefresh`, and
  `:LCPlanProgress`.
- Support `sql-free-50` as a built-in plan.
- Show a premium/permission message for `sql-premium-50` if LeetCode returns no
  groups.

Verification:

- `:LCPlan sql-free-50` shows grouped SQL 50 questions.
- `:LCPlan sql-free-50 postgresql` creates PostgreSQL files.
- `:LCPlanNext sql-free-50` opens the first `TO_DO` problem.
- `:LCPlan sql-premium-50` reports Plus/permission state instead of silently
  showing an empty list.

### Phase 3: Progress and Polish

- Refresh plan cache after accepted submissions.
- Add command completion for language and plan slug arguments.
- Add browser-open actions for problem and plan URLs.
- Add README docs and examples.
- Add small Lua tests for language selection and file generation if the project
  adopts a test runner.

## Open Decisions

1. Whether to keep `config.options.lang` as a backward-compatible alias for
   `default_lang.algorithm`.
   Recommendation: keep it for one release and map it internally.

2. Whether SQL plan progress should be local-only or LeetCode-backed.
   Recommendation: read LeetCode `status` when available, but do not require
   joining the plan to use the picker.

3. Whether to support multiple language files for algorithm questions.
   Recommendation: support it naturally through the language-aware filename
   logic, but do not optimize the UI around it yet.
