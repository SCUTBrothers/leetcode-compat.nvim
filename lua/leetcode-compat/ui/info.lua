local M = {}

local file = require("leetcode-compat.file")

--- 在 floating window 中显示当前题目信息
function M.show()
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then
    vim.notify("LeetCode: 当前 buffer 不是文件", vim.log.levels.WARN)
    return
  end

  local meta = file.parse_metadata(filepath)
  if not meta then
    vim.notify("LeetCode: 无法解析文件元数据（需要 @lc 标记）", vim.log.levels.WARN)
    return
  end

  local lines = {
    " LeetCode 题目信息",
    "",
    "  题号:  #" .. meta.id,
  }

  if meta.title then
    table.insert(lines, "  标题:  " .. meta.title)
  end

  table.insert(lines, "  语言:  " .. (meta.lang or "unknown"))

  if meta.app then
    table.insert(lines, "  站点:  " .. meta.app)
  end

  table.insert(lines, "  文件:  " .. vim.fn.fnamemodify(filepath, ":~"))
  table.insert(lines, "")

  -- 计算窗口大小
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = width + 4
  local height = #lines

  -- 创建 buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"

  -- 打开居中的 floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Info ",
    title_pos = "center",
  })

  -- 按 q 或 Esc 关闭
  local function close_win()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q", close_win, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close_win, { buffer = buf, nowait = true })

  -- 失去焦点时自动关闭
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = close_win,
  })
end

return M
