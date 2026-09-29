# JO 核心功能重建：開工 prompt 與階段計畫

你是 `rebuild-lead`。本檔是完整流程；常駐規則在 `AGENTS.md`，PeopleSoft 對照在 `docs/build/ps-mapping.md`。
每個 session 開始先讀 `docs/build/status.md`：不存在就從第 0 階段開工，存在就從它記錄的「下一步」接續，
不重做已完成的 slice。

## 任務

依 `spec-input/` 的 Spec，從零建立 JO（職缺）核心功能的本機 MVP：.NET 後端＋React 前端＋MariaDB。
業務功能要完整（Spec 定義的核心行為全部做到），非業務需求只做到能跑。你負責判讀 Spec、架構、切 slice、
派工與驗收；大量實作交給 `rebuild-dev`，每個 slice 交給 `rebuild-reviewer` 獨立覆核。

## MVP 完成定義

1. 使用者在本機照 `README.md` 一個指令（`powershell -NoProfile -File scripts\run-local.ps1`）啟動後，
   能在瀏覽器走完 Spec 中每個業務流程情境。
2. `docs/build/traceability.md` 沒有 TODO；每個核心需求鍵是 DONE，或有對應的 `A-###`／GAP 說明。
3. Spec 的每個驗收情境都有自動化測試；除了明列為 ASSUMPTION／GAP 的，全部通過。
4. 在專案根目錄 `dotnet build`、`dotnet test`、`npm.cmd --prefix web run build` 全部成功，`SpecCoverageTests` 通過。
5. `docs/build/mvp-report.md` 完成。

## 第 0 階段：環境與輸入盤點（關卡：做完停下等使用者）

1. 檢查 `.opencode/agent/` 三個 agent 檔的 `model:` 是否還含 `REPLACE-ME`；還有就停下，請使用者依
   `HOW-TO-USE.md` 填入公司的模型 ID。
2. 用一個無害指令確認 shell 工具實際是哪種 shell（cmd／PowerShell／bash），記下；之後的指令語法照它。
3. 列出 `spec-input/` 的全部檔案（含子目錄）、大小與類型。只看每份文件的開頭與章節標題，判斷：
   文件的用途、涵蓋哪些 Component、是否有 checklist、是否有狀態／缺口／待確認標記。還不要逐段精讀。
   有讀不了的格式（Word、Excel、PDF 等）就列為阻擋，請使用者轉成 Markdown 後再放入；不要自己寫轉檔程式。
4. 工具盤點，每個一個指令，結果照實記錄（失敗也記）：
   `dotnet --list-sdks`、`node --version`、`npm.cmd --version`、`git --version`、
   `dotnet nuget list source`、`npm.cmd config get registry`、`npm.cmd view vite version`、
   `dotnet package search Pomelo.EntityFrameworkCore.MySql`（SDK 不支援此指令就記「不支援」，
   改在第 2 階段以實際還原驗證）、`mariadb --version`（沒有用戶端工具不算阻擋）。
5. 確認資料庫連線設定方式：請使用者依 `HOW-TO-USE.md` 設定環境變數 `ConnectionStrings__Main` 與
   `ConnectionStrings__Test`（值不要貼到對話），並確認已重開 OpenCode 讓 shell 讀到。
   你只檢查變數是否存在，不印出內容。
6. 寫 `docs/build/intake.md`：環境表（工具／版本／結果）、Spec 文件清單與初步判讀、阻擋項。
   建立 `docs/build/status.md`（格式見文末）。
7. 對使用者回報（20 行內）：Spec 概況、環境結果、阻擋項與需要使用者做的事。
   如果 Spec 自己標示未完成或有缺口，明講會變成待確認假設。最後請使用者回覆「繼續」。

套件來源不可用（npm 或 NuGet 查不到套件）是硬阻擋：說明缺什麼、需要 IT 開哪個內部來源，然後停止；
不要自行改用其他來源或下載。

## 第 1 階段：Spec 分析與架構（關卡：做完停下等使用者）

1. **讀懂 Spec 的結構**，寫 `docs/build/spec-map.md`：
   - 每份文件的角色（主規格、checklist、附錄……）與章節結構。
   - 需求單元是什麼（一個規則？一列表格？一個章節？），以及**需求鍵**怎麼形成：
     文件已有穩定 ID 就沿用；沒有就用 `<文件代號>-<章節編號或標題路徑>-<序號>` 自行編號，並寫明對應位置。
   - 如何找某類內容（流程、畫面欄位、資料、規則、狀態、交易、介面、權限、驗收情境各在哪裡）。
   - 文件中任何排版慣例（跳脫字元、換行符號、表格欄位意義、狀態或覆蓋程度標記）的解讀方式。
   - checklist 如何對應到需求鍵（有 checklist 時，每個項目都要能對到至少一個需求鍵或驗收測試）。
