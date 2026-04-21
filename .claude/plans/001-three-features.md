# 三个新功能实现计划

## 概览

在现有 leetcode-nvim 插件基础上新增三个功能：
1. **每日一题** — `LCDaily` 命令
2. **随机题目** — `LCRandom` 命令
3. **间隔重复复习 (FSRS v6)** — `LCReview` 系列命令

---

## 功能 1: 每日一题 (`LCDaily`)

### 实现方式
- 在 `api.lua` 新增 `M.fetch_daily(callback)` 方法
  - leetcode.cn 使用 `todayRecord` GraphQL 查询
  - leetcode.com 使用 `activeDailyCodingChallengeQuestion` 查询
  - 返回 `titleSlug`，然后复用现有 `fetch_question` + `file.get_or_create` 流程打开题目
- 在 `init.lua` 注册 `LCDaily` 命令
- 在 `picker.lua` 新增 `M.open_daily()` 方法，调用 API 获取每日一题并打开

### 新增文件: 无
### 修改文件: `api.lua`, `init.lua`, `picker.lua`

---

## 功能 2: 随机题目 (`LCRandom`)

### 实现方式
- 在 `picker.lua` 新增 `M.open_random()` 方法
  - 调用 `api.fetch_problems_cached` 获取题目列表
  - 使用 `math.random` 随机选择一个题目
  - 复用现有 `open_local` / `fetch_and_create` 流程打开
- 在 `init.lua` 注册 `LCRandom` 命令
- 可选参数支持难度过滤: `LCRandom Easy/Medium/Hard`

### 新增文件: 无
### 修改文件: `init.lua`, `picker.lua`

---

## 功能 3: 间隔重复复习 (FSRS v6)

### 算法选择
使用 **FSRS v6 Long-Term Scheduler**（纯天数调度，无分钟级学习步骤），原因：
- LeetCode 练习场景不需要分钟级复习间隔
- 实现更简单，所有间隔都是天数
- 算法精度与 Basic Scheduler 一致

### 数据结构

每张卡片 (对应一道题目):
```lua
{
  id = 1,                    -- 题目 ID
  due = "2025-01-20",        -- 下次复习日期 (YYYY-MM-DD)
  stability = 0,             -- 记忆稳定性 (天)
  difficulty = 0,            -- 难度 (1.0-10.0)
  elapsed_days = 0,          -- 距上次复习天数
  scheduled_days = 0,        -- 计划间隔天数
  reps = 0,                  -- 总复习次数
  lapses = 0,                -- 遗忘次数
  state = 0,                 -- 0=New, 1=Learning, 2=Review, 3=Relearning
  last_review = "2025-01-15" -- 上次复习日期
}
```

### 数据存储
- 存储路径: `{workspace}/../fsrs_data.json` (与 workspace 同级目录)
- JSON 格式，包含 cards 数组和配置参数
- 初始化时扫描 workspace 中已有题目文件作为初始卡片 (state=New)

### 新增文件
1. **`lua/leetcode-compat/fsrs.lua`** — FSRS v6 算法核心实现
   - 21 个默认参数 (W[0]-W[20])
   - `forgetting_curve(elapsed_days, stability)` — 计算可提取性 R
   - `init_stability(rating)` — 初始稳定性
   - `init_difficulty(rating)` — 初始难度
   - `next_difficulty(d, rating)` — 更新难度
   - `next_recall_stability(d, s, r, rating)` — 回忆成功时的新稳定性
   - `next_forget_stability(d, s, r)` — 遗忘时的新稳定性
   - `next_interval(s)` — 计算下次间隔天数
   - `schedule(card, rating, now)` — 核心调度：输入卡片和评分，返回更新后的卡片

2. **`lua/leetcode-compat/review.lua`** — 复习数据管理 + UI
   - `load_data()` / `save_data()` — 读写 JSON 数据文件
   - `init_from_workspace()` — 从 workspace 扫描初始化卡片
   - `get_due_cards(date)` — 获取某天到期的卡片列表
   - `rate_card(id, rating)` — 对卡片评分并更新调度
   - `show_review_list()` — 显示今日待复习列表 (fzf picker)
   - `show_stats()` — 显示复习统计

### 命令
- `LCReview` — 打开今日待复习题目列表 (fzf picker)
- `LCReviewRate {rating}` — 对当前题目评分 (1=Again, 2=Hard, 3=Good, 4=Easy)
- `LCReviewStats` — 显示复习统计信息
- `LCReviewInit` — 从 workspace 初始化/同步卡片数据

### 修改文件: `init.lua`

### 复习流程
1. 用户执行 `LCReview`，显示今日到期题目列表
2. 选择题目打开练习 (复用现有打开逻辑)
3. 练习完成后执行 `LCReviewRate 3` (Good) 等命令评分
4. 系统根据 FSRS 算法计算下次复习日期并保存

---

## 实现顺序

1. 功能 1: 每日一题 (最简单，改动最小)
2. 功能 2: 随机题目 (简单，改动小)
3. 功能 3: FSRS 间隔重复 (最复杂，新增两个文件)

## 文件变更总结

| 文件 | 变更类型 |
|------|---------|
| `lua/leetcode-compat/api.lua` | 修改 — 新增 `fetch_daily` |
| `lua/leetcode-compat/init.lua` | 修改 — 注册新命令 |
| `lua/leetcode-compat/ui/picker.lua` | 修改 — 新增 `open_daily`, `open_random` |
| `lua/leetcode-compat/fsrs.lua` | 新增 — FSRS v6 算法 |
| `lua/leetcode-compat/review.lua` | 新增 — 复习管理 + UI |
