# JO 核心功能重建套件：使用說明（給管理者）

這個套件是一組 prompt 與規則。讓 AI agent 依公司交付的 Spec，從零建立 JO（職缺）核心功能的本機 MVP：
.NET 後端＋React 前端＋MariaDB。套件本身不含任何公司內容，也不假設 Spec 的格式。Spec 的結構由 agent
在第 1 階段讀懂，寫成 `docs/build/spec-map.md`，再依此建立需求索引。

## 模型分工

| agent | 預設模型 | 做什麼 | 為什麼 |
|---|---|---|---|
| `rebuild-lead` | Opus 4.8 | 讀 Spec、需求索引、架構、切 slice、派工、驗收、進度 | 判讀與取捨最吃推理，錯了會影響全部 slice |
| `rebuild-dev` | Sonnet 5 | 逐張 slice 寫程式與測試 | 量最大，需要速度與穩定的寫碼能力 |
| `rebuild-reviewer` | Opus 4.8 | 每張 slice 獨立覆核是否忠於 Spec | 用新的 context 核對，不受實作者自評影響 |

實際跑下來如果 Sonnet 5 的判讀比較好，可以對調：改三個 agent 檔的 `model:` 即可，其他檔不用改。

## 套件檔案與放置位置

把 `rebuild-kit/` 底下的全部檔案（包括本檔，agent 會參照它），照相同的相對路徑放到新專案根目錄：

| 套件內路徑 | 用途 |
|---|---|
| `HOW-TO-USE.md` | 本說明（agent 會引用其中的開工步驟） |
| `AGENTS.md` | 所有 agent 自動載入的常駐規則 |
| `opencode.json` | 專案層 OpenCode 設定：關閉 session 分享與自動更新 |
| `.gitignore` | 排除 Spec、建置產物、node_modules、本機設定 |
| `.opencode/agent/rebuild-lead.md` | 主控 agent |
| `.opencode/agent/rebuild-dev.md` | 實作 subagent |
| `.opencode/agent/rebuild-reviewer.md` | 覆核 subagent |
| `.opencode/command/rebuild.md` | `/rebuild` 開工／續跑入口 |
| `docs/build/KICKOFF.md` | 開工 prompt 與階段計畫（主 prompt） |
| `docs/build/ps-mapping.md` | PeopleSoft → .NET／React／MariaDB 對照與陷阱 |

## 前置需求

- 已安裝：.NET SDK（8 或 10 LTS）、Node.js LTS（含 npm）、MariaDB 10.11 以上、git、OpenCode CLI。
- 套件來源：這台機器的 NuGet 與 npm 要能從公司核定的來源（內部鏡像）還原套件。不能還原時，
  agent 會在第 0 階段停下並說明缺什麼，不會自行改用其他來源。
- Spec：公司依 template 與 checklist 產出的全部 Spec 檔案。

## 開工步驟

1. **建新資料夾**，不要放在 MCPSample 裡面（例：`D:\work\jo-clone`）。在裡面執行 `git init`，不要加任何 remote。
   接著設定本專案的 commit 身分（代號即可，不必真名）：`git config user.name "<代號>"`、`git config user.email "<代號>@local"`。
2. **放套件檔**：依上表，從 GitHub 開 Raw 複製整檔貼上，存成 UTF-8。
3. **放 Spec**：把公司 Spec 的全部檔案放進 `spec-input\`，有 checklist 也一起放；子資料夾與檔名隨意，不要改內容。
   agent 只能讀文字檔（`.md`、`.txt`、`.csv`、`.json`）。Word／Excel 請先轉成 Markdown 或 csv（例如用公司機已有的
   markitdown skill；Excel 每個工作表一個 csv）再放進來；原檔可以一起留著當對照。這個資料夾在 `.gitignore` 裡。
4. **建資料庫**：用 MariaDB 附的 HeidiSQL 或 `mariadb` 用戶端，以管理者帳號執行下面這段（密碼自訂、不要貼給 agent）：

   ```sql
   CREATE DATABASE joclone CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
   CREATE DATABASE joclone_test CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
   CREATE USER 'joclone'@'localhost' IDENTIFIED BY '<自訂密碼>';
   GRANT ALL PRIVILEGES ON joclone.* TO 'joclone'@'localhost';
   GRANT ALL PRIVILEGES ON joclone_test.* TO 'joclone'@'localhost';
   ```

5. **設連線環境變數**（PowerShell，換成你的密碼）：

   ```powershell
   [Environment]::SetEnvironmentVariable('ConnectionStrings__Main', 'Server=localhost;Port=3306;Database=joclone;User=joclone;Password=<自訂密碼>', 'User')
   [Environment]::SetEnvironmentVariable('ConnectionStrings__Test', 'Server=localhost;Port=3306;Database=joclone_test;User=joclone;Password=<自訂密碼>', 'User')
   ```

   設完**關掉所有終端機再重開**，OpenCode 的 shell 才讀得到。
6. **填模型 ID**：執行 `opencode models` 找出公司可用的 Opus 4.8 與 Sonnet 5 的 ID。
   `rebuild-lead.md`、`rebuild-reviewer.md` 的 `model: REPLACE-ME/opus-4.8` 換成 Opus 4.8 的 ID；
   `rebuild-dev.md` 的 `model: REPLACE-ME/sonnet-5` 換成 Sonnet 5 的 ID。格式是 `provider/model-id`。
7. **開工**：在新專案根目錄執行 `opencode`，按 Tab 切到 `rebuild-lead`，輸入 `/rebuild`。
   不用 `/rebuild` 的話，也可以直接輸入：「讀 docs/build/KICKOFF.md，從第 0 階段開始。」

## 過程中你要做的事

| 時機 | 你會看到 | 你要做的 |
|---|---|---|
| 第 0 階段結束 | 環境與 Spec 盤點結果、阻擋項 | 排除阻擋（例如請 IT 開套件來源），回覆「繼續」（新 session 就輸入 `/rebuild 繼續`） |
| 第 1 階段結束 | 需求鍵數、slice 數、待業務確認的假設 `A-###`、技術決定 | 看過後回覆「繼續」，或指出要調整的地方 |
| 第 2～3 階段 | 每張 slice 一段 5 行內的簡報 | 通常不用做事；出現權限詢問就依內容允許或拒絕 |
| 停下來問你 | 工具壞掉、Spec 矛盾需要業務判斷、同一問題修不好 | 依說明處理後回覆 |
| 第 4 階段結束 | `docs/build/mvp-report.md`、`docs/build/smoke.md` | 照 `README.md` 啟動，照 smoke.md 手動走一遍 |

