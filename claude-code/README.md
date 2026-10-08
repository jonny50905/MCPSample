# Claude Code 版——PeopleSoft 知識庫分析框架

> 本檔給人看，**不必搬到公司機**（不在搬運 manifest 內）。

同一套框架的第二個前端：**Claude Code CLI＋Sonnet**。PeopleSoft 的規則、契約、外環腳本與 OpenCode 版完全相同，
只換掉「CLI 怎麼開主代理、怎麼委派、怎麼擋錯誤呼叫、外環怎麼開 headless session」這一層。
OpenCode 版（repo 根的 `.opencode/`＋`AGENTS.md`）保留不動、照常可用。**公司機只裝其中一版、只搬那一版。**

## 搬運：只搬這一版

**最省事：搬運包**。`transfer/ps-bundle-claude.txt` 就是下表全部的檔收成的一個文字檔：複製 Raw、另存 UTF-8，
在公司機執行 `powershell -NoProfile -File .\scripts\ps-bundle.ps1 -Bundle <檔>`（先加 `-DryRun` 看計畫）。
第一次要先手動搬 `scripts/ps-bundle.ps1` 一個檔。本機改過的檔（例如已回填的 profile）會保留，兩邊都改過的另存 `.incoming`。
詳見 `transfer/README.md`。逐檔搬的對照如下：

| 來源（GitHub） | 公司機路徑 |
|---|---|
| `claude-code/CLAUDE.md` | `CLAUDE.md` |
| `claude-code/.claude/**` | `.claude/**`（去掉 `claude-code/` 前綴） |
| `scripts/**` | `scripts/**`（兩版共用的外環，原樣） |

- 完整清單＝`scripts/ps-transfer-manifest.claude.json`：`files[].path` 是公司機路徑、`repo` 是 GitHub 上的位置
  （`scripts/` 的檔兩者相同，沒有 `repo` 欄）。本 manifest 自己也要搬。
- `.ps1`（含 `.claude/hooks/ps-runtime-guard.ps1`）一律存 **UTF-8 with BOM**；其他檔 UTF-8。
- 搬完跑 `powershell -NoProfile -File .\scripts\ps-fs-doctor.ps1`：看到「搬運完整性（Claude Code 版…）」且結論 `G` 才算完成。
  外環與 fs-doctor 以 `.claude\peoplesoft` 是否存在認版本；同一資料夾還要跑 OpenCode 版外環時先 `$env:PS_CLI='opencode'`。

## 部署後的樣子

```text
<專案>/
├─ CLAUDE.md                     常駐指引（執行期規則）
├─ .claude/
│  ├─ settings.json              模型 sonnet、權限允許清單、hook（不設預設主代理：直接 `claude` 是一般 session）
│  ├─ hooks/ps-runtime-guard.ps1 執行期 guard（PreToolUse／PostToolUse；PowerShell 5.1）
│  ├─ agents/                    主代理 5＋子代理 7＋Spec 文件的讀者、worker、判定 4
│  ├─ commands/                  /ps-research、/ps-audit、/ps-lesson、/ps-correct、/ps-spec＋外環專用 4 個
│  ├─ skills/                    ps-* 11 個
│  └─ peoplesoft/                契約、cookbook、profile、domain map、報告模板、spec、sdoc（Spec 文件的契約、schema、範例）、本機教訓帳本
├─ scripts/                      外環（兩版共用）
└─ docs/ps-research/ …           研究產出（本機／內部 git，不動）
```

## 第一次安裝（公司機）

1. **資料夾**：建議沿用現有專案資料夾（研究產出 `docs/ps-research`、`.ps-private`、`.ps-runtime` 都在裡面），把上表的檔搬進去。
   改用 Claude Code 版之後，這個資料夾就不要再開 OpenCode（OpenCode 也會讀到 `.claude/skills`，兩套同名 skill 會混在一起）；
   兩版要並存請另開資料夾。
2. **profile**：`.claude/peoplesoft/customization-profile.yaml` 的鍵與值和 OpenCode 版逐行相同（只有註解不同）——
   把舊檔已回填的值（`oracle.connectionName`、`oracle.currentSchema`、`navigation` 區塊…）照抄過來，或直接把舊檔整份複製過來。
   `business-domain-map.yaml`、`research-domains.txt` 若本機改過，同樣複製過來。
3. **註冊 MCP（名字一個字都不能差）**：`oracleMCP`、`PeoplecodeElasticSearch`、`PeoplecodeSource`、`PeoplecodeMetadata`。
   用 user scope 註冊，內部主機名就不會落在專案檔裡：
   - stdio 型：`claude mcp add --scope user oracleMCP -- <原本 opencode.json 裡該 server 的 command 與 args>`
   - http／sse 型：`claude mcp add --scope user --transport http PeoplecodeSource <URL>`（sse 改 `--transport sse`）
   - 確認：`claude mcp list` 四個都 connected；工具全名會是 `mcp__oracleMCP__connect` 這種形狀。
