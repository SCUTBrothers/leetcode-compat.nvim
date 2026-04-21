--- 间隔重复复习管理
local M = {}

local config = require("leetcode-compat.config")
local file = require("leetcode-compat.file")
local fsrs = require("leetcode-compat.fsrs")

local _data = nil -- 内存缓存

--- 数据文件路径
local function data_path()
  local ws = config.options.workspace
  local parent = vim.fn.fnamemodify(ws, ":h")
  return parent .. "/fsrs_data.json"
end

--- 加载数据
---@return table { cards: table<number, table>, config: table }
function M.load_data()
  if _data then return _data end

  local path = data_path()
  if vim.fn.filereadable(path) == 1 then
    local ok, content = pcall(vim.fn.readfile, path)
    if ok and #content > 0 then
      local parsed_ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
      if parsed_ok and type(data) == "table" then
        -- cards 从数组转为 id -> card 的 map
        if data.cards and vim.islist(data.cards) then
          local map = {}
          for _, card in ipairs(data.cards) do
            if card.id then map[card.id] = card end
          end
          data.cards = map
        end
        _data = data
        return _data
      end
    end
  end

  _data = { cards = {}, config = {} }
  return _data
end

--- 保存数据
function M.save_data()
  if not _data then return end
  local path = data_path()
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")

  -- cards 从 map 转为数组存储
  local cards_list = {}
  for _, card in pairs(_data.cards) do
    table.insert(cards_list, card)
  end
  table.sort(cards_list, function(a, b) return a.id < b.id end)

  local save = { cards = cards_list, config = _data.config or {} }
  local json = vim.json.encode(save)
  vim.fn.writefile({ json }, path)
end

--- 从 workspace 初始化/同步卡片
--- 扫描 workspace 中的题目文件，为没有卡片记录的题目创建新卡片
---@return number new_count 新增卡片数
function M.init_from_workspace()
  local data = M.load_data()
  local local_files = file.scan_workspace()
  local new_count = 0

  for _, f in ipairs(local_files) do
    if f.id and not data.cards[f.id] then
      data.cards[f.id] = fsrs.new_card(f.id)
      new_count = new_count + 1
    end
  end

  if new_count > 0 then
    M.save_data()
  end
  return new_count
end

--- 获取到期卡片列表
---@param date_str? string "YYYY-MM-DD"，默认今天
---@return table[] due_cards
function M.get_due_cards(date_str)
  date_str = date_str or os.date("%Y-%m-%d")
  local data = M.load_data()
  local due = {}
  for _, card in pairs(data.cards) do
    if fsrs.is_due(card, date_str) then
      table.insert(due, card)
    end
  end
  table.sort(due, function(a, b) return a.id < b.id end)
  return due
end

--- 对卡片评分
---@param id number 题目 ID
---@param rating number 1=Again, 2=Hard, 3=Good, 4=Easy
function M.rate_card(id, rating)
  if rating < 1 or rating > 4 then
    vim.notify("LeetCode: 评分必须为 1-4 (Again/Hard/Good/Easy)", vim.log.levels.WARN)
    return
  end

  local data = M.load_data()
  local card = data.cards[id]
  if not card then
    -- 自动创建卡片
    card = fsrs.new_card(id)
  end

  local scheduler = fsrs.new(data.config)
  local new_card = scheduler.schedule(card, rating)
  data.cards[id] = new_card
  M.save_data()

  local rating_names = { "Again", "Hard", "Good", "Easy" }
  vim.notify(string.format(
    "LeetCode: #%d 评分 %s → 下次复习 %s (间隔 %d 天)",
    id, rating_names[rating], new_card.due, new_card.scheduled_days
  ), vim.log.levels.INFO)
end

--- 从当前文件获取题目 ID
---@return number|nil
local function current_problem_id()
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then return nil end
  local meta = file.parse_metadata(filepath)
  if meta then return meta.id end
  local id = file.parse_id_from_filename(filepath)
  return id
end

--- 对当前题目评分
---@param rating number
function M.rate_current(rating)
  local id = current_problem_id()
  if not id then
    vim.notify("LeetCode: 当前文件不是 LeetCode 题目", vim.log.levels.WARN)
    return
  end
  M.rate_card(id, rating)
