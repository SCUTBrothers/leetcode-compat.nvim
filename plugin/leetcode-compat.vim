" leetcode-compat.nvim - 兼容 VSCode LeetCode 插件格式的 Neovim LeetCode 工具
" 此文件仅作为 Lua 模块的 bridge，实际逻辑在 lua/leetcode-compat/ 中

if exists('g:loaded_leetcode_compat')
  finish
endif
let g:loaded_leetcode_compat = 1
