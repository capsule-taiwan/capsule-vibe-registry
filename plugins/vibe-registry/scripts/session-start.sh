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
2. 問使用者「本人」的公司 email（登記專案時標示負責人用）。
   **注意：全公司共用同一個 Claude 帳號，登入帳號信箱（it-2@capsulecorporation.cc）不是使用者本人的信箱**——
   禁止從 ~/.claude.json、git config 或任何檔案推斷，一定要開口問本人；
   若對方回答 it-2@...，說明那是共用帳號，請改提供個人的公司信箱（通常是 名.姓@capsulecorporation.cc）。
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

# 本資料夾（或其上層）是否已綁定某個登記專案（add/join 成功時由 registry.sh 記錄）
BOUND_NOTE=""
DIRMAP="$HOME/.claude/vibe-registry-dirs"
if [ -f "$DIRMAP" ]; then
  best=""
  while IFS=$'\t' read -r p bid btitle; do
    [ -n "$p" ] || continue
    case "$PWD" in
      "$p" | "$p"/*)
        if [ "${#p}" -gt "${#best}" ]; then
          best="$p"
          BOUND_NOTE="◆ 本資料夾已綁定登記專案：${btitle}（id: ${bid}）——進度更新/收尾直接用這個 id，不用查找；查重時注意這是使用者自己的專案。"
        fi ;;
    esac
  done < "$DIRMAP"
fi

cat <<EOF
<vibe-registry>
以下是公司 vibe coding 專案登記表的進行中項目（CSV，最近更新在前）：

$ROWS

$BOUND_NOTE

登記表使用規則（對 Claude 的指示）：
1. 使用者要開始開發新東西時查重：先跑 bash "$DIR/registry.sh" list --all 取即時全表（含已完成——有人做完的東西可直接沿用，是最該攔下的重工；上表只是開場的進行中快照）再比對；命中時主動告知使用者（誰、在做什麼/做完了什麼、最後更新時間），請使用者決定沿用、加入（join）或繼續新開。
2. 查重命中且使用者表示「就是同一個專案 / 我是跟他一起做的」時，不要重複登記，改加入成員：
   bash "$DIR/registry.sh" join <id>
3. 確定是新專案（不是問問題、不是小修改）時，**先問使用者是否要登記**（說明內容全公司可見；可選籠統標題保留隱私；拒絕就尊重且本 session 不再提），同意後執行：
   bash "$DIR/registry.sh" add "專案名稱" "一句話描述"
4. 對登記項目達成里程碑（完成功能/commit/部署/修完 bug）的**當下**就更新，別等收尾（session 結束時機你觀察不到，等收尾=永遠不會發生）：
   bash "$DIR/registry.sh" update <id> "進度摘要"
5. session 中看到部署成功的 URL、或使用者說「上線了」給了網址，當下記錄（查重命中已完成且有 url 的專案時，直接把網址給使用者沿用）：
   bash "$DIR/registry.sh" link <id> "https://..."
6. 專案完成或暫停時：
   bash "$DIR/registry.sh" status <id> done|paused|active
7. 查看完整清單（含已完成）：bash "$DIR/registry.sh" list --all
詳細工作流見 project-registry skill。
</vibe-registry>
EOF
exit 0