4. **信任資料夾**：在專案資料夾執行一次 `claude`，接受信任詢問。沒信任時，專案 `settings.json` 的權限允許清單會被忽略，
   外環 headless session 的工具會全部被拒。
5. **驗收**：`powershell -NoProfile -File .\scripts\ps-claude-doctor.ps1 -Live`——檢查版本判定、claude 版本、powershell、
   hook 自測、profile、四個 MCP 註冊，並開一個真 headless session 只做第 0 步開線；結論代號 `G` 才算裝好
   （代號：V 版本判定／C claude／P powershell／H hook／F profile／N MCP／T 工具被拒＝多半沒信任／L connect 沒成功）。
   之後 `claude --agent ps-orchestrator` 問一題業務問題，第一個動作應是 `mcp__oracleMCP__connect`（connection_name＝profile 值）。

需求：Claude Code CLI 2.1 以上（用到 `--agent`、`--permission-mode dontAsk`、agent frontmatter 的 hooks）；
hook 指令是 `powershell -NoProfile -File .claude/hooks/ps-runtime-guard.ps1`，`powershell` 要在 PATH 上（Git Bash 與 PowerShell 都能執行這行）。
`claude` 用 npm 裝（`claude.cmd`）或原生安裝（`claude.exe`）外環都認得。

## 日常使用

| 要做什麼 | 怎麼開 |
|---|---|
| 業務問答 | `claude --agent ps-orchestrator` |
| 產完整業務文件 | `claude --agent ps-deep-research`，進去後 `/ps-research <領域>`（或一行：`claude --agent ps-deep-research "/ps-research <領域>"`） |
| 稽核／教訓／知識指正 | 同上的主代理，`/ps-audit <領域>`、`/ps-lesson <描述>`、`/ps-correct <正確知識>` |
| 以 Component 產 Spec 文件（00-index＋14 份＋90） | `/ps-spec <Component...>`（委派 ps-spec-author），或 `claude --agent ps-spec-author` 直接輸入清單；見下方「Spec 文件」 |
| 框架維護、排錯、看 log | `claude`（一般 session，沒有主代理的工具限制；改了框架檔記得回報維護端） |
| 無人看管跑批 | 不變：`scripts\ps-auto-loop.ps1`、`ps-auto-all.ps1`、`ps-supplemental.ps1`、`ps-spec.ps1 -Run`——外環自動改開 `claude -p --agent …` |

指令打錯主代理（例如在問答 session 打 `/ps-research`）時，模型只會回一行「請以 `claude --agent ps-deep-research` 開新 session」，不會動檔。

## 與 OpenCode 版的差異（只有機制，規則相同）

| 項目 | OpenCode 版 | Claude Code 版 |
|---|---|---|
| 主代理 | Tab 切換 | `claude --agent <名>`；不設預設主代理（直接 `claude` 是一般 session，供維護與排錯） |
| 委派 | task 工具 | Agent 工具（`subagent_type` 參數名不變）；子代理不能再委派 |
| 工具權限 | tools 覆寫表（沒列＝開） | agent `tools:` 白名單（沒列＝沒有）＋`settings.json` 權限允許清單 |
| MCP 工具名 | `oracleMCP_connect` | `mcp__oracleMCP__connect` |
| MCP 註冊 | 全域 opencode.json | `claude mcp add --scope user`（或專案 `.mcp.json`，含主機名時不建議） |
| 執行期 guard | plugin（JS） | hook（PowerShell）：connect 目標＝profile、Agent 目標不得是 skill 名或主代理名；ps-* 主代理下只准 ps-* 子代理（內建代理也擋），一般 session 可用內建代理維護排錯、suggestedNext 註記、worker 讀寫路徑白名單 |
| oracleMCP 掛載故障 | `/mcps` 重掛；plugin 可受控自動重掛 | 該 session 打 `/mcp` 選 oracleMCP 重新連線；**沒有自動重掛**（profile 的 `mcpAutoRecover` 不使用） |
| 外環 headless | `opencode run --command X "<參數>"` | `claude -p --agent <主代理> --permission-mode dontAsk --output-format stream-json --verbose "/X <參數>"` |
| headless 權限 | 全域 opencode.json 的 permission | `.claude/settings.json`：允許 MCP 查詢工具、寫 `docs/ps-research/**`／`.ps-runtime/spec/**`／`.ps-runtime/clone-spec/**`／`.ps-runtime/sdoc/**`、ps-spec-build 與 ps-sdoc 命令；拒絕 `sqlcl_run`、WebFetch、WebSearch；其餘在 headless 一律自動拒絕 |
| `/ps-spec` | ps-spec-build（CLONE1：單一 spec.md） | ps-sdoc（DOC1：00-index＋14 份文件＋90 問題清單；本版獨有） |
| session 紀錄 | out／err／rc | 另有 `<時間>-<tag>.stream.jsonl`（完整事件流）；`.out.txt` 是抽出的最終回覆（稽核 stdout 回收照舊） |
| 教訓帳本 | `lessons/applied.md`（L 編號） | 本機帳本 `.claude/peoplesoft/lessons/applied.md`（C 編號；維護端主帳本另計） |
| 模型 | 本機部署模型 | `settings.json` 的 `model: sonnet`；外環 `-Model` 透傳 `--model` |

