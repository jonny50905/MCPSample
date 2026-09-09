# HANDOFF — PeopleSoft 知識庫分析框架（2026-09-02 交接）

> 給下一個 session（或明天的自己）。開發分支 `claude/peoplesoft-framework-handover-0u6b5g`，
> HEAD 見 `git log -1`。本檔在 manifest 範圍外，不需搬到公司機。

## 0. 一句話現況

大領域（67 個 NN 檔）的稽核在單一 session 內撞 context 上限（auditor 子代理、單檔 37 列即爆），
已改成**分批稽核**（L107）：外環 manifest → 每 session K 檔 → part 檔不變量發收據 → 收據齊備由外環
合併 90-audit.md。第一次實跑失敗在「模型 exit 0 卻不寫任何檔」（b0/b1/b2 零產出），已把批次指令
改掛回實證能寫檔的 `ps-deep-research`（80196ee），**待管理者搬檔重跑驗證**。職缺領域（第二領域）
政策定案 CUSTOM_FIRST、已入佇列，等大領域告一段落再開。

**接手追記（2026-09-02，第二個 session）**：manifest 在 80196ee 後未重生——c6dae63 新增的
`scripts/tests/test-auto-loop.ps1` 落在 fs-doctor 的搬運集合（scripts 全樹）內卻不在 manifest、且無 BOM。
已補 BOM、以 `ps-fs-doctor -WriteManifest` 重生為 55 檔；測試組在 pwsh 7.4.6（Linux）實跑
**全部情境 PASS**（98 個 Assert）。§1 步驟 1 已改為 5 檔＋核對欄。程式碼零改動。
其後前一 session 又推 ab1ee40（分批稽核 K 改 AIMD：每圈從 `-AuditBatchSize` 重新起算，圈內整批全收據
→K 翻倍至上限、零收據且有寫檔→對半；修「台帳持久＝K 永遠 1、65 檔跑 65 個 session」）——
本 session 已 pull、逐行讀過、測試組在 ab1ee40 上重跑全 PASS。**同一分支目前有兩個維護 session 在推**，
push 前先 `git pull`。

**追記（2026-09-03，oracleMCP 連線根因）**：管理者三個實驗定案 oracleMCP 連線是 server 全域單例
（誰 disconnect 全員斷線；L109、SOP-12 補述）。已改模型側契約：cookbook 生命週期「不得 disconnect、
connect 冪等」、三個 flow agent 同步、四個 subagent tools 表硬性 `"oracleMCP_disconnect": false`（ps-auditor 也在內）、會查 oracleMCP 的委派維持 ≤ 3＋首個先單獨派（曾短暫壓到 1，已恢復）（ps-audit-batch／ps-audit／
ps-deep-research／ps-audit-orchestrator）、`.gitignore` 補 audit-parts。**ps-auto-loop.ps1 一行未動**
（外環斷路器草案留解凍後，見 L109「有意不做」；立即緩解可加 `-AuditBatchesPerCycle 4`）。
搬運清單見 §1 步驟 1a。功能分支 `claude/issue-17-legacy-contract-phase1` 已 merge 本修正並另改
ps-contract-batch／ps-contract-verify。

**追記（2026-09-04，issue #23）**：新領域 tier 1 只剩「一槍」的根因＝tier 1 相位與畢業門只看 CoverageOnly
缺料、把未做的原始調查項當補強項（L110）。修法：`ps-auto-loop.ps1` 加 `Get-ResearchDebt`／
`Test-ResearchScopeOk`（原始調查項＋D 項＝research 債；A／U 不算；流程標籤不算），相位 `債>0 → research`、
畢業門 RESEARCH_SCOPE_OK、進度尺加債；`ps-graduation.ps1` GateVersion 3→4（誤發的 tier 1 收據作廢，
ps-auto-all 會重新 RUN）；test-auto-loop 情境 27。搬運見 §1 步驟 1a。**這是解凍後第一次動 auto-loop**。

