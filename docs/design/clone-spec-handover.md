# Component → 核心功能重建 Spec：交付與搬運

分支：`claude/peoplesoft-framework-handover-0u6b5g`；本波基於 `1a6b3f2` 直接修改，版本與發布紀錄以 git 為準。
忽略 .NET；未改動既有未追蹤的 `issues-33-36-independent-review.md`。

## 使用者入口

在 OpenCode 輸入 `/ps-spec TW_DEMO_A TW_DEMO_B`，或切到 `ps-spec-author` 後直接輸入清單。
上述為合成名，真實名稱只在公司機輸入。相同清單重送會續跑；不需 Pack、Domain 或先跑領域研究。
只查進度可說「狀態 TW_DEMO_A」，修復阻擋後說「重試被擋項 TW_DEMO_A」，上游更新後說「重新查證 TW_DEMO_A」。

最新文件入口：`docs/ps-spec/<job>/README.md`，含 Spec、來源 trace、品質 gate；`current.json` 是機械入口。
已驗收正文與未驗收候選分開，後者也有可讀草稿。需要人工交付修稿時另存，不直接改 generated。
操作細節見 `.opencode/peoplesoft/SOP.md` 的 SOP-25；SOP-24 只保留給需要既定模板映射者。

## 本波設計

- 讀者是沒有原系統 context 的獨立 LLM，目的為重建核心行為，不是描述整個 PeopleSoft 平台。
- 10 個主題固定必要細節：範圍、流程、UI、資料、規則、狀態、交易、介面、權限、驗收。
  條件要有原始欄位與運算、狀態要有守衛與拒絕路徑、畫面要有逐欄呈現／可編輯條件。
- 以實際使用鏈決定 CORE／DEPENDENCY／EXCLUDED；必要的原生依賴只寫最小替代契約。
- 分頁研究、獨立 session 覆核、確定性驗收／組文；多 Component 覆核能讀全工作已接受章節。
- 缺證據只補查受影響頁，明確 Retry 才增加額度；未知不能經續頁或 N/A 洗成完成。
- 繁體中文敘述，技術名稱、schema、PeopleCode／SQL、stored value、原始訊息保留原文。
- 本機 source／判證契約 fingerprint 改變會建新版本；Oracle 即時變動不會自動被本機 hash 偵測，已知更新請重新查證。

REVIEW_READY 只表示結構驗證與獨立模型覆核通過，不能證明語意完整、企業 E2E 或重建等價。
未觀察到的動態 UI／權限／併發結果要留缺口；公司內部核對與重建端驗收仍必要。
所有 runtime、trace、Spec 均留本機並 gitignore；對外只回 `CLONE1` 結論碼。

## 驗證範圍

| 驗證 | 結果／邊界 |
|---|---|
| Windows PowerShell 5.1 packet／review／renderer 單元 | 88 PASS，0 FAIL |
| Windows PowerShell 5.1 CLI＋fake worker | 34 PASS，0 FAIL；含同 Root 互斥、不同 Root 同名 Component 的鎖隔離 |
| 固定模板 Spec 回歸 | 27 情境全部通過，含父子標題、同列 token、slot 重綁、NO_EVIDENCE、續篇識別 |
| auto-loop 回歸 | 全部通過；合成 Git fixture 隔離全域 autocrlf，無本專案 commit |
| PS5.1 靜態守衛／模型文件 lint | 0 阻擋；靜態守衛 12 項既有警告 |
| runtime-guard 單元／真 OpenCode＋假 MCP／假模型 | 10 單元、13 E2E 情境通過；不連企業資料 |
| 新 command／權限 smoke | 真 OpenCode 1.18.29；author Status、worker read/write、禁止偽造收據。不是實際業務或完整 task 委派鏈測試 |
| 公司 PeopleSoft E2E | 未執行，無法從本環境驗證 |

新測試入口：`scripts/tests/test-spec-clone.ps1`、`scripts/tests/test-spec-build.ps1`、
`tests/runtime-guard/run-clone-smoke.mjs`。後者只用既有 OPENCODE_BIN 與 Node，啟動 localhost 合成模型。
不需搬任何下載的測試執行檔或測試暫存資料。公司機的模型與 MCP 沿用公司核定設定，沒有新增 npm 依賴。