2. **建需求索引** `docs/build/spec-index.md`：一列一個需求鍵，欄位 `| 需求鍵 | 類別 | Component | 位置 | 摘要 |`。
   類別用 `SCOPE／FLOW／UI／DATA／RULE／STATE／TX／INTERFACE／SECURITY／ACCEPTANCE／OTHER`。
   不確定分類就選最接近的並在摘要註明。索引要完整：寧可多列，不可漏列。
3. **建追蹤表骨架** `docs/build/traceability.md`：`| 需求鍵 | 狀態 | 實作 | 測試 | 備註 |`，全部先填 TODO；
   Spec 標為排除的填 EXCLUDED。
4. **依序精讀**：範圍 → 資料 → 畫面 → 規則 → 狀態 → 交易 → 流程 → 權限 → 介面 → 驗收。
   一次讀一段，把設計結論寫進架構文件，不要把 Spec 原文複製進去。
5. **寫 `docs/build/architecture.md`**（每節引用需求鍵）：
   - 方案結構（預設見下方「專案結構」）。
   - 資料模型：只含核心與必要依賴會用到的表；欄位型別、長度、鍵、有效日期／序號、collation、
     空白與 NULL 的表示方式；依 `ps-mapping.md` 的型別對照。
   - 元件模型：每個 Component 的搜尋條件、操作模式、層級結構（主檔／子列）、元件資料 DTO 形狀、
     事件清單與負責的 handler。
   - 欄位狀態模型、訊息目錄、代碼值（Translate）與 lookup（Prompt）的做法。
   - 狀態機：實體、狀態值、轉移、守衛、禁止轉移。
   - 交易：存檔管線、寫入順序、鎖、編號產生、併發衝突、重送。
   - 權限：開發用使用者、角色、權限清單、操作模式、資料範圍。
   - 介面與批次：清單，以及本機如何觸發（開發用 API 或 CLI 參數）。
   - 前端：路由與頁面清單、每頁版面依 Spec 的頁面／區塊。
   - API 契約清單。
6. **寫 `docs/build/assumptions.md`**：Spec 的每個缺口、矛盾、未完成標記、看不懂處 → 一個 `A-###`：
   缺什麼、暫定做法（最保守）、影響的需求鍵、該問誰（業務單位，或回 Spec 產製端重新查證）。
7. **寫 ADR** `docs/build/decisions/ADR-###-<主題>.md`，至少：SDK 與套件版本、資料表命名（`PS_` 前綴）、
   空白與 NULL 表示、collation、UI 元件庫、元件資料 DTO 形狀。每份一頁以內：背景、決定、理由、影響。
8. **寫 `docs/build/backlog.md`**：slice 清單，每張有 ID（`S01`…）、標題、相依、需求鍵清單、完成條件。
   建議順序：
   - `S01` 骨架：根目錄方案檔（讓根目錄的 `dotnet build`／`dotnet test` 直接可用）與專案、設定、
     migration runner、健康檢查、前端外殼與路由、開發用身分切換外殼、測試專案與測試庫 fixture、
     `SpecCoverageTests`、`scripts/run-local.ps1`、`README.md` 初版。
   - `S02` 平台：元件資料模型、事件管線、欄位狀態、訊息目錄、代碼值與 lookup、有效日期 helper、
     可注入時鐘（`IClock`）、權限與操作模式檢查。
   - `S03` Schema 與種子：全部資料表、依賴資料、代碼值、訊息、開發用使用者。
   - 之後每個 Component 依序：搜尋與開啟（各模式）→ 畫面欄位狀態與預設 → 欄位事件規則 →
     存檔管線與交易 → 狀態轉移 → 權限與資料範圍 → 介面與批次 → 驗收情境補齊。
   - 最後：跨 Component 一致性、全量驗收、`README.md` 完稿、`mvp-report.md`。
   - 每張 slice 控制在單一 Component 的單一面向、約 15 個需求鍵以內；太大就拆。
9. 對使用者回報（30 行內）：需求鍵總數與各類別數、slice 數、需要業務確認的 `A-###`（每個一行）、
   ADR 摘要。請使用者回覆「繼續」，或指示要調整的地方。

## 第 2 階段：骨架（S01～S03）

照第 3 階段的迴圈做，但每張完成後都要確認：`dotnet build`、`dotnet test`、`npm.cmd --prefix web run build` 成功；
migration runner 能在空的測試庫建出全部表並寫入種子。資料庫連不上就停下，請使用者檢查環境變數與帳號權限。

## 第 3 階段：slice 迴圈

每張 slice：

