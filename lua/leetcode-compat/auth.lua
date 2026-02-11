local M = {}

local config = require("leetcode-compat.config")

--- 从文件读取 cookie
function M.get_cookie()
  local path = config.options.cookie_path
  if vim.fn.filereadable(path) == 1 then
    local lines = vim.fn.readfile(path)
    if #lines > 0 then
      return lines[1]
    end
  end
  return nil
end

--- 保存 cookie 到文件
function M.save_cookie(cookie)
  local path = config.options.cookie_path
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ cookie }, path)
end

--- 提示用户输入 cookie
function M.prompt_cookie()
  vim.ui.input({
    prompt = "LeetCode Cookie (LEETCODE_SESSION=xxx; csrftoken=xxx): ",
  }, function(input)
    if input and input ~= "" then
      M.save_cookie(input)
      -- 验证 cookie
      local api = require("leetcode-compat.api")
      api.check_auth(function(ok, username)
        if ok then
          vim.notify("LeetCode: 已登录为 " .. username, vim.log.levels.INFO)
        else
          vim.notify("LeetCode: Cookie 无效，请重新设置", vim.log.levels.ERROR)
        end
      end)
    end
  end)
end

--- 从 cookie 字符串中提取 csrftoken
function M.get_csrf()
  local cookie = M.get_cookie()
  if not cookie then return nil end
  return cookie:match("csrftoken=([^;]+)")
end

--- 检查是否已认证
function M.is_authenticated()
  return M.get_cookie() ~= nil
end

return M