SOP 編號照用；有差異的只有：

- **SOP-10**（serving 端上限）：不適用——模型與 context 上限由 Claude Code 管理，超過時自動壓縮；外環仍會把「Prompt is too long」標成 CONTEXT_OVERFLOW。
- **SOP-17**（無人看管權限）：改看 `.claude/settings.json` 的允許清單與上面第 4 步的信任；要臨時換權限模式設 `$env:PS_CLAUDE_PERMISSION_MODE`（只接受 dontAsk／acceptEdits／default／auto／bypassPermissions）。
- **SOP-21**（掛載故障）：`/mcp` → oracleMCP → 重新連線；hook 紀錄在 `auto-loop-logs\ps-runtime-guard\hook-<日期>.jsonl`（只記工具名、代理名、決策與錯誤碼）。

## Spec 文件（本版獨有）

`/ps-spec <Component...>` 產生給另一個 LLM 重建功能用的 Spec 文件：00-index（入口）、01～09、14、16～19 共 14 份，加 90 問題清單。

1. 第一次執行會在 `.ps-private\sdoc\<jobId>\` 建四個檔的骨架，結論碼 `DOC1-0-01`：
   - `status.md`：把這組 Component 的狀態圖（Mermaid flowchart 或 stateDiagram-v2，畫法不限）與圖下的說明貼進來，刪掉第一行的 `SDOC:SKELETON` 標記。必備。
   - `project.md`：目標與決策責任（選填）。
   - `decisions.md`：之後裁決 90 的問題用。
   - `approvals.md`：之後核准文件用（填 00-index 上的 docHash 前 12 碼）。
2. 再下同一個 `/ps-spec`：三位讀者各自解讀狀態圖（不一致的逐項再問一次、多數決），之後依序研究範圍、資料、權限、說明區域、流程、介面、功能、畫面、規則、操作、測試；每頁研究與獨立覆核是兩個 session。
   研究完成後，三位只看渲染後文件的乾淨讀者回答外環出的題目（L5）；第 1 輪沒讀懂的項目交原研究單元改寫，再由新讀者重問一次。
   一次跑 `-MaxSessions` 個 session，結論碼 `DOC1-3-02-<n>` 時 ps-spec-author 會自動續跑。
3. 產出在 `docs\ps-spec\<jobId>\README.md`（入口）與 `generated\<代號>\`；結論碼與下一步見 `.claude\peoplesoft\spec\support-codes.md` 的 DOC1。
4. 執行狀態在 `.ps-runtime\sdoc\<jobId>\`（attempt、收據、ID 對照、工作中文件），log 在 `.ps-runtime\sdoc-logs\`。

## 回報維護端

和 OpenCode 版相同：只回報結論碼（fs-doctor 代號、KNOW1／SUPP1／SPEC1／CLONE1／DOC1）與 enum 值，不貼路徑、物件名、hash。
另：使用 Claude Code 時，對話內容（含研究產出片段）會送到模型服務——能否用於機密資料依公司規範決定。

## 維護（給 AI 維護 session）

- 模型讀的檔規則同 OpenCode 版（只留規則、無日期／issue 編號／變更敘述；`ps-agent-doc-lint` 也掃 `claude-code/`）。
  改 OpenCode 版的規則時，同一條改動要落到 Claude Code 版對應檔（只換機制用語）。
- 改完依序：`ps-spec.ps1 -Doctor -WriteGenericManifest` → `tests/test-claude-variant.ps1 -WriteGenericManifest` →
  `ps-fs-doctor.ps1 -WriteManifest`（兩份搬運 manifest 一起重生）→ 全部測試（含 `test-claude-variant.ps1`）。
- 真 CLI 端到端（花 API 費用，手動）：`node tests/claude-code/run-e2e.mjs [--model haiku|sonnet]`。
