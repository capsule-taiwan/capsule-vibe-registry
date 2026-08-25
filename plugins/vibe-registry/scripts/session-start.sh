#!/usr/bin/env bash
# SessionStart hook：抓進行中專案清單，以純文字 stdout 注入 session context。
# 任何失敗（離線 / API 掛掉）都靜默退出，不能擋使用者開 session。
#
# 後端是 Edge Function 閘道（客戶端只持有函式 token，無資料庫憑證）。
# 設定優先序（與 registry.sh 一致）：
# 1.（未來版本）plugin userConfig → CLAUDE_PLUGIN_OPTION_* 環境變數，偵測到就落地。
#    目前團隊用的 2.1.x 不支援 userConfig，此路徑備而不用。
# 2. 腳本目錄 config.env（開發 repo / IT 手動放置）
# 3. ~/.claude/vibe-registry.env（對話式引導產生；放 home 是為了不隨 plugin 版本更新消失）
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_CONFIG="$HOME/.claude/vibe-registry.env"

if [ -n "${CLAUDE_PLUGIN_OPTION_REGISTRY_URL:-}" ] && [ -n "${CLAUDE_PLUGIN_OPTION_REGISTRY_TOKEN:-}" ]; then
  umask 077
  cat > "$HOME_CONFIG" <<EOF
# 本檔由 vibe-registry plugin 依 userConfig 自動產生，手動修改會被覆寫。
REGISTRY_URL="${CLAUDE_PLUGIN_OPTION_REGISTRY_URL}"
REGISTRY_TOKEN="${CLAUDE_PLUGIN_OPTION_REGISTRY_TOKEN}"
OWNER_EMAIL="${CLAUDE_PLUGIN_OPTION_OWNER_EMAIL:-}"
EOF
  chmod 600 "$HOME_CONFIG"
fi

REGISTRY_URL=""
REGISTRY_TOKEN=""
if [ -f "$DIR/config.env" ]; then
  # shellcheck source=/dev/null
  source "$DIR/config.env"
elif [ -f "$HOME_CONFIG" ]; then
  # shellcheck source=/dev/null
  source "$HOME_CONFIG"
fi

# URL 非秘密，預設寫死；設定檔有填則覆蓋（換 Supabase 專案時用）
REGISTRY_URL="${REGISTRY_URL:-https://rgdhqguwspcnpmuyrytp.supabase.co}"

# 尚未設定 → 注入「引導設定」指示，讓 Claude 在對話中完成一次性設定
if [ -z "${REGISTRY_TOKEN:-}" ]; then
  cat <<EOF
<vibe-registry>
vibe-registry plugin（公司 vibe coding 專案登記表）已安裝但尚未設定。
請在本 session 開頭先花一分鐘引導使用者完成一次性設定（若使用者正忙別的事，等段落結束再提）：
1. 請使用者打開 Slack #vibe-coding 頻道的置頂訊息，把「登記表 token」貼過來。
2. 問使用者的公司 email（登記專案時標示負責人用）。
3. 將設定寫入 \$HOME/.claude/vibe-registry.env（寫完 chmod 600），內容格式：
REGISTRY_TOKEN="貼上的 token"
OWNER_EMAIL="使用者的公司 email"
4. 執行 bash "$DIR/registry.sh" list 驗證連線；成功後告知使用者：設定完成，之後開任何 session 都自動生效，不用再管。
</vibe-registry>
EOF
  exit 0
fi

ROWS="$(curl -sf --max-time 8 -X POST \
  -H "x-registry-token: $REGISTRY_TOKEN" -H "Content-Type: application/json" \
  --data '{"action":"list"}' \
  "$REGISTRY_URL/functions/v1/vibe-registry")" || exit 0

cat <<EOF
<vibe-registry>
以下是公司 vibe coding 專案登記表的進行中項目（CSV，最近更新在前）：

$ROWS

登記表使用規則（對 Claude 的指示）：
1. 使用者要開始開發新東西時查重：先跑 bash "$DIR/registry.sh" list --all 取即時全表（含已完成——有人做完的東西可直接沿用，是最該攔下的重工；上表只是開場的進行中快照）再比對；命中時主動告知使用者（誰、在做什麼/做完了什麼、最後更新時間），請使用者決定沿用、加入（join）或繼續新開。
2. 查重命中且使用者表示「就是同一個專案 / 我是跟他一起做的」時，不要重複登記，改加入成員：
   bash "$DIR/registry.sh" join <id>
3. 確定是新專案（不是問問題、不是小修改）時，幫使用者登記：
   bash "$DIR/registry.sh" add "專案名稱" "一句話描述"
4. 本次 session 對某登記項目有實質進度時（發起人或成員皆可），收尾前更新：
   bash "$DIR/registry.sh" update <id> "進度摘要"
5. 專案完成或暫停時：
   bash "$DIR/registry.sh" status <id> done|paused|active
6. 查看完整清單（含已完成）：bash "$DIR/registry.sh" list --all
詳細工作流見 project-registry skill。
</vibe-registry>
EOF
exit 0
