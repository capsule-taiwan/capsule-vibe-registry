#!/usr/bin/env bash
# vibe-registry CLI：list / add / join / update / status
# 由 Claude（或人）在 session 中呼叫；後端是 Supabase Edge Function `vibe-registry`
# （唯一閘道；客戶端只持有函式 token，沒有任何資料庫憑證）。
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_CONFIG="$HOME/.claude/vibe-registry.env"

# 設定優先序：
# 1. hook 環境變數（未來 userConfig 用，現版 Claude Code 不會有）
# 2. 腳本目錄 config.env（開發 repo / IT 手動放置）
# 3. ~/.claude/vibe-registry.env（對話式引導產生；放 home 是為了不隨 plugin 版本更新消失）
REGISTRY_URL="${CLAUDE_PLUGIN_OPTION_REGISTRY_URL:-}"
REGISTRY_TOKEN="${CLAUDE_PLUGIN_OPTION_REGISTRY_TOKEN:-}"
OWNER_EMAIL="${CLAUDE_PLUGIN_OPTION_OWNER_EMAIL:-}"
if [ -z "$REGISTRY_URL" ]; then
  if [ -f "$DIR/config.env" ]; then
    # shellcheck source=/dev/null
    source "$DIR/config.env"
  elif [ -f "$HOME_CONFIG" ]; then
    # shellcheck source=/dev/null
    source "$HOME_CONFIG"
  fi
fi
# URL 非秘密，預設寫死；設定檔有填則覆蓋（換 Supabase 專案時用）
REGISTRY_URL="${REGISTRY_URL:-https://rgdhqguwspcnpmuyrytp.supabase.co}"
if [ -z "${REGISTRY_TOKEN:-}" ]; then
  echo "錯誤：尚未設定登記表連線。請依 Slack #vibe-coding 置頂訊息取得 token 完成設定（Claude 可引導：把 token/email 寫入 ~/.claude/vibe-registry.env）。" >&2
  exit 1
fi

FN="$REGISTRY_URL/functions/v1/vibe-registry"

# 資料夾 ↔ 專案對照表（TSV: 路徑<TAB>id<TAB>名稱）。add/join 成功時記錄目前
# 工作目錄，之後 hook 開場即可注入「本資料夾屬於專案 X」，update 不用再找 id。
DIRMAP="$HOME/.claude/vibe-registry-dirs"
record_dir() { # $1=id $2=title
  [ -n "$1" ] || return 0
  { grep -v "^$PWD	" "$DIRMAP" 2>/dev/null || true; } > "$DIRMAP.tmp"
  printf '%s\t%s\t%s\n' "$PWD" "$1" "$2" >> "$DIRMAP.tmp"
  mv "$DIRMAP.tmp" "$DIRMAP"
}

# 身份優先序：設定檔 email > 本機 git 設定 > 系統帳號 fallback
owner_email() {
  if [ -n "${OWNER_EMAIL:-}" ]; then
    echo "$OWNER_EMAIL"
  else
    git config user.email 2>/dev/null || echo "${USER:-unknown}@unknown"
  fi
}

# 把任意字串做成合法 JSON 字串內容（處理反斜線、雙引號、換行）
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed -e 's/\\n$//'
}

# 呼叫閘道：非 200 時把伺服器訊息丟到 stderr 並以非零退出
call() {
  local out http body
  out="$(curl -s --max-time 12 -w $'\n%{http_code}' -X POST \
    -H "x-registry-token: $REGISTRY_TOKEN" -H "Content-Type: application/json" \
    --data "$1" "$FN")" || { echo "錯誤：連不上登記表（離線或服務異常），稍後再試" >&2; exit 1; }
  http="${out##*$'\n'}"
  body="${out%$'\n'*}"
  if [ "$http" != "200" ]; then
    echo "錯誤（${http}）：${body}" >&2
    exit 1
  fi
  printf '%s\n' "$body"
}

cmd="${1:-}"
case "$cmd" in
  list)
    if [ "${2:-}" = "--all" ]; then
      call '{"action":"list","all":true}'
    else
      call '{"action":"list"}'
    fi
    ;;
  add)
    title="${2:?用法: registry.sh add \"專案名稱\" \"一句話描述\"}"
    desc="${3:-}"
    resp="$(call "{\"action\":\"add\",\"title\":\"$(json_escape "$title")\",\"description\":\"$(json_escape "$desc")\",\"owner\":\"$(json_escape "$(owner_email)")\"}")"
    printf '%s\n' "$resp"
    record_dir "$(printf '%s' "$resp" | sed -n 's/.*id: \([0-9a-f-]*\)).*/\1/p')" "$title"
    ;;
  join)
    id="${2:?用法: registry.sh join <id>}"
    resp="$(call "{\"action\":\"join\",\"id\":\"$(json_escape "$id")\",\"me\":\"$(json_escape "$(owner_email)")\"}")"
    printf '%s\n' "$resp"
    case "$resp" in 已加入專案*) record_dir "$id" "$(printf '%s' "$resp" | sed -n 's/.*「\(.*\)」.*/\1/p')";; esac
    ;;
  link)
    id="${2:?用法: registry.sh link <id> <上線app網址|--clear>}"
    url="${3:?用法: registry.sh link <id> <上線app網址|--clear>}"
    [ "$url" = "--clear" ] && url=""
    call "{\"action\":\"link\",\"id\":\"$(json_escape "$id")\",\"url\":\"$(json_escape "$url")\"}"
    ;;
  update)
    id="${2:?用法: registry.sh update <id> \"進度摘要\"}"
    note="${3:?用法: registry.sh update <id> \"進度摘要\"}"
    call "{\"action\":\"update\",\"id\":\"$(json_escape "$id")\",\"note\":\"$(json_escape "$note")\"}"
    ;;
  status)
    id="${2:?用法: registry.sh status <id> active|paused|done}"
    st="${3:?用法: registry.sh status <id> active|paused|done}"
    call "{\"action\":\"status\",\"id\":\"$(json_escape "$id")\",\"status\":\"$(json_escape "$st")\",\"me\":\"$(json_escape "$(owner_email)")\"}"
    ;;
  *)
    cat >&2 <<'USAGE'
用法:
  registry.sh list [--all]                 列出進行中（--all 含已完成）
  registry.sh add "專案名稱" "一句話描述"    登記新專案（owner 自動取設定的 email）
  registry.sh join <id>                    加入既有專案成為成員
  registry.sh update <id> "進度摘要"        更新進度
  registry.sh link <id> <部署網址>          記錄成品/部署網址
  registry.sh status <id> active|paused|done
USAGE
    exit 1
    ;;
esac