## 整檔搬運核對清單

路徑相對 repo 根；行數允許 ±1 行尾差異。PS1 一律另存 **UTF-8 with BOM**。
公司機不要跑 WriteManifest／WriteGenericManifest；搬完跑 `powershell -NoProfile -File scripts/ps-fs-doctor.ps1`，
以及 `powershell -NoProfile -File scripts/ps-spec.ps1 -Doctor`（預期 `SPEC1-0-03`）。
保留公司已有設定與私有規則，不將公司內容回傳維護端。

| 路徑 | 類型 | 行數 | 核對 |
|---|---|---:|---|
| `.gitignore` | 修改 | 41 | 必含 docs/ps-spec/ |
| `.opencode/agent/ps-ae-flow.md` | 修改 | 96 | |
| `.opencode/agent/ps-auditor.md` | 修改 | 266 | |
| `.opencode/agent/ps-clone-worker.md` | 新增 | 72 | |
| `.opencode/agent/ps-metadata-flow.md` | 修改 | 118 | |
| `.opencode/agent/ps-orchestrator.md` | 修改 | 237 | |
| `.opencode/agent/ps-peoplecode-flow.md` | 修改 | 87 | |
| `.opencode/agent/ps-spec-author.md` | 新增 | 65 | |
| `.opencode/agent/ps-sql-flow.md` | 修改 | 70 | |
| `.opencode/agent/ps-sqr-flow.md` | 修改 | 78 | |
| `.opencode/agent/ps-ui-flow.md` | 修改 | 146 | |
| `.opencode/command/ps-clone-batch.md` | 新增 | 11 | |
| `.opencode/command/ps-spec.md` | 新增 | 12 | |
| `.opencode/peoplesoft/lessons/applied.md` | 修改 | 3502 | |
| `.opencode/peoplesoft/SOP.md` | 修改 | 948 | |
| `.opencode/peoplesoft/spec/clone-contract.md` | 新增 | 64 | |
| `.opencode/peoplesoft/spec/clone-profile.json` | 新增 | 59 | |
| `.opencode/peoplesoft/spec/generic.manifest.json` | 修改 | 116 | |
| `.opencode/peoplesoft/spec/pack.schema.json` | 修改 | 85 | |
| `.opencode/peoplesoft/spec/support-codes.md` | 修改 | 188 | |
| `AGENTS.md` | 修改 | 111 | |
| `README.md` | 修改 | 639 | |
| `scripts/ps-spec-build.ps1` | 新增 | 450 | 存 UTF-8 with BOM |
| `scripts/ps-spec-clone-lib.ps1` | 新增 | 282 | 存 UTF-8 with BOM |
| `scripts/ps-spec-lib.ps1` | 修改 | 2727 | 存 UTF-8 with BOM |
| `scripts/ps-transfer-manifest.json` | 修改 | 592 | |
| `scripts/tests/test-auto-loop.ps1` | 修改 | 1024 | 存 UTF-8 with BOM |
| `scripts/tests/test-spec-build.ps1` | 新增 | 266 | 存 UTF-8 with BOM |
| `scripts/tests/test-spec-clone.ps1` | 新增 | 166 | 存 UTF-8 with BOM |
| `scripts/tests/test-spec.ps1` | 修改 | 1132 | 存 UTF-8 with BOM |
| `tests/runtime-guard/run-clone-smoke.mjs` | 新增 | 114 | 維護測試用 |
| `tests/runtime-guard/unit.test.mjs` | 修改 | 398 | 維護測試用 |
| `HANDOFF.md` | 修改 | 444 | 維護交接用，可不搬公司機 |
| `docs/design/clone-spec-handover.md` | 新增 | 96 | 本清單，可不搬公司機 |

### 介面參考

命令參數與 agent 指定依 OpenCode [Commands](https://opencode.ai/docs/commands/)；
工具與 write 所用 edit permission 依 [Tools](https://opencode.ai/docs/tools/) 及 [Permissions](https://opencode.ai/docs/permissions/)。
實際配置仍以本 repo 既有單數 agent／command 目錄慣例及上述真 CLI smoke 為準，未變更公司 OpenCode 版本。
