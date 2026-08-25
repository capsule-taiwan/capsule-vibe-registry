#!/usr/bin/env bash
# vibe-registry 一鍵安裝腳本
# 用法（貼到終端機執行）：
#   bash <(curl -fsSL https://raw.githubusercontent.com/capsule-taiwan/capsule-vibe-registry/master/install.sh)
set -euo pipefail

REPO="capsule-taiwan/capsule-vibe-registry"

if ! command -v claude >/dev/null 2>&1; then
  echo "找不到 claude 指令。請先安裝 Claude Code：https://claude.com/claude-code" >&2
  exit 1
fi

echo "==> 加入 capsule-vibe marketplace..."
claude plugin marketplace add "$REPO" 2>/dev/null || claude plugin marketplace update capsule-vibe

echo "==> 安裝 vibe-registry plugin..."
claude plugin install vibe-registry@capsule-vibe

cat <<'MSG'

✅ 安裝完成！

下一步：開一個新的 Claude Code session（已開著的要先關掉重開），
Claude 會自動引導你完成一次性設定（需要 Slack #vibe-coding 置頂訊息裡的資訊）。
MSG
