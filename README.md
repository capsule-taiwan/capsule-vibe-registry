# capsule-vibe-registry

公司 vibe coding 專案登記系統。這個 repo 同時是 Claude Code plugin marketplace 和 plugin 本體。**Repo 為 public，內含零秘密**——使用者持有的憑證是一個只對登記閘道（Edge Function）有效的 token，由安裝後 Claude 對話式引導填入（向 IT 索取）。

**解決的問題**：大家用 Claude 各自開發，互相不知道誰在做什麼 → 重工、無法追蹤。

**機制**：
- 每次開 Claude Code session，SessionStart hook 自動抓中央登記表的進行中項目注入 context → **Claude 幫每個人查重**，開新工作時主動提醒「某某已在做類似的事 / 已經做完可沿用」
- `project-registry` skill 讓 Claude 在使用者開新專案時**徵求同意後**登記（可選籠統標題保留隱私、可拒絕）、協作時 join、有進度時更新、完成時收尾
- 登記 / 加入 / 完成時由伺服器端發 Slack 通知 → 管理者與全員在 Slack 就看得到動態
- `/registry` 指令隨時看全表

## 架構與安全模型

```
使用者機器（plugin）
  └─ registry.sh ──(REGISTRY_TOKEN)──> Edge Function vibe-registry（唯一閘道）
                                          ├─ 驗 token、驗欄位、限定動作（list/add/join/update/status）
                                          ├─ service_role 寫 vibe_projects（RLS 零政策，anon 完全進不來）
                                          └─ Slack webhook 通知（webhook URL 只存在伺服器端 secret）
```

- **使用者手上沒有任何資料庫憑證**：`REGISTRY_TOKEN` 只能呼叫這支函式的五個動作，動不了專案裡任何表（DB 內含其他資料，這點是硬要求）。
- token 外洩的最壞情況＝亂登記幾筆假資料（都有留痕），rotate：`supabase secrets set REGISTRY_TOKEN=新值` + 更新 Slack 置頂。
- 仍未解的：身份冒用（呼叫者自稱誰就是誰）。要解需 Supabase Auth 每人真帳號，現階段刻意不做（摩擦換信任）。

## 目錄結構

```
.claude-plugin/marketplace.json          marketplace 定義
install.sh                               使用者一鍵安裝腳本
supabase/registry.sql                    登記表 schema + RLS 鎖定（SQL Editor 執行）
supabase/functions/vibe-registry/index.ts  Edge Function 閘道（唯一存取路徑）
plugins/vibe-registry/
  .claude-plugin/plugin.json             plugin manifest
  hooks/hooks.json                       SessionStart hook 註冊
  scripts/config.env.example             設定格式參考
  scripts/session-start.sh               開 session 抓清單注入 context / 未設定時注入引導指示
  scripts/registry.sh                    list / add / join / update / status CLI
  skills/project-registry/SKILL.md       登記工作流（Claude 自動觸發）
  commands/registry.md                   /registry 斜線指令
```

## 設定怎麼流動（重要）

設定存在 `~/.claude/vibe-registry.env`（chmod 600，內容：REGISTRY_URL / REGISTRY_TOKEN / OWNER_EMAIL）——**放 home 而不是安裝目錄**，因為安裝目錄帶版本號（`cache/capsule-vibe/vibe-registry/<版本>/`），plugin 更新換目錄設定就丟了。產生方式是**對話式引導**：安裝後第一次開 session，hook 偵測到未設定，會注入指示讓 Claude 引導使用者——從 Slack 置頂貼上 token、問到 email，Claude 自己寫好設定檔並跑 `list` 驗證。全程使用者只需要複製貼上。（開發時可在 repo 的 `scripts/config.env` 放一份，優先於 home 設定。）

> 為什麼不用 plugin 的 `userConfig` 設定機制：團隊現用的 Claude Code 2.1.x 的 manifest 驗證不認識該欄位，含有它會**整個拒裝**。腳本內保留了 `CLAUDE_PLUGIN_OPTION_*` 的讀取路徑，等全員版本跟上再把 `userConfig` 加回 manifest 即可無痛切換。

## 管理者設定（一次性）

1. 在 Supabase 專案的 SQL Editor 執行 `supabase/registry.sql`（冪等，重跑安全；會把表鎖成「僅 Edge Function 可存取」）
2. **部署閘道**（repo 目錄內，需 `supabase login`）：
   ```
   npx supabase functions deploy vibe-registry --project-ref <ref> --no-verify-jwt
   ```
