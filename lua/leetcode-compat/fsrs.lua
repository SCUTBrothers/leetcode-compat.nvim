--- FSRS v6 Long-Term Scheduler
--- 基于 open-spaced-repetition/go-fsrs 移植
local M = {}

-- 评分常量
M.Again = 1
M.Hard = 2
M.Good = 3
M.Easy = 4

-- 状态常量
M.New = 0
M.Learning = 1
M.Review = 2
M.Relearning = 3

-- FSRS v6 默认参数 (21 个)
M.default_weights = {
  [0]  = 0.212,    -- S0(Again)
  [1]  = 1.2931,   -- S0(Hard)
  [2]  = 2.3065,   -- S0(Good)
  [3]  = 8.2956,   -- S0(Easy)
  [4]  = 6.4133,   -- D0 base
  [5]  = 0.8334,   -- D0 rating scaling
  [6]  = 3.0194,   -- difficulty delta scaling
  [7]  = 0.001,    -- mean reversion weight
  [8]  = 1.8722,   -- recall stability multiplier
  [9]  = 0.1666,   -- recall stability power on S
  [10] = 0.796,    -- recall stability R scaling
  [11] = 1.4835,   -- forget stability base
  [12] = 0.0614,   -- forget stability D power
  [13] = 0.2629,   -- forget stability (S+1) power
  [14] = 1.6483,   -- forget stability R scaling
  [15] = 0.6014,   -- hard penalty
  [16] = 1.8729,   -- easy bonus
  [17] = 0.5425,   -- short-term stability multiplier
  [18] = 0.0912,   -- short-term stability offset
  [19] = 0.0658,   -- short-term stability power on S
  [20] = 0.1542,   -- forgetting curve decay
}

-- 默认配置
M.default_config = {
  request_retention = 0.9,
  maximum_interval = 36500,
  weights = nil, -- nil 时使用 default_weights
}

local function clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

--- 创建调度器实例
---@param opts? table { request_retention, maximum_interval, weights }
---@return table scheduler
function M.new(opts)
  opts = opts or {}
  local self = {}
  self.request_retention = opts.request_retention or M.default_config.request_retention
  self.maximum_interval = opts.maximum_interval or M.default_config.maximum_interval
  self.w = opts.weights or M.default_weights

  -- 预计算 decay 和 factor
  self.decay = -self.w[20]
  self.factor = math.pow(0.9, 1 / self.decay) - 1

  --- 遗忘曲线：计算可提取性 R
  function self.forgetting_curve(elapsed_days, stability)
    if stability <= 0 then return 0 end
    return math.pow(1 + self.factor * elapsed_days / stability, self.decay)
  end

  --- 初始稳定性
  function self.init_stability(rating)
    return clamp(self.w[rating - 1], 0.001, 36500)
  end

  --- 初始难度
  function self.init_difficulty(rating)
    local d = self.w[4] - math.exp(self.w[5] * (rating - 1)) + 1
    return clamp(d, 1, 10)
  end

  --- 线性阻尼
  local function linear_damping(delta_d, d)
    return (10 - d) * delta_d / 9
  end

  --- 均值回归
  local function mean_reversion(init, current)
    return self.w[7] * init + (1 - self.w[7]) * current
  end

  --- 更新难度
  function self.next_difficulty(d, rating)
    local delta_d = -self.w[6] * (rating - 3)
    local next_d = d + linear_damping(delta_d, d)
    next_d = mean_reversion(self.init_difficulty(M.Easy), next_d)
    return clamp(next_d, 1, 10)
  end

  --- 回忆成功时的新稳定性
  function self.next_recall_stability(d, s, r, rating)
    local hard_penalty = (rating == M.Hard) and self.w[15] or 1
    local easy_bonus = (rating == M.Easy) and self.w[16] or 1
    local new_s = s * (1 + math.exp(self.w[8])
      * (11 - d)
      * math.pow(s, -self.w[9])
      * (math.exp((1 - r) * self.w[10]) - 1)
      * hard_penalty
      * easy_bonus)
    return clamp(new_s, 0.001, 36500)
  end

  --- 遗忘时的新稳定性
  function self.next_forget_stability(d, s, r)
    local new_s = self.w[11]
      * math.pow(d, -self.w[12])
      * (math.pow(s + 1, self.w[13]) - 1)
      * math.exp((1 - r) * self.w[14])
    -- ceiling: 不超过遗忘前稳定性的衰减值
    local ceiling = s / math.exp(self.w[17] * self.w[18])
    new_s = math.min(new_s, ceiling)
    return clamp(new_s, 0.001, 36500)
  end

  --- 计算下次间隔天数
  function self.next_interval(s)
    local interval = s / self.factor * (math.pow(self.request_retention, 1 / self.decay) - 1)
    return clamp(math.floor(interval + 0.5), 1, self.maximum_interval)
  end

  --- 核心调度：Long-Term Scheduler
  --- 所有状态都直接转为 Review，间隔以天为单位
  ---@param card table 卡片数据
  ---@param rating number 1-4
  ---@param now? number 当前时间戳 (os.time())
  ---@return table new_card 更新后的卡片
  function self.schedule(card, rating, now)
    now = now or os.time()
    local c = {}
    for k, v in pairs(card) do c[k] = v end

    -- 计算距上次复习的天数
    local elapsed_days = 0
    if c.last_review and c.last_review ~= "" then
      local last_ts = M.parse_date(c.last_review)
      if last_ts then
        elapsed_days = math.max(0, math.floor((now - last_ts) / 86400))
      end
    end
    c.elapsed_days = elapsed_days

    if c.state == M.New then
      -- 新卡片
      c.difficulty = self.init_difficulty(rating)
      c.stability = self.init_stability(rating)
      c.reps = 1
      if rating == M.Again then
        c.lapses = (c.lapses or 0) + 1
      end
    else
      -- 已有卡片
      local r = self.forgetting_curve(elapsed_days, c.stability)
      c.difficulty = self.next_difficulty(c.difficulty, rating)
      if rating == M.Again then
        c.stability = self.next_forget_stability(c.difficulty, c.stability, r)
        c.lapses = (c.lapses or 0) + 1
      else
        c.stability = self.next_recall_stability(c.difficulty, c.stability, r, rating)
      end
      c.reps = (c.reps or 0) + 1
    end

    -- Long-Term: 所有状态都转为 Review
    c.state = M.Review
    local interval = self.next_interval(c.stability)
    c.scheduled_days = interval
    c.last_review = os.date("%Y-%m-%d", now)
    c.due = os.date("%Y-%m-%d", now + interval * 86400)

    return c
  end

  return self
end

--- 创建新卡片
---@param id number 题目 ID
---@return table card
function M.new_card(id)
  return {
    id = id,
    due = os.date("%Y-%m-%d"),  -- 今天即可复习
    stability = 0,
    difficulty = 0,
    elapsed_days = 0,
    scheduled_days = 0,
    reps = 0,
    lapses = 0,
    state = M.New,
    last_review = "",
  }
end

--- 解析日期字符串为时间戳
---@param date_str string "YYYY-MM-DD"
---@return number|nil timestamp
function M.parse_date(date_str)
  if not date_str or date_str == "" then return nil end
  local y, m, d = date_str:match("^(%d+)-(%d+)-(%d+)$")
  if not y then return nil end
  return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

--- 判断卡片是否到期
---@param card table
---@param date_str? string "YYYY-MM-DD"，默认今天
---@return boolean
function M.is_due(card, date_str)
  date_str = date_str or os.date("%Y-%m-%d")
  return card.due <= date_str
end

return M
