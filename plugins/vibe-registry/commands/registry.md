---
description: 查看公司 vibe coding 專案登記表
---

執行 `bash "${CLAUDE_PLUGIN_ROOT}/scripts/registry.sh" list`（使用者加了 `--all` 就帶上），把回傳的 CSV 整理成好讀的表格呈現：專案名稱、負責人、成員、狀態、最新進度、最後更新時間。依最後更新時間排序，超過 14 天沒動的標註「可能已停滯」。id 欄不用完整顯示，取前 8 碼即可。

$ARGUMENTS