**追記（2026-09-04，issue #24 導覽路徑）**：管理者問「系統有沒有列出 PeopleSoft menu path 的能力」——
盤點結論：**只有 technical menu**（cookbook §2e 的 PSMENUITEM 三欄），**沒有 Portal Registry**（PSPRSMDEFN 全庫零命中），
但模板必填「選單路徑」、contract 線又有 `menuPath` 必填 kv，於是模型拿技術選單串成「Recruiting > Use > X」（L111）。
修法（#24 主張逐條對抗驗證後施工）：cookbook §2e／§4 正名＋新 §2k（2k-0 欄位驗證先行，全部**待公司機驗證**）；
mcp-tool-contracts 新角色 `ps_get_navigation_entries`＋§3 值域；subagent-report-contract 硬規則 3a＋兩個選填陣列；
function-detail-template 功能定位拆「### 導覽入口」「### Technical Menu」；ps-ui-flow（agent＋SKILL）接導覽職責；
ps-security-flow／ps-metadata-flow／ps-orchestrator／ps-business-explain／ps-auditor（三個 FAIL 原因）／ps-deep-research 規則；
ps-doc-lint 兩條確定性規則（美工類，tier 1 不擋）＋`[導覽]` 工單＋auto-loop 手術 prompt 補型別；test-auto-loop 情境 28。
上線程序見 SOP-19。功能分支另改 contract 線（menuPath→technicalMenu、導覽表加入口型／可見性、schema／vocabulary 升版）。
**審查追記（同日）**：25 個 opus agent 對抗審查後補強（L111 末段列表）——lint 寬鬆路徑式／流程箭頭豁免／`AUTHORIZED_FOR_CONTEXT` 字串判違規／
SINGLE_PATH_COLLAPSE 第三型／`### Technical Menu` 不參與判定；[導覽] 工單指紋剝 Kinds；cookbook §2k 補驗證與到期欄；模板加「CREF 物件名」欄；情境 28 共 17 判定。
**追記（2026-09-07）**：清除 ps-orchestrator／ps-deep-research 殘留的「一次只准一個」（L109 追記）；orchestrator 歸戶建議改分流（已有研究→`/ps-correct`，沒研究過才 `/ps-research`）。
**追記（2026-09-07，L112）**：模型檔清理——16 個 agent／skill／command／contract／template 檔移除 issue 編號、日期、審查／舊版／已廢止敘述與外環機制說明；新增 `scripts/ps-agent-doc-lint.ps1`（`-WriteManifest` 前置，擋這類內容進模型檔）；AGENTS.md 鐵律加一條；test-auto-loop 情境 29。
**追記（2026-09-07，issue #27／L113）**：Classic 導覽改為 profile 化＋canonical query——`customization-profile.yaml` 加 `navigation:`（surfaces CLASSIC_ONLY、identity MENU_COMPONENT、portal、labelLanguage ENG、hideFromNavValues、attrValType CLOB、verified）；cookbook 新 §2k-C（canonical＋結果映射＋0 列排查），2k-2／2k-3 降診斷、2k-3 隱藏旗標改正（CLOB／REFTYPE／值）；ps-ui-flow 3a 改「verified 就直接跑 canonical、原樣映射」；可見性新值 CLASSIC_NAV_VISIBLE（功能分支 vocabulary 3）；lint 讀 profile（CLASSIC_ONLY 不要求 surface gap 行）＋Portal 證據 regex 加 `FROM PSPRSMDEFN`；auditor 4a 改重跑 canonical；SOP-20；情境 28 調整、情境 30 canonical 文字守衛。**待公司機驗**：CONNECT_BY_ISCYCLE、PSPRSMDEFNLANG 鍵欄位、LINK 列是否帶 SEG、portal 名。
**追記（2026-09-07，issue #27／L113）**：Classic 導覽改為 profile 化＋canonical query——`customization-profile.yaml` 加 `navigation:`（surfaces CLASSIC_ONLY、identity MENU_COMPONENT、portal、labelLanguage ENG、hideFromNavValues、attrValType CLOB、verified）；cookbook 新 §2k-C（canonical＋結果映射＋0 列排查），2k-2／2k-3 降診斷、2k-3 隱藏旗標改正（CLOB／REFTYPE／值）；ps-ui-flow 3a 改「verified 就直接跑 canonical、原樣映射」；可見性新值 CLASSIC_NAV_VISIBLE（功能分支 vocabulary 3）；lint 讀 profile（CLASSIC_ONLY 不要求 surface gap 行）＋Portal 證據 regex 加 `FROM PSPRSMDEFN`；auditor 4a 改重跑 canonical；SOP-20；情境 28 調整、情境 30 canonical 文字守衛。**公司機已驗（同日）**：PORTAL_EXPIRE_DT 存在、LINK 列帶 SEG2（1039/1045）、EMPLOYEE 在、CONNECT_BY_ISCYCLE 可用；canonical 對已知 Component 回 1 可見／4 不可見。管理者定案 canonical 只回看得到的列（NAV_PATHS CTE＋`WHERE CLASSIC_VISIBLE = 1`），帶旗標版降為診斷形。
**追記（2026-09-07，issue #28／L114）**：oracleMCP 連線擁有權收攏到主 agent（嚴格版）——ps-orchestrator／ps-deep-research／ps-audit-orchestrator 的 tools 開 `oracleMCP_list_connections`＋`oracleMCP_connect`（run_sql／disconnect 仍關），派第一個要查 DB 的 subagent 之前先 list_connections→connect 一次；四個 subagent（ps-ui-flow／ps-metadata-flow／ps-ae-flow／ps-auditor）tools 加 `"oracleMCP_connect": false`，第一個 SELECT 直接發、遇未連線只回 `status=BLOCKED`＋`blockedReason=NOT_CONNECTED`（不 connect、不重試）；主 agent 收到 NOT_CONNECTED 重連一次＋重派一次。subagent-report-contract 新增 `blockedReason` 封閉值域（NOT_CONNECTED／ORACLE_MCP_DOWN／QUERY_TIMEOUT／SCHEMA_UNRESOLVED／TOOL_ERROR／NO_EVIDENCE／BUDGET_EXCEEDED；COMPLETE→NOT_APPLICABLE）。cookbook「連線生命週期」拆主 agent／subagent 兩段；「第一個先單獨派」規則整樹移除（≤3 併發保留）；SOP-12 追記；test-scenarios §7 手動回歸 R1～R7；test-auto-loop 情境 31（tools 權限＋文字守衛）。**待公司機驗**：`opencode.json` permission 是否放行主 agent 的 `oracleMCP_connect`；已連線再 connect 的回應是否為冪等。
**再追記（2026-09-07，issue #28 公司機回饋）**：主 agent 看得到 connect、看不到 list_connections——根因是 OpenCode 0.6.0～1.0.x 把 MCP 工具名的連字號改成底線（實際工具名 `oracleMCP_list_connections`），tools 表寫連字號對不上；1.1.30 起保留連字號。落點：三個主 agent tools 表改為底線拼法；`customization-profile.yaml` 加 `oracle.connectionName`（FILL_ME，**管理者本機回填 SQLcl 已儲存連線名**，之後 fs-doctor 報該檔 M 屬預期）；cookbook 主 agent 段第 1 步改「先 profile 後 list」；ps-ui-flow／ps-metadata-flow／ps-ae-flow／ps-auditor 硬規則段殘留的舊流程改為只回 BLOCKED(NOT_CONNECTED)；情境 31 加兩種拼法／profile 欄位／殘留守衛；test-scenarios §7 加 R0 工具可見性。
**再追記（2026-09-07，管理者定案）**：公司機 OpenCode 的工具名就是底線版——全樹一律寫 `list_connections`／`run_sql`，連字號拼法全部移除、不再兩種都開（三個主 agent tools 表只留 `oracleMCP_list_connections`；cookbook 第 0 步列工具名；SOP-12 再追記；test-scenarios §7；情境 31 加守衛擋連字號拼法回流）。
**再追記（2026-09-07，公司機回饋 2）**：主 agent 仍高機率不 connect——條件式規則（派第一個 DB 委派之前才 connect）模型常跳過。改為無條件開場動作：三個主 agent 加「第 0 步」（read profile → `oracleMCP_connect`，做完才准查 wiki／委派／作答；回「已連線」也算成功）；cookbook 主 agent 段、/ps-audit、/ps-audit-batch 措辭同步；情境 31 斷言三個主 agent 含「第 0 步」「無條件」、agent／command 無條件式 connect 殘留；test-scenarios §7 加 R8。
**再追記（2026-09-07，管理者定案 2）**：開場順序固定 `list_connections` → `connect`，不准跳過 list；profile `oracle.connectionName` 只用來在清單裡挑名字（有填且在清單裡用它，否則清單第一個）。三個主 agent 第 0 步、cookbook 主 agent 段、/ps-audit／/ps-audit-batch／/ps-contract-batch／/ps-contract-verify、profile 註解、test-scenarios R1／R8、情境 31（斷言第 0 步裡 list 在 connect 之前）同步。
**追記（2026-09-08，issue #29／L115）**：公司機（OpenCode 1.18.29）實測第 0 步仍是機率行為（更常 task 先派→NOT_CONNECTED）。
順序改由**執行期閘門**強制：新增 `.opencode/plugin/ps-oracle-preflight-gate.js`（OpenCode plugin，零外部相依，自動載入）——
per-session 狀態機 NEED_LIST→NEED_CONNECT→READY、每則訊息重置；`task` 目標為會查 DB 的 subagent（agent 檔 tools 表 run_sql 為開）
且未 READY → 擋下並回 `PS_ORACLE_PREFLIGHT_REQUIRED`（不執行、不改參數）；NOT_CONNECTED 回報→退回 NEED_CONNECT；oracleMCP 未掛載→退讓；
enforce／observe 兩模式；交易紀錄 `auto-loop-logs\ps-oracle-gate\<sessionID>.jsonl`。另發現 OpenCode 有 plugin 時啟動會等
`.opencode` 的 `@opencode-ai/plugin` 安裝結束（斷網實測 72 秒）→ 新增 `.opencode/.npmrc`（`offline=true`，2 秒）。
AGENTS.md「先查 wiki」改到第 0 步之後。原始碼（anomalyco/opencode v1.18.29）逐條對碼、issue 主張五處修正（`docs/design/oracle-preflight-gate-decision-memo.md`）。
驗證：情境 32（靜態）、`tests/oracle-gate/unit.test.mjs`（狀態機 5 組）、`tests/oracle-gate/run-e2e.mjs`（真 OpenCode 1.18.29 binary＋假 oracleMCP＋假模型，
headless 路徑 7 情境全 PASS、重複跑一致）；公司機回歸 `scripts/tests/test-oracle-gate-runtime.ps1`（SOP-21）。搬運見 §1 步驟 1b。
**再追記（2026-09-08，外部 review 四輪 → 退版重寫）**：review 對 a31c946 提兩個 Must（連線是全域單例、per-session READY 看不到別人的
connect／disconnect；analyzer 沒證每題都有 chat.message 重置）；之後三輪修法（a94a616→886d6e2）被判定偏離——跨行程影子狀態
（`connection-state.json`，topology 未證實）、失敗 ≥2 次與 `prt_` 的 fail-open、analyzer 豁免改寫了 acceptance criterion——指定回 a31c946 重寫。
`aa9e42c` 退版（樹狀態＝a31c946，歷史保留），再以**最小不變量**重寫：每則真實訊息 NEED_LIST→NEED_CONNECT→READY 才准派會查 DB 的
subagent；唯一例外＝目標沒有 Oracle 能力；oracleMCP 未掛載（即時查）退讓；其餘一律擋（無失敗次數放行、無 prt_ 退讓、無祖先放行、
無跨 session／跨行程協調）。只移植已證明安全的：turnId＝訊息 id、synthetic／同 id 不重置、task 入場快照、mcp.status 不快取、
多輪 e2e（run --session／serve／compaction）、analyzer 的 turnMismatch／turnInvariantViolations／PS 5.1 修正——**全部無豁免**
（未掛載期間放行的 DB task 照算違反，另標 standDowns）；SOP-12 舊敘述改現況；fs-doctor `-Force`。不移植：connection-state／epoch
（先做 SOP-21 步驟 9 的 topology 實驗 T1～T3 再設計）、event hook「already connected」（R16 驗完再定）、ps-auditor 拆能力（另案）。
驗證：單元 10 組、e2e 12 情境（真 OpenCode 1.18.29）、test-auto-loop 情境 32／33 全 PASS。細節 L115 追記、`docs/design/oracle-preflight-gate-decision-memo.md` §四。
**再追記（2026-09-08，外部 review 第二輪，對 d544ec3）**：review 以 hook-level 測試重現兩個時序缺口——上一題晚到的 connect 成功會替下一題
完成前置、上一題晚到的 NOT_CONNECTED 會作廢下一題已完成的前置；另指出 subagent 的 Oracle 權限是排除清單、analyzer 用 basis 字串篩能力會漏
unknown-agent 且零違規≠可用、MCP 未掛載退讓與不變量敘述矛盾、空輸出被當成功、「否則清單第一個」是靜默連錯 DB 的來源。第一批修法（不改核心
不變量）全部落地：plugin 入場快照＋callID 配對（after 用入場題目；stale／unknown 不前進；await 期間換題→擋；成功判定三態）、每列 dbCapable、
**oracleMCP 未掛載改為擋**（訊息走 ORACLE_MCP_DOWN 協定，不再有環境層退讓）、四個 DB subagent 的 Oracle 工具改允許清單（只開 run_sql）、
profile `oracle.connectionName` 必填且必須在清單裡（否則回「Oracle 連線未設定」，不挑清單第一個）、analyzer 加 callMismatch（before／after／export
parentID 歸屬）與安全／可用兩條驗收（-ExpectDbTask）。驗證：單元 14 組、e2e 14 情境（真 OpenCode 1.18.29；新增 empty-connect、stale-connect-serve）、
analyzer 對 14 份真 export 判定一致、test-auto-loop 262 判定全 PASS。第二批（連線生命週期改版：題目狀態／資源狀態分離、連線世代、owner、
DUAL 探測、集中復原、真 SQLcl repeated-connect 契約）另案。細節 L115 追記、memo §五。搬運見 §1 步驟 1b（**886d6e2 那批已搬的檔要整批重搬**）。
**再追記（2026-09-08，外部 review 第三輪，對 e0b1c75）**：review 判定「保留、小幅修正後接受第一階段」，11 個 hook-level 探測 7 過 4 重現：
G1 connect 目標只是模型規則（profile=HR_DEV 仍能 connect HR_UAT）、G2 同題復原後舊 task 晚回的 NOT_CONNECTED 作廢新 READY、G3 已 READY 後再
connect 失敗 READY 不作廢、G4 analyzer 把 BLOCKED／非 JSON 算成功。全部落地：connect 在執行前比對 profile（未填 → ORACLE_CONNECTION_NOT_CONFIGURED、
不一致 → ORACLE_CONNECTION_MISMATCH，工具不執行）；每次 connect 嘗試世代 +1 並作廢 READY、只由該次成功恢復；task 入場記世代、舊世代的
NOT_CONNECTED 不作廢新世代；task after 解析報告（reportStatus／blockedReason／childSessionID）、run_sql after 記 ok；analyzer 完成＝報告 COMPLETE
且子 session run_sql 成功。驗證：單元 18、e2e 17 情境（新增 wrong-target／not-configured／reconnect-fail）、analyzer 對真 export 一致、
test-auto-loop 273 判定。**公司機注意**：profile `oracle.connectionName` 現在是硬性條件——必須與 SQLcl 已儲存連線名完全一致，未填或不一致時
connect 根本不會執行；已填的值搬檔時不得被 FILL_ME 覆蓋。細節 L115 追記、memo §六、SOP-21 步驟 9 內網最小驗收表。
**再追記（2026-09-09，公司機實測「第 0 步常被略過」）**：搬完 b8e7aba 後主 agent 仍常不開線就直接派 subagent（閘門擋下、要求補做，
每題多一次來回）。管理者問為何開線要獨立一個第 0 步而不併進工作流——成立：獨立章節不是模型執行的計畫，工作流編號清單才是。兩層處置：
(1) 三個主 agent 檔移除獨立「## 第 0 步」章節，開線改為工作流編號步驟（orchestrator 第 2 步、deep-research 啟動與續跑第 0 項、
audit-orchestrator 第一動作第 1 項；名字仍叫第 0 步）；(2) 閘門在主 agent 的每一則真實使用者訊息後注入 synthetic 提醒 part（先 list→connect
（connection_name＝profile 值）→ 才准派會查 DB 的 subagent；沒有 oracleMCP_ 工具就回 ORACLE_MCP_DOWN），不擋、不查狀態，
env PS_ORACLE_GATE_REMINDER／profile oracle.preflightReminder 可關；plugin 自己 connect 在 1.18.29 不可行（沒有 plugin 呼叫工具的 API）。
驗證：單元 19、e2e 17 情境（每情境驗 export 的真實訊息帶提醒 part、模型請求看得到）、test-auto-loop 278 判定。公司機看 R22 與
`-AnalyzeAll` 的 blockedRuns 是否下降；診斷「沒做第 0 步」先看 jsonl 的 before task 列是 block（閘門有擋）還是 allow／沒有紀錄（沒載到）。
**再追記（2026-09-09，公司機實測第五輪：搬完 fbbb765 後兩件事）**：(1) 主 agent 回報「本次工具環境中沒有掛載 list_connections 以及 connect」
——公司機的 OpenCode 一遇到 tools 表的 `"oracleMCP_*": false` 就把整個 MCP 對該 agent 隱藏，後面的個別 true 救不回（沙箱 1.18.29 是最後匹配者優先，
版本行為不同；管理者拔掉萬用字元、逐工具寫 true／false 就正常）。三個主 agent＋四個 DB subagent 的 Oracle 片段全部改**逐工具明寫**（全關的
agent 保留萬用字元）；閘門載入時把「萬用字元 deny＋個別 true」混寫記到 `_plugin.log`（`wildcardDenyMix=[…]`＋WARN）；情境 31 擋回流。
(2) `list_connections` 把名稱與連線字串黏在一起回（`Name:ABCReadonlyConnect string: {…}`），模型讀成「ABCReadonlyConnect」、怎麼連都失敗。
管理者定案：**不呼叫 list_connections，直接 connect profile `oracle.connectionName`（原樣照抄）**。落點：三個主 agent 的開線步驟（失敗再 connect 一次；
仍失敗才 list 一次把原文附給管理者核對）、cookbook、/ps-audit、/ps-audit-batch、AGENTS.md、profile 註解；閘門不變量縮成 NEED_CONNECT→READY
（NEED_LIST 移除；list 的 after 只記錄）、擋下訊息／connect 目標錯誤／提醒 part 改「呼叫 oracleMCP_connect（profile 值原樣；不必先 list、不從清單挑名字）」；
analyzer 的 turnInvariantViolations 只看 connect→READY、preflight＝有 connect 成功、加 listCalls 觀察值（正常 0）；假 oracleMCP 的清單改仿真黏合格式。
驗證：單元 20、e2e 17 情境全 PASS（connect-first 改 list-first：多做的 list 不算前置也不擋路；放棄路徑 list 一次附原文）、analyzer 對 17 個 e2e export
判定一致（listCalls 只在 list-first／connect-fail／empty-connect／reconnect-fail 為 1）、test-auto-loop 全 PASS。公司機看 R23（`_plugin.log` 的
wildcardDenyMix=[]、模型看得到 connect＋list_connections）與 R24（正常題目零 list、connect 的 connection 欄＝profile 值原樣）。
**再追記（同日，公司機實測第六件）**：閘門失敗樣式 `ORA-\d{5}` 把 SQLcl connect 成功的回覆判成失敗（成功回覆的說明文字引用 ORA-nnnnn）→
閘門永遠不開。管理者定案移除該行、改認 `connection not (connected|established|found)`；單元加回歸（成功文字含 ORA 碼 → READY）。
搬運清單自此改表格（檔名＋raw 連結），不再給 curl（公司會擋）。