- **中斷或 context 滿了**：開新的 OpenCode session，切到 `rebuild-lead`，輸入 `/rebuild`，會從 `docs/build/status.md` 接續。
- **只看進度**：`/rebuild status`。
- **加指示**：`/rebuild <你的指示>`，例如「這輪只做 S07」。
- 請用互動式 session 操作，不要 headless 執行：權限詢問在 headless 下沒人回答，會卡住。

## 你會拿到什麼

- 可在本機執行的程式：啟動方式寫在新專案的 `README.md`（單一指令 `scripts\run-local.cmd`；用 `.cmd` 是因為公司執行原則會擋 `.ps1`）。
- `docs/build/traceability.md`：每個需求鍵的實作狀態、程式位置與測試名。
- `docs/build/assumptions.md`：Spec 的缺口與暫定做法。這些要找業務確認，或回 Spec 產製端補查。
- `docs/build/mvp-report.md`：完成度統計、驗收測試結果、未解項目、刻意簡化的非業務項目。
- `docs/build/smoke.md`：手動操作驗證清單。

「測試全過」只代表程式符合 agent 對 Spec 的理解，不代表與 PeopleSoft 等價，也不等於企業驗收。
請業務人員依 smoke.md 實際操作確認。

## Spec 更新時

1. 刪掉舊的 `spec-previous\`（如果有），把目前的 `spec-input\` 整個改名為 `spec-previous\`，再建新的 `spec-input\` 放入新版檔案。
2. 執行 `/rebuild spec-update`：agent 比對差異、更新需求索引與追蹤表、開新的 slice，回報差異後等你回覆「繼續」。

## 機密

- 新專案的 `spec-input\`、`docs\build\`、程式碼都含公司業務內容：不要加外部 remote，也不要推到 GitHub。
  是否進公司內部 git，依公司規範決定。
- agent 被設定為不使用網路搜尋與網頁擷取，也不使用 PeopleSoft／Oracle 的 MCP 工具（Spec 是唯一來源）。
- 回報給框架維護端時，只給：目前階段、slice 完成數／總數、測試通過／失敗數、`A-###` 數、卡住的工具錯誤類型。
  不給物件名、欄位名、檔案路徑或訊息原文。

## 常見狀況

- **切到 `rebuild-lead` 或執行 `/rebuild` 時出現 model not found**：`model:` 還是 REPLACE-ME 或 ID 打錯，回到開工步驟 6。
- **第 0 階段說 `model:` 還是 REPLACE-ME**：同上，改 dev 或 reviewer 的檔。
- **套件還原失敗**：多半是 npm registry 或 NuGet source 沒有指向公司內部來源，請 IT 設定。
- **測試連不到資料庫**：檢查開工步驟 4、5，重開終端機與 OpenCode。
- **OpenCode 啟動明顯變慢**：可以比照 MCPSample，在新專案放 `.opencode\.npmrc`，內容一行 `offline=true`。
- **agent 在 shell 前景跑長駐程式而卡住**：常見寫法已用權限擋下；真的發生時中斷該步，提醒它依 AGENTS.md 只跑 build 與 test。
- **commit 失敗說沒有身分**：回到開工步驟 1 設定 `git config user.name`／`user.email`。