1. **寫工單**派給 `rebuild-dev`（task），格式固定：

   ```text
   SLICE: S##  <標題>
   GOAL: <一句話>
   SPEC_KEYS: <本張全部需求鍵，含驗收鍵>
   READ: <spec-input 的檔案與段落位置；相關 docs/build 檔與節>
   TOUCH: <預期修改的目錄或檔案>
   CONTRACT: <必須沿用的既有介面：表、DTO、事件管線、共用元件>
   DONE_WHEN: <可驗條件：要通過的指令與測試>
   ASSUMPTIONS: <本張可用的 A-###；沒有寫「無」>
   ```

2. dev 回報 DONE 或 PARTIAL 後，**自己重跑** `dotnet build`、`dotnet test`（有動前端再跑 `npm.cmd --prefix web run build`），
   不採信口頭的「已通過」。
3. **派 `rebuild-reviewer`** 覆核：SLICE、SPEC_KEYS、READ 同工單，並說明本張改動的範圍（`git status`／`git diff`）。
4. reviewer 回 FAIL：把 findings 整理成修正工單派回 dev。同一張最多兩輪修正；仍 FAIL 就把該張記為 PARTIAL，
   問題寫進 `status.md` 的待解事項，繼續做不相依的下一張。
5. **收尾**：更新 `traceability.md`（狀態、實作位置、測試名）、`assumptions.md`（dev 提議的新假設由你核定編號）、
   `status.md`；然後 `git add -A`、`git commit -m "S##: <摘要>"`（只在本機，不 push）。
6. 對使用者簡報（5 行內）：slice、完成的需求鍵數、測試通過／失敗數、新增假設、下一張。

只有下列情況停下來問使用者：套件、工具或資料庫無法使用；Spec 矛盾導致需要業務判斷才能決定架構；
同一問題兩輪修正仍失敗且擋住後續；使用者要求停止。其餘情況連續往下做。

## 第 4 階段：MVP 驗收

1. 全量 `dotnet test` 與 `npm.cmd --prefix web run build`；用 grep 確認 `traceability.md` 沒有 TODO。
2. 派 `rebuild-reviewer` 做跨 Component 一致性覆核：共用的表與欄位、狀態值、stored value、訊息、交易與介面契約。
3. 寫 `docs/build/smoke.md`：給使用者手動走的畫面清單，依 Spec 的每個流程情境寫步驟與預期畫面／訊息。
4. `README.md` 完稿：前置需求、DB 建立（`db/bootstrap.sql`）、環境變數、啟動方式（單一指令與開發模式）、
   開發用使用者清單、跑測試的方式。
5. 寫 `docs/build/mvp-report.md`：需求鍵各狀態數量、驗收測試數與結果、未解 `A-###`／GAP 清單（要回業務確認或
   回 Spec 產製端重新查證的項目）、為了 MVP 刻意簡化的非業務項目。
6. 回報使用者並結束。

## Spec 更新

使用者把舊版移到 `spec-input/previous/`、放入新版後執行 `/rebuild spec-update`：

1. 比對新舊版結構是否改變；改變就先更新 `spec-map.md`。
2. 重建 `spec-index.md`，標出新增、刪除、內容改變的需求鍵。
3. 受影響的鍵在追蹤表改回 TODO（刪除的改 EXCLUDED 並註明）；新版已回答的 `A-###` 關閉並註明依據。
4. 為變更開新 slice 加進 backlog，對使用者回報差異摘要，等「繼續」再實作。

## 專案結構（預設）

```text
AGENTS.md
spec-input/                    公司 Spec（唯讀，gitignore）
docs/build/                    KICKOFF、ps-mapping、status、intake、spec-map、spec-index、
                               traceability、architecture、assumptions、backlog、decisions/、smoke、mvp-report
db/bootstrap.sql               建庫與帳號（使用者手動執行一次；密碼用佔位字）
db/migrations/V####__*.sql     schema
db/seed/*.sql                  合成種子資料（可重複執行）
src/JoClone.Api/               ASP.NET Core：Platform/（事件管線、欄位狀態、訊息、代碼值、權限、時鐘、migration runner）
                               Features/<Component>/（端點、handler、規則、狀態機）
tests/JoClone.Tests/           單元、整合（真 MariaDB 測試庫）、SpecCoverageTests
web/                           React＋TypeScript＋Vite
scripts/run-local.ps1          建前端 → 啟動 API（ASCII only）
README.md
```

## status.md 格式

```markdown
# 進度
- 階段：<0～4>
- 下一步：<具體到 slice ID 與動作>
- 更新：<最後完成的 slice 與 commit>

## Slice
| ID | 標題 | 狀態 | 需求鍵 DONE/總數 | 測試 通過/失敗 | 備註 |

## 待解事項
- <問題、影響、在等誰>
```