## 1. 管理者下一步（按序）

1. 搬 5 檔（核對欄：行數＝編輯器總行數，允許 ±1 行尾差異）：

   | 檔案 | 新增／修改 | 行數 | 備註 |
   |---|---|---|---|
   | `scripts/ps-auto-loop.ps1` | 修改（#24 手術 prompt [導覽] 型＋#24 手術 prompt [導覽] 型＋#27 Classic canonical） | 2329 | 存 UTF-8 with BOM；含 ab1ee40 的 K AIMD |
   | `.opencode/command/ps-audit-batch.md` | 修改（L112 清理＋L112 清理＋#28 連線歸主 agent＋開場無條件 connect＋list→connect 順序） | 109 | 掛 ps-deep-research（80196ee） |
   | `.opencode/agent/ps-audit-orchestrator.md` | 修改（L112 清理＋L112 清理＋#28 連線歸主 agent＋#28 工具名兩種拼法＋底線拼法＋開場無條件 connect＋list→connect 順序） | 152 | 備用、未掛載，但 manifest 要對 |
   | `scripts/tests/test-auto-loop.ps1` | 新增（新目錄 `scripts\tests\`＋情境 28＋情境 29＋情境 30＋情境 31＋情境 31 拼法守衛＋底線拼法＋開場無條件 connect＋list→connect 順序） | 675 | 存 UTF-8 with BOM；公司機以 `pwsh -NoProfile -File` 跑 |
   | `scripts/ps-transfer-manifest.json` | 修改 | 342 | 最後搬；搬完跑 `ps-fs-doctor` 應報 56 檔一致（其印出的基準 commit 欄是 cc14f32＝另一 session 本機值，本 repo 無此 commit；雜湊內容對應 ab1ee40，已逐檔核對） |
1a. oracleMCP 根因修正＋#23 research 債＋#24 導覽路徑（2026-09-03～04；若步驟 1 的 5 檔尚未搬，兩批一起搬；manifest 只搬最新）：

   | 檔案 | 新增／修改 | 行數 | 備註 |
   |---|---|---|---|
   | `.opencode/peoplesoft/oracle-query-cookbook.md` | 修改（生命週期＋平行規則＋#24 §2e／§4 正名、§2k＋L112 清理＋#27 Classic canonical＋#28 連線歸主 agent＋#28 工具名兩種拼法＋底線拼法＋開場無條件 connect＋list→connect 順序） | 636 | |
   | `.opencode/agent/ps-ui-flow.md` | 修改（生命週期＋#24 導覽職責＋L112 清理＋#27 Classic canonical＋#28 連線歸主 agent＋#28 硬規則段去舊流程＋底線拼法） | 142 | |
   | `.opencode/agent/ps-metadata-flow.md` | 修改（生命週期＋#24 授權≠導覽＋L112 清理＋#28 連線歸主 agent＋#28 硬規則段去舊流程＋底線拼法） | 110 | |
   | `.opencode/agent/ps-ae-flow.md` | 修改（生命週期＋#28 連線歸主 agent＋#28 硬規則段去舊流程＋底線拼法） | 92 | |
   | `.opencode/agent/ps-auditor.md` | 修改（tools 硬性 deny＋規則＋#24 三個 FAIL 原因＋L112 清理＋#27 Classic canonical＋#28 連線歸主 agent＋#28 硬規則段去舊流程） | 260 | |
   | `.opencode/agent/ps-orchestrator.md` | 修改（#24 路徑類問題委派＋作答紀律＋清除一次只准一個殘留、歸戶分流＋L112 清理＋#27 Classic canonical＋#28 連線歸主 agent＋#28 工具名兩種拼法＋底線拼法＋開場無條件 connect＋list→connect 順序） | 186 |  |
   | `.opencode/peoplesoft/report-templates/function-detail-template.md` | 修改（#24 功能定位拆 ### 導覽入口／### Technical Menu＋L112 清理＋#27 Classic canonical） | 111 |  |
   | `.opencode/peoplesoft/mcp-tool-contracts.md` | 修改（#24 ps_get_navigation_entries＋§3 值域＋L112 清理＋#27 Classic canonical） | 128 |  |
   | `.opencode/peoplesoft/customization-profile.yaml` | 修改（navigation 區塊：Classic 導覽環境事實＋oracle.connectionName＋底線拼法＋list→connect 順序） | 101 | 管理者依 SOP-20 核對 portal／labelLanguage 後把 verified 設 true；oracle.connectionName 本機回填（之後 fs-doctor 報此檔 M 屬預期） |
   | `.opencode/peoplesoft/subagent-report-contract.md` | 修改（#24 硬規則 3a＋兩個選填陣列＋L112 清理＋#27 Classic canonical＋#28 連線歸主 agent） | 169 |  |
   | `.opencode/peoplesoft/test-scenarios.md` | 修改（§7 oracleMCP 連線擁有權手動回歸 R1～R7＋R0＋底線拼法＋開場無條件 connect＋list→connect 順序） | 672 | 公司機手動跑；結果記 applied.md L114 |
   | `.opencode/skills/ps-ui-flow/SKILL.md` | 修改（#24 導覽語系義務＋Rules＋L112 清理） | 192 |  |
   | `.opencode/skills/ps-security-flow/SKILL.md` | 修改（#24 authorization ≠ navigation） | 62 |  |
   | `.opencode/skills/ps-business-explain/SKILL.md` | 修改（#24 五條硬規則＋輸出 2a＋L112 清理＋#27 Classic canonical） | 105 |  |
   | `scripts/ps-doc-lint.ps1` | 修改（#24 兩條導覽規則＋[導覽] 工單，美工類＋#27 Classic canonical） | 1612 | 存 UTF-8 with BOM |
   | `scripts/ps-agent-doc-lint.ps1` | 新增（L112 模型檔衛生檢查） | 47 | 存 UTF-8 with BOM；`ps-fs-doctor -WriteManifest` 前置 |
   | `scripts/ps-fs-doctor.ps1` | 修改（-WriteManifest 前置 agent 檔檢查） | 308 | 存 UTF-8 with BOM |
   | `AGENTS.md` | 修改（鐵律加模型檔衛生一條） | 82 | 根目錄，不在 manifest；opencode 每次 session 都讀 |
   | `.opencode/command/ps-audit-batch.md` | 修改（oracleMCP 委派 ≤ 3、首個先單獨派→#28 改主 agent connect＋L112 清理＋#28 連線歸主 agent＋開場無條件 connect＋list→connect 順序） | 109 | |
   | `.opencode/command/ps-audit.md` | 修改（≤ 3、首個先單獨派→#28 改主 agent connect＋L112 清理＋#28 連線歸主 agent＋開場無條件 connect＋list→connect 順序） | 72 | |
   | `.opencode/agent/ps-deep-research.md` | 修改（三處 ≤ 3＋#24 導覽入口填法＋清除一次一個殘留＋L112 清理＋#27 Classic canonical＋#28 連線歸主 agent＋#28 工具名兩種拼法＋底線拼法＋開場無條件 connect＋list→connect 順序） | 518 | |
   | `.opencode/agent/ps-audit-orchestrator.md` | 修改（≤ 3、首個先單獨派→#28 改主 agent connect＋L112 清理＋#28 連線歸主 agent＋#28 工具名兩種拼法＋底線拼法＋開場無條件 connect＋list→connect 順序） | 152 | |
   | `.opencode/peoplesoft/SOP.md` | 修改（只加 SOP-12 補述＋SOP-13 tier 1 門＋SOP-19＋SOP-20＋SOP-12 追記＋SOP-12 再追記＋底線拼法＋開場無條件 connect＋list→connect 順序） | 861 | |
   | `.opencode/peoplesoft/lessons/applied.md` | 修改（只加 L109＋L110＋L111＋L109 追記＋L112＋L113＋L114＋L114 追記＋底線拼法＋開場無條件 connect＋list→connect 順序） | 3230 | |
   | `scripts/ps-auto-loop.ps1` | 修改（#23：research 債＝相位＋畢業門＋進度尺＋#24 手術 prompt [導覽] 型＋#27 Classic canonical） | 2329 | 存 UTF-8 with BOM |
   | `scripts/ps-graduation.ps1` | 修改（GateVersion 3→4） | 191 | 存 UTF-8 with BOM；舊 tier 1 收據作廢屬預期 |
   | `scripts/tests/test-auto-loop.ps1` | 修改（情境 27＋情境 28 共 17 判定＋情境 29＋情境 30＋情境 31＋情境 31 拼法守衛＋底線拼法＋開場無條件 connect＋list→connect 順序） | 675 | 存 UTF-8 with BOM |
   | `scripts/ps-transfer-manifest.json` | 修改 | 342 | 最後搬；fs-doctor 應報 56 檔一致（commit 欄＝產生時 HEAD，早一步屬預期） |

   `.gitignore`、`HANDOFF.md`、`README.md` 不在搬運集合。
1b. issue #29 執行期閘門（2026-09-08～09；1／1a 尚未搬的一起搬，manifest 只搬最新。**已依 886d6e2／d544ec3／e0b1c75／b8e7aba／fbbb765 搬過的檔要重搬**——
    閘門、七個帶 Oracle 的 agent 檔（tools 逐工具明寫）、兩個 command、cookbook、profile 註解、SOP、applied、test-scenarios、test-auto-loop、
    runtime 回歸腳本、manifest 都改了）：

   | 檔案 | 新增／修改 | 行數 | 備註 |
   |---|---|---|---|
   | `.opencode/plugin/ps-oracle-preflight-gate.js` | 新增（新目錄 `.opencode\plugin\`；不變量只剩 connect→READY、list 只記錄、connect 目標執行前比對／嘗試作廢 READY／同題世代／報告解析／run_sql 三態／第 0 步提醒注入／wildcardDenyMix 警告） | 733 | 存 UTF-8；OpenCode 自動載入；載入證據＝`auto-loop-logs\ps-oracle-gate\_plugin.log` 的 loaded 行（含 reminder=on、wildcardDenyMix=[]） |
   | `.opencode/.npmrc` | 新增 | 4 | `offline=true`，不可省（否則有 plugin 時每次啟動多等到安裝重試逾時）；啟動仍多等 70 秒才在全域設定目錄再放一份（SOP-21 步驟 1） |
   | `.opencode/peoplesoft/customization-profile.yaml` | 修改（oracle.preflightGate: enforce；preflightReminder: on；connectionName 註解改「直接 connect 這個名字、不 list、原樣、閘門執行前比對」） | 111 | 本機已回填 FILL_ME 者只合併 oracle 區塊的註解、`preflightGate`、`preflightReminder`（fs-doctor 報此檔 M 屬預期）；**connectionName 必須與 SQLcl 已儲存連線名完全一致（實際連得上的那個名字，不是 list_connections 黏在一起的字串），否則所有 connect 在執行前被擋** |
   | `.opencode/agent/ps-ui-flow.md` | 修改（Oracle 逐工具明寫：list／connect／disconnect／run_sqlcl false、run_sql true；不再用 oracleMCP_* 萬用字元） | 144 | 上一批的 `"oracleMCP_*": false` 寫法在公司機會隱藏整個 MCP，**必須重搬** |
   | `.opencode/agent/ps-metadata-flow.md` | 修改（同上） | 112 | 必須重搬 |
   | `.opencode/agent/ps-ae-flow.md` | 修改（同上） | 94 | 必須重搬 |
   | `.opencode/agent/ps-auditor.md` | 修改（同上） | 262 | 必須重搬 |
   | `.opencode/agent/ps-orchestrator.md` | 修改（tools 逐工具明寫；工作流第 2 步改直接 connect profile 值、不先 list、失敗兩次才 list 附原文） | 184 | 必須重搬 |
   | `.opencode/agent/ps-deep-research.md` | 修改（同上；「啟動與續跑」第 0 項） | 517 | 必須重搬 |
   | `.opencode/agent/ps-audit-orchestrator.md` | 修改（同上；「第一動作」第 1 項） | 151 | 必須重搬 |
   | `.opencode/command/ps-audit.md` | 修改（開場直接 connect、不先 list 措辭） | 72 |  |
   | `.opencode/command/ps-audit-batch.md` | 修改（同上） | 109 |  |
   | `.opencode/peoplesoft/oracle-query-cookbook.md` | 修改（主 agent 段第 1～2 步：直接 connect profile 值原樣、不先 list；list 只在兩次失敗後附原文） | 638 |  |
   | `.opencode/peoplesoft/SOP.md` | 修改（SOP-12 現況＋再追記（萬用字元隱藏整個 MCP／清單黏合）＋SOP-21 整段改 connect-only：配對／三態／未掛載也擋／connect 目標強制／嘗試作廢／世代／完成定義／第 0 步兩層處置／R17～R24／內網最小驗收表／topology 實驗） | 859 |  |
   | `.opencode/peoplesoft/lessons/applied.md` | 修改（L115＋五輪追記） | 3226 |  |
   | `.opencode/peoplesoft/test-scenarios.md` | 修改（§7 R0／R1／R5／R8 改寫；§7a R9～R24） | 696 |  |
   | `.opencode/peoplesoft/README.md` | 修改（目錄結構的 plugin 說明改 connect-only） | 308 |  |
   | `scripts/tests/test-auto-loop.ps1` | 修改（情境 31 逐工具明寫＋混寫守衛＋開線直接 connect；情境 32 無 NEED_LIST／wildcardDenyMix；情境 33 list 不算前置） | 850 | 存 UTF-8 with BOM；情境 32 沒有 node 或沒搬 `tests/` 時跳過單元測試（正常） |
   | `scripts/tests/test-oracle-gate-runtime.ps1` | 修改（turnInvariantViolations 只看 connect→READY；preflight＝有 connect 成功；listCalls 觀察值） | 442 | 存 UTF-8 with BOM；用法見 SOP-21 |
   | `scripts/ps-fs-doctor.ps1` | 修改（Get-TransferFiles 加 -Force、排除 OpenCode 安裝痕跡） | 312 | 存 UTF-8 with BOM；上一批已搬者不必重搬 |
   | `scripts/ps-transfer-manifest.json` | 修改 | 359 | 最後搬；fs-doctor 應報全部一致（commit 欄＝產生時 HEAD，早一步屬預期） |
   | `AGENTS.md` | 修改（第 0 步改直接 connect profile 連線名、不先 list；plugin 零相依鐵律；未掛載也擋） | 93 | 根目錄，不在 manifest；opencode 每次 session 都讀 |

   `tests/oracle-gate/*`（沙箱單元／e2e 測試組）與 `docs/design/oracle-preflight-gate-decision-memo.md` 不搬。
   搬完照 SOP-21 步驟 2～5 驗：`_plugin.log` 有 loaded（reminder=on、wildcardDenyMix=[]）→ 快篩（一題＋同視窗第二題；看 R16 已連線再 connect、
   R17／R23 工具可見性、R18 連線名設定錯誤、R19 正向驗收反例、R20 再 connect、R21 一開多用、R22 提醒注入、R24 不 list 直接 connect）→ 同一視窗互動 20 題後 `-AnalyzeAll`（安全五項無豁免，
   oracleMCP 掛載中；blockedRuns 應明顯低於注入前）→ B1／B2／B3 各 30 次（B1 另判每 session ≥1 個「報告 COMPLETE 且子 session run_sql 成功」
   的 DB task）；再做步驟 9 的內網最小驗收與步驟 10 的 topology 實驗 T1～T3（R15），結果回報維護 session。
2. 清殘留：`auto-loop-logs\<領域>\audit-ledger.json`、`docs\ps-research\<領域>\audit-parts\`。
3. 重跑 `ps-auto-loop.ps1 -Domain <領域> -Tier 2`。
4. **b0 結束時看 `audit-parts\domain.md` 有沒有出現**：有＝agent 層病因確認已修；沒有＝看 log
   新增的 `out>` 三行（模型最後說的話）——剩下兩種可能：模型印表沒 write（新版 stdout 回收會過）、
   或 `write` 被 opencode.json 的 permission `ask` 規則擋（建議 doom_loop ask→deny，見 L60 二次修正；
   但依 L60 實測 headless 的 ask 是**阻塞到逾時**，不會 exit 0——b0 實案 12 分鐘 exit 0，此假說先驗不成立，
   剩「agent 未被認到」（80196ee 已消滅變數）與「印表沒寫」（stdout 回收已接住）兩種）。
5. 成功後觀察：「稽核第 i 批…收據 x/y」累積、「稽核 BLOCKED」（若有，先試 `-AuditEvidencePageSize 5`）、
   「稽核輪次 N 合併完成」。首輪後 lint 若報「未稽核」列＝有檔 BLOCKED，不得畢業。
6. 大領域收尾：查無全量抽驗蓋章（旗標由外環翻）、待人工SQL 回填、畢業（GraduationGateVersion 4，#23 後舊 tier 1 收據作廢重驗，
   舊收據作廢屬預期）。
7. 職缺領域：`ps-auto-loop.ps1 -Domain 職缺 -Tier 1`（一次只跑一個領域；oracleMCP 單通道）。

## 2. 本 session 落地的機制（L103～L107，全在 `.opencode/peoplesoft/lessons/applied.md`）

| 教訓 | 一句話 | 關鍵碼 |
|---|---|---|
| L103 | 守衛的三個素樸假設：指紋剝行號、[附錄] 形狀守衛、NN 檔＋歸檔檔破壞防衛、取項順序、[回灌] 陳舊壓下、不適用節、ChunkId 誤判修正、查無抽驗落後警告 | auto-loop `Get-OrderFingerprint`／`Invoke-NnDestructionGuard`；lint `[附錄]`／`-FixHeadings` |
| L104 | Domain Gate：任務 C 只是候選產生器，DOMAIN_ROOT 才准成 D；`-MaxNewDPerAudit` 熔絲 | auditor 結構化候選；deep-research 稽核模式步驟 3 |
| L105 | 歸檔所有權外環化：模型只打勾，`Invoke-ChecklistArchiveCommit` 唯一歸檔者；`Invoke-ArchiveDedup` 降為 crash recovery | auto-loop；ps-audit／deep-research 歸檔段 |
| L106 | context 溢出先分端再修：auditor 二次定位頁數上限、`FailureKind` 標籤、lint `-EvidenceStats` | ps-auditor；progressive-source-retrieval §5.1 |
| L107 | 稽核分批化：manifest／檔級收據／part 不變量／外環合併／溢出＝容量事件（K 對半、頁對半、BLOCKED→未稽核→lint 違規） | auto-loop 分批稽核塊（`Invoke-AuditRound` 等）；`ps-audit-batch` 指令 |

外部協作者 issue #12／#13／#22 皆已逐條對碼驗證並回帖（成立處落地、分歧處註明理由）。
分批稽核的完整設計備忘：`docs/design/audit-batching-decision-memo.md`。

## 3. 操作知識（不看對話也要知道的）

- **搬運**：公司網路封鎖 git，人工從 GitHub Raw 複製；`.ps1` 存 UTF-8 with BOM；搬完跑
  `scripts/ps-fs-doctor.ps1` 做 manifest 雜湊對照；維護端每批 push 前 `-WriteManifest`（公司機不跑）。
  **每次 push 之後都要給管理者搬運清單**（管理者定案）：以上一次已搬的 HEAD 為基準列 `git diff --name-only` 中屬搬運集合的檔，
  **用表格：檔名＋GitHub raw 連結（釘在本次 HEAD）＋備註**；**不要給 curl 或任何下載指令（公司會擋）**，管理者是點連結後人工複製；
  另附 profile 只合併不覆蓋的提醒、搬完的驗證指令；不在搬運集合的檔（HANDOFF／README／docs／tests）不列。
  公司機沒有 pwsh，指令一律寫 `powershell -NoProfile -ExecutionPolicy Bypass -File …`。
- **模型檔衛生**：`scripts/ps-agent-doc-lint.ps1`（`-WriteManifest` 的前置）擋 issue 編號／日期／變更敘述進模型讀的檔；
  規則見 AGENTS.md 鐵律（L112）。
- **研究產出 `docs/ps-research/**` 是公司機密**：只進內部 git，本 repo 不含。本機 `opencode.json`
  含公司主機名，不進 repo。
- **台帳與其刪除語義**（都在 `auto-loop-logs\<領域>\`）：
  `surgery-ledger.json`（手術工單 attempts/BLOCKED，處理完刪＝放行）、
  `audit-ledger.json`（分批稽核檔級收據，輪次合併後自動歸檔為 `audit-r<N>.done.json`；系統性故障後刪＝重置）、
  `reconcile-restored.txt`（復活斷路器）。`docs\ps-research\<領域>\audit-parts\` 是分批稽核的暫存，
  合併後自刪。
- **主要參數**（ps-auto-loop.ps1）：`-Tier 1|2`、`-AuditBatchSize 6`（每圈起算值＝AIMD 上限，ab1ee40）、`-AuditEvidencePageSize 10`
  （唯一尚未實測校準的參數；實測 Evidence 列數最大 37／p95 26／中位 12）、`-AuditBatchesPerCycle 0`、
  `-AuditBatchTimeoutMin 60`、`-MaxNewDPerAudit 10`、`-SurgeryBatchSize 7`、`-MaxSurgeryPerCycle 3`。
- **log 訊號詞彙**：「排水圈」「本批解決 N 筆（身分尺）」「手術停滯 BLOCKED」「破壞防衛」
  「歸檔 commit（外環）」「跨檔同文去重」「容量事件：CONTEXT_OVERFLOW」「批次 K 減半為／升為」「稽核第 i 批…收據 x/y」
  「稽核 BLOCKED」「稽核輪次 N 合併完成」「本輪稽核新增 D 項 N 筆 > 上限」。
- **cmd 傳遞限制**：session prompt 禁半形雙引號與 `> < & | % ^`；findstr 對 UTF-8 中文不可靠，
  一律 `powershell Get-Content -Encoding UTF8`。
- **閘門測試（#29）**：`node --test tests/oracle-gate/unit.test.mjs`（狀態機 20 組）；`OPENCODE_BIN=<binary> node tests/oracle-gate/run-e2e.mjs`
  （真 OpenCode＋假 oracleMCP＋假模型，17 情境含 `list-first`／`multi-turn-serve`／`compaction-serve`／`stale-connect-serve`／`connect-fail`／
  `wrong-target`／`reconnect-fail`；binary 由
  `npm pack opencode-linux-x64@1.18.29` 取得；`tests/oracle-gate/README.md`）。改 plugin 必跑兩者；改 agent 檔 tools 表也要跑
  （DB subagent 判定從 tools 表推導）。沙箱要點：OpenCode 用 `PWD` 決定專案目錄；`serve` 啟動後第一個請求可能掛住（執行器 20 秒逾時重試）；
  plugin 內不得出現 connection-state／epoch／prt_／失敗放行／祖先查詢（情境 32 守衛），analyzer 不得有豁免。
- **測試**：`pwsh -File scripts/tests/test-auto-loop.ps1`（28 個真實函式 AST 抽取、情境 27 含 #23、
  含 lint fixture）。改 auto-loop／lint 後必跑。

## 4. 未決與風險

- 分批稽核「模型不寫檔」的真因未定（agent 未被認到／印表沒寫／write 被 ask 擋）——重跑一次即定案。
- `-AuditEvidencePageSize` 未校準；serving 端 context 真值不可得，靠自校準（溢出對半）。
- Domain Gate 只擋新增，存量 67 檔內的依附／域外物件不回溯清洗（人工 scope review 可選）。
- 收據證明「parent 寫的數字通過不變量」，不證明「子代理真跑過」——與現況同，未新增風險。
- 文件漂移（下一波有其他改動時一併搬，不為此單獨搬大檔）：`ps-deep-research.md:251` 仍寫
  「ps-audit-batch（agent ps-audit-orchestrator）」，80196ee 後實掛 ps-deep-research（僅註解性文字，
  該節對批次指令本就不適用）；`SOP.md` 未收 L104～L107 的操作知識（台帳刪除語義、分批稽核參數、
  log 訊號詞只在本檔 §3，而本檔不搬公司機）——建議下一波以「只加不刪」補一節進 SOP。
- 閘門（#29）待公司機驗：真 SQLcl `connect`／`list_connections` 的成功回覆是否命中 FAILURE_PATTERNS（誤判會讓閘門永遠不開——
  jsonl 看 `ok:false`＋`failureMatch`）；「已連線再 connect」是正常回覆還是 isError（R16：isError 時閘門那題不會開，驗完才決定要不要接
  event hook）；互動 TUI 的 task／turn hook 覆蓋率（`-AnalyzeAll` 四項＝0）；`.npmrc offline` 是否真的讓啟動不再多等（仍多等 → 全域目錄再放一份）；
  **topology 實驗 T1～T3**（SOP-21 步驟 9／R15）：兩個 opencode 行程是否共用同一條 SQLcl 連線、同行程兩個 session 是否共用、oracleMCP type——
  共用連線防護（review Must #1）等這三個結果再設計，閘門目前 READY 是 per-session、看不到別的 session／視窗的 connect／disconnect。
  已知限制：同回合中途斷線閘門看不到（靠 NOT_CONNECTED 退回）；DB 連不上時 ps-auditor 的純 chunk 任務也會被擋（第 0 步規則本就如此）；
  command 的 agent 若是 subagent（目前沒有）被擋時整個 prompt 以錯誤結束（fail-closed）。
- 舊掛起：已畢業領域貼 U 項工單；PENDING_MANUAL 人工 SQL（SOP-2 第 4 階）；`-GitCommit` 觀察期
  結束後恢復；畢業後端到端測試；opencode.json 的 doom_loop ask→deny。