3. **設 secrets**：
   ```
   npx supabase secrets set REGISTRY_TOKEN=$(openssl rand -hex 24) --project-ref <ref>
   npx supabase secrets set SLACK_WEBHOOK_URL=<webhook>   --project-ref <ref>   # 選配
   ```
4. （選配）開 `#vibe-coding` 頻道 + incoming webhook（給上一步的 SLACK_WEBHOOK_URL）
5. 在 `#vibe-coding` 發**置頂訊息**：REGISTRY_TOKEN + 一鍵安裝指令（下方）。URL 非秘密且已內建在腳本預設值，不用發
6. 本地先測（見「本地測試」）後，推到公司 GitHub **public repo**

## 使用者安裝（每人一次，不需要 GitHub 帳號）

> Plugin 安裝狀態存在每台電腦本機的 `~/.claude/`，**不跟著 Claude 帳號走**（共用帳號也一樣要各機安裝）。

最簡單：終端機貼一行（Slack 置頂有現成的）：

```
bash <(curl -fsSL https://raw.githubusercontent.com/capsule-taiwan/capsule-vibe-registry/master/install.sh)
```

或在 Claude Code 內手動執行：

```
/plugin marketplace add capsule-taiwan/capsule-vibe-registry
/plugin install vibe-registry@capsule-vibe
```

裝完**重開一次 session**，Claude 會主動引導設定：請你從 `#vibe-coding` 置頂訊息貼上 token、問你的公司 email（登記時標示負責人用；不依賴 git/GitHub，沒有帳號也沒關係），然後自動寫好設定並驗證。從此不需再做任何事。

要改設定：直接跟 Claude 說「幫我改 vibe-registry 的設定」即可。

Marketplace 支援自動更新（`/plugin` → Marketplaces → auto-update），之後改 skill 措辭、調整規則，推上 repo 大家就會收到；設定存在各自本機的 home，更新不會被動到。

## 本地測試

```
/plugin marketplace add /path/to/capsule-vibe-registry
/plugin install vibe-registry@capsule-vibe
```

重開 session，應看到 Claude 知道登記表內容。測完整流程：

1. 跟 Claude 說「我要做一個報價單產生器」→ 應該查重後自動 `add` 並回報
2. 另開 session 說「我想做一個報價工具」→ 應該提醒已有人在做
3. `/registry` → 應列出表格
4. 說「報價單產生器做完了」→ 應 `status done` + Slack 通知

（開發時可複製 `config.env.example` 為 `config.env` 直接填值，跳過對話式設定。）

## 安全與已知限制

- **寫入路徑唯一**：所有讀寫走 Edge Function；`vibe_projects` 的 RLS 啟用且零政策，anon/authenticated 直連一律被拒。改函式邏輯後要重新 deploy 才生效。
- **token 不驗身份**：拿到 token 的人可以用任何 email 自稱任何人（登記表信任模型）。要真身份需上 Supabase Auth，屬於未來升級。
- **repo 是 public**：程式碼與機制公開（無實害），但**任何秘密都不可 commit**——config.env 已 gitignore，token/webhook 只存在 Supabase secrets 與 Slack 置頂，PR 審查時留意。
- **只在公司 Claude 帳號下運作**：hook 會讀本機登入帳號的 email（`~/.claude.json`），非 `@capsulecorporation.cc` 網域（例如個人帳號）靜默不動作。這是行為範圍控制、非安全機制（讀不到 email 時放行，避免 Claude Code 改版後功能無聲消失）。
- **登記靠 Claude 自覺**（skill 引導，非強制）：使用者堅持不登記擋不住。底線的「強制」需要 MDM 推 managed settings，目前沒有。實務上 SessionStart 注入 + skill 引導的完成率已遠高於「請大家自己去填表」。
- **停滯偵測**：`registry.sql` 尾端有 pg_cron 選配，14 天沒更新自動標 `stale`，`/registry` 會標註。
- **重工的另一半**：登記表只能提醒「有人在做」，看不到彼此的程式碼。有價值的產出還是要收編進正式 repo，那是下一階段的事。

## 之後可以長的方向

- 登記表 dashboard 網頁（Supabase 直接出，或掛進 CRM 管理後台）
- Slack 每週摘要（cron 掃表發週報：新增/完成/停滯）
- 收編流程：done 的專案引導交接給工程師進正式 repo
- Supabase Auth 每人真帳號（解身份冒用；等登記表變成正式系統再說）
