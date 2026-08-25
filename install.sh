#!/usr/bin/env bash
# vibe-registry 一鍵安裝腳本：裝 plugin + 當場完成設定
# 用法（貼到終端機執行）：
#   bash <(curl -fsSL https://raw.githubusercontent.com/capsule-taiwan/capsule-vibe-registry/master/install.sh)
set -euo pipefail

REPO="capsule-taiwan/capsule-vibe-registry"
REGISTRY_URL="https://rgdhqguwspcnpmuyrytp.supabase.co"
CONF="$HOME/.claude/vibe-registry.env"

if ! command -v claude >/dev/null 2>&1; then
  echo "找不到 claude 指令。請先安裝 Claude Code：https://claude.com/claude-code" >&2
  exit 1
fi

echo "==> 加入 capsule-vibe marketplace..."
claude plugin marketplace add "$REPO" 2>/dev/null || claude plugin marketplace update capsule-vibe

echo "==> 安裝 vibe-registry plugin..."
claude plugin install vibe-registry@capsule-vibe

# ── 當場完成設定（省掉「重開 session 再讓 Claude 引導」的斷點）──
if [ -f "$CONF" ] && grep -q 'REGISTRY_TOKEN=".' "$CONF"; then
  echo "==> 已有設定（${CONF}），保留不動。要重設：刪除該檔後重跑本腳本。"
elif [ -r /dev/tty ]; then
  echo ""
  echo "==> 最後兩個問題（資料在 Slack #vibe-coding 頻道的置頂訊息裡）："
  TOKEN=""
  while [ -z "$TOKEN" ]; do
    printf "  1) 貼上登記表 token: "
    read -r TOKEN < /dev/tty
  done
  EMAIL=""
  while ! printf '%s' "$EMAIL" | grep -q "@"; do
    printf "  2) 你的公司 email（例 amy.chen@capsulecorporation.cc）: "
    read -r EMAIL < /dev/tty
  done
  umask 077
  printf 'REGISTRY_TOKEN="%s"\nOWNER_EMAIL="%s"\n' "$TOKEN" "$EMAIL" > "$CONF"
  chmod 600 "$CONF"
  printf "==> 驗證連線..."
  HTTP="$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 -X POST \
    -H "x-registry-token: $TOKEN" -H "Content-Type: application/json" \
    --data '{"action":"list"}' "$REGISTRY_URL/functions/v1/vibe-registry" || echo 000)"
  if [ "$HTTP" = "200" ]; then
    echo " OK ✅"
  else
    echo " 失敗（token 可能貼錯或離線）。稍後可刪除 $CONF 重跑本腳本，或開 Claude session 讓 Claude 引導。" >&2
  fi
else
  echo "==> （非互動環境，略過設定：開新 session 時 Claude 會引導完成）"
fi

cat <<'MSG'

✅ 安裝完成！重開 Claude Code（已開著的視窗先關掉）即全自動生效。
   之後在 Claude 裡輸入 /registry 可隨時查看全公司進行中的專案。
MSG
