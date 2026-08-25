#!/usr/bin/env bash
# vibe-registry 一鍵安裝腳本：裝 plugin + 當場完成設定
# 用法（貼到終端機執行；token 可作為第一個參數直接帶入，email 可作為第二個參數）：
#   bash <(curl -fsSL https://raw.githubusercontent.com/capsule-taiwan/capsule-vibe-registry/master/install.sh) <token> [email]
# 不帶參數則互動式詢問。
set -euo pipefail

REPO="capsule-taiwan/capsule-vibe-registry"
REGISTRY_URL="https://rgdhqguwspcnpmuyrytp.supabase.co"
CONF="$HOME/.claude/vibe-registry.env"

TOKEN_ARG="${1:-}"
EMAIL_ARG="${2:-}"

if ! command -v claude >/dev/null 2>&1; then
  echo "找不到 claude 指令。請先安裝 Claude Code：https://claude.com/claude-code" >&2
  exit 1
fi

echo "==> 加入 capsule-vibe marketplace..."
claude plugin marketplace add "$REPO" 2>/dev/null || claude plugin marketplace update capsule-vibe

echo "==> 安裝 vibe-registry plugin..."
claude plugin install vibe-registry@capsule-vibe

# ── 設定：參數 > 既有設定 > 互動詢問 ──
TOKEN="$TOKEN_ARG"
EMAIL="$EMAIL_ARG"
if [ -f "$CONF" ]; then
  # shellcheck source=/dev/null
  source "$CONF" 2>/dev/null || true
  [ -n "$TOKEN" ] || TOKEN="${REGISTRY_TOKEN:-}"
  [ -n "$EMAIL" ] || EMAIL="${OWNER_EMAIL:-}"
fi
if [ -r /dev/tty ]; then
  while [ -z "$TOKEN" ]; do
    printf "請貼上登記表 token（Slack #vibe-coding 置頂訊息裡有）: "
    read -r TOKEN < /dev/tty
  done
  while ! printf '%s' "$EMAIL" | grep -q "@"; do
    printf "請輸入你的公司 email（例 amy.chen@capsulecorporation.cc）: "
    read -r EMAIL < /dev/tty
  done
fi

if [ -z "$TOKEN" ]; then
  echo "==> （沒有 token 也無法互動詢問：開新 Claude session 時 Claude 會引導完成設定）"
else
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
    echo " 失敗（token 可能貼錯或離線）。可重跑本腳本，或開 Claude session 讓 Claude 引導。" >&2
  fi
  if ! printf '%s' "$EMAIL" | grep -q "@"; then
    echo "==> 提醒：尚未設定 email，之後開 Claude session 時告訴 Claude 你的公司信箱即可補上。"
  fi
fi

cat <<'MSG'

✅ 安裝完成！重開 Claude Code（已開著的視窗先關掉）即全自動生效。
   之後在 Claude 裡輸入 /registry 可隨時查看全公司進行中的專案。
MSG