end

--- 显示今日待复习列表
function M.show_review_list()
  M.init_from_workspace() -- 先同步

  local due_cards = M.get_due_cards()
  if #due_cards == 0 then
    vim.notify("LeetCode: 今日没有需要复习的题目 🎉", vim.log.levels.INFO)
    return
  end

  -- 获取题目列表用于显示标题
  local api = require("leetcode-compat.api")
  api.fetch_problems_cached(function(err, problems)
    local title_map = {}
    if not err and problems then
      for _, p in ipairs(problems) do
        title_map[p.id] = p
      end
    end

    -- 构建显示条目
    local state_names = { [0] = "New", [1] = "Learning", [2] = "Review", [3] = "Relearning" }
    local entries = {}
    local card_by_line = {}
    for _, card in ipairs(due_cards) do
      local p = title_map[card.id]
      local title = p and p.title or "Unknown"
      local diff = p and p.difficulty or "?"
      local state = state_names[card.state] or "?"
      local entry = string.format("%4d | %-6s | %-10s | reps:%-2d | %s", card.id, diff, state, card.reps or 0, title)
      table.insert(entries, entry)
      card_by_line[entry] = card
    end

    local ok, fzf = pcall(require, "fzf-lua")
    if not ok then
      vim.ui.select(entries, { prompt = "LeetCode Review:" }, function(choice)
        if not choice then return end
        local card = card_by_line[choice]
        if card then
          require("leetcode-compat.ui.picker").open_by_id(card.id)
        end
      end)
      return
    end

    fzf.fzf_exec(entries, {
      prompt = "LeetCode Review> ",
      winopts = {
        height = 0.8,
        width = 0.8,
        preview = { hidden = "hidden" },
      },
      fzf_opts = {
        ["--header"] = string.format("今日待复习: %d 题 | enter: 打开 | ctrl-1/2/3/4: Again/Hard/Good/Easy", #due_cards),
      },
      actions = {
        ["default"] = function(selected)
          if not selected or #selected == 0 then return end
          local card = card_by_line[selected[1]]
          if card then
            require("leetcode-compat.ui.picker").open_by_id(card.id)
          end
        end,
        ["ctrl-1"] = function(selected)
          if not selected or #selected == 0 then return end
          local card = card_by_line[selected[1]]
          if card then M.rate_card(card.id, fsrs.Again) end
        end,
        ["ctrl-2"] = function(selected)
          if not selected or #selected == 0 then return end
          local card = card_by_line[selected[1]]
          if card then M.rate_card(card.id, fsrs.Hard) end
        end,
        ["ctrl-3"] = function(selected)
          if not selected or #selected == 0 then return end
          local card = card_by_line[selected[1]]
          if card then M.rate_card(card.id, fsrs.Good) end
        end,
        ["ctrl-4"] = function(selected)
          if not selected or #selected == 0 then return end
          local card = card_by_line[selected[1]]
          if card then M.rate_card(card.id, fsrs.Easy) end
        end,
      },
    })
  end)
end

--- 显示复习统计
function M.show_stats()
  M.init_from_workspace()
  local data = M.load_data()

  local total = 0
  local by_state = { [0] = 0, [1] = 0, [2] = 0, [3] = 0 }
  local due_today = 0
  local today = os.date("%Y-%m-%d")

  for _, card in pairs(data.cards) do
    total = total + 1
    by_state[card.state] = (by_state[card.state] or 0) + 1
    if fsrs.is_due(card, today) then
      due_today = due_today + 1
    end
  end

  local lines = {
    "LeetCode 间隔重复统计",
    "═══════════════════════",
    string.format("总卡片数:   %d", total),
    string.format("今日待复习: %d", due_today),
    "",
    "按状态分布:",
    string.format("  New:        %d", by_state[0]),
    string.format("  Learning:   %d", by_state[1]),
    string.format("  Review:     %d", by_state[2]),
    string.format("  Relearning: %d", by_state[3]),
  }

  -- 浮动窗口显示
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local width = 30
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
  })
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf })
end

return M
