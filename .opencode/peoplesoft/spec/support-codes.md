# 結論碼與 drill tuple（KNOW1／SUPP1／SPEC1）

三個 CLI 家族每個動詞的**最後一行**都是唯一的結論碼；上面的內容只在本機看。結論碼**不含**路徑、檔名、物件名、hash、requestId。
形狀：`<家族>1-<stage>-<code>[-<count>]`，regex `^(KNOW|SUPP|SPEC)1-\d-\d\d(-\d+)?$`。
公司機回報只回結論碼、drill tuple 與 PASS／FAIL；`.ps-private`、template／checklist 原文、NN 內容一律不出公司。

## KNOW1（scripts/ps-knowledge.ps1）

| stage | code | 意義 | exit |
|---|---|---|---|
| 1 rebuild | 01 | OK（三檔已原子替換） | 0 |
| 1 rebuild | 02 | PUBLISH_DEFERRED（目標被別的行程開著，舊索引保留） | 1 |
| 2 check | 01 | CURRENT | 0 |
| 2 check | 02-`<n>` | STALE，n＝變動檔數（檔名寫在 auto-loop-logs/knowledge-doctor.txt） | 1 |
| 2 check | 03 | MISSING（先 -Rebuild） | 2 |
| 3 find | 01-`<n>` | HIT，n＝命中筆數 | 0 |
| 3 find | 02 | NONE | 0 |
| 4 slice | 01 | OK | 0 |
| 4 slice | 02 | NOT_FOUND（檔或節不存在） | 2 |
| 9 usage | 01 | BAD_ARGS | 2 |

## SUPP1（scripts/ps-supplemental.ps1）

| stage | code | 意義 |
|---|---|---|
| 1 submit | 01 | CREATED（新 request 檔） |
| 1 submit | 02 | PENDING（同 need 已有未終局 request；不重送） |
| 1 submit | 03-`<i>` | TERMINAL，i＝既有終局 outcome 序號（RESOLVED=1／PARTIAL=2／UNRESOLVED=3／OUT_OF_SCOPE=4／SUPERSEDED=5）；要新世代用 -Resubmit |
| 1 submit | 04-`<n>` | INVALID，n＝驗證錯誤數（未知欄位／值域／文法） |
| 1 submit | 05 | ROUTING_REQUIRED（目標無 NN 且無 -DomainHint） |
| 2 status | 01-`<n>` | OK，n＝列出的 request 數 |
| 3 run | 01-`<n>` | DONE，n＝本次發布的 result 數（由 ps-auto-loop -SupplementalOnly 迷你圈印，exit 4） |
| 3 run | 02 | NOTHING（迷你圈無待處理、無派工；exit 4） |
| 4 result | 01-`<layer>` | FOUND，layer＝完成層（1 RESEARCHED／2 AUDITED／3 GRADUATED／4 PROJECTED） |
| 4 result | 02 | NONE（尚未發布 result） |
| 4 result | 03 | NOT_RESEARCHED（result 存在但 outcome 非 RESOLVED／PARTIAL） |
| 9 usage | 01 | BAD_ARGS |

exit：0＝完成；2＝參數、驗證、路由錯（1-04／1-05／9-01）。

## SPEC1（scripts/ps-spec.ps1）

stage：0 integrity／1 pack／2 plan／3 dispatch／4 accept／5 knowledge／6 render／7 gate／8 mapping／9 usage。責任方見 troubleshooting-matrix.md。

| stage | code | 意義 | exit |
|---|---|---|---|
| 0 | 01-`<n>` | GENERIC_MODIFIED：generic 集合（scripts/ps-spec*.ps1、.opencode/peoplesoft/spec/**、worker agent／command）有 n 個檔與 generic.manifest.json 不符（缺／改／多） | 1 |
| 0 | 02 | MANIFEST_MISSING：generic.manifest.json 不存在（維護端 -Doctor -WriteGenericManifest） | 1 |
| 0 | 03 | OK：generic 完整（-Doctor 無 -Drill） | 0 |
| 0 | 04 | MANIFEST_WRITTEN（-WriteGenericManifest） | 0 |
| 0 | 05-`<n>` | DRILL：印了 n 行 tuple（-Drill） | 0 |
| 1 | 01 | VALID（結構合法且 reviewedVersion＝packVersion） | 0 |
| 1 | 02 | NOT_FOUND：pack 目錄或 pack.json 不存在 | 2 |
| 1 | 03-`<n>` | INVALID：n 個驗證錯誤（未知欄位／ID 重複／checklist 未引用／slot 與模板標記不對應／factKind、property、context 不在目錄／依賴成環／required 非 bool） | 1 |
| 1 | 04 | TEMPLATE_MISSING | 1 |
| 2 | 01-`<n>` | PLANNED：新 plan 已寫（plans/&lt;planHash&gt;/plan.json），n＝COMPOSE 單位數 | 0 |
| 2 | 02-`<n>` | PLAN_REUSED：planHash 未變（同輸入） | 0 |
| 2 | 03 | IDENTITY_NOT_FOUND：索引中沒有以該 Component 為主物件的 NN（給 -DomainHint 可改為提交 KnowledgeNeed → 5-01） | 1 |
| 2 | 04-`<n>` | IDENTITY_AMBIGUOUS：n 個領域都有該 Component 且等級平手；給 -DomainHint | 1 |
| 2 | 05 | HINT_MISS：-DomainHint 的領域沒有該 Component 的 NN | 1 |
| 2 | 06 | UNSUPPORTED（plan finding；requirement factKind 為 UNSUPPORTED） | — |
| 2 | 07 | JOB_WRITE_DEFERRED：job.json 被別的行程開著 | 1 |
| 2 | 08 | PACK_CHANGED：pack contentHash 與 plan 不符（重跑 -Plan；只改 slot／模板＝bindingHash 不觸發） | 1 |
| 3 | 01-`<n>` | READY：所有單位都有有效收據，n＝收據數（phase READY） | 0 |
| 3 | 02-`<n>` | DISPATCHED：達 -MaxSessions，尚有 n 個可派單位 | 0 |
| 3 | 03 | SLOT_BUSY：session-slot 互斥鎖被另一個外環占用 | 1 |
| 3 | 04-`<n>` | SESSION_FAILED：session 未健康結束（逾時／exit≠0／prompt 不安全），不記 attempt | 1 |
| 3 | 05 | NO_OPENCODE：PATH 找不到 opencode shim | 2 |
| 3 | 06 | NO_PLAN：先 -Plan | 2 |
| 4 | 01 | ACCEPTED（verdict；收據已寫） | — |
| 4 | 02 | INVALID（verdict；計入 attempt；原因碼見下） | — |
| 4 | 03-`<n>` | BLOCKED：n 個單位 attempts≥2 仍不合格（或不可拆的容量事件），其餘單位已派完 | 1 |
| 4 | 04-`<n>` | SOURCE_CHANGED：input.json 快照與現況不符（session 期間來源改動、或 plan 過期）——拒收、不記 attempt、重跑 -Plan | 1 |
| 4 | 05 | CAPACITY_SPLIT（verdict；>150 行或 JSON 洩漏；不記 attempt；已寫 splits/） | — |
| 4 | 06 | BLOCKED_CAPACITY（verdict；≤1 條目仍超限，不可拆） | — |
| 5 | 01-`<n>` | WAITING_KNOWLEDGE：n 個 need 已提交／等待補研究 result（重跑 -Run 無新 result＝no-op） | 0 |
| 5 | 02 | SUBMITTED（plan 摘要用） | — |
| 5 | 03 | RESUBMITTED（既有 result 但 hash≠hashAfter 且事實仍缺 → -Resubmit 新世代） | — |
| 5 | 04-`<n>` | WAITING_AUDIT：result RESOLVED／PARTIAL 但等級低於 evidencePolicy——不重送，等下一輪稽核 | 0 |
| 5 | 05-`<n>` | BLOCKED_KNOWLEDGE：result UNRESOLVED／OUT_OF_SCOPE，或 hash＝hashAfter 仍抽不出事實 | 1 |
| 5 | 06-`<n>` | REPLAN_REQUIRED：等待中的 need 已有新 result／已過稽核，重跑 -Plan 重新抽取 | 1 |
| 5 | 07-`<n>` | ROUTING_REQUIRED：need 無法路由（目標無 NN 且無 DomainHint） | 1 |
| 5 | 08-`<n>` | SUBMIT_INVALID：need 未通過補研究驗證 | 1 |
| 6 | 01 | RENDERED：outputs/&lt;generation&gt;/{spec.md,trace.md,gate.json} 與 current.json 已寫（重跑 byte 相同） | 0 |
| 6 | 02-`<n>` | SOURCE_CHANGED：render 前重驗 n 個 sourceRef／收據指紋不符——current.json 不換；重跑 -Plan／-Run | 1 |
| 6 | 03 | NO_PLAN | 2 |
| 6 | 07 | PUBLISH_DEFERRED：輸出檔被別的行程開著 | 1 |
| 7 | 01 | SPEC_COMPLETE | 0 |
| 7 | 02-`<n>` | SPEC_PARTIAL：n 個 finding（見 7-1x／7-2x） | 1 |
| 7 | 03-`<n>` | BLOCKED：required 且 applicable 的 requirement 有 BLOCKED／BLOCKED_CAPACITY／BLOCKED_KNOWLEDGE | 1 |
| 7 | 11 | REQUIRED_MISSING（finding：無 fact／無收據且非等待中） | — |
| 7 | 12 | CARDINALITY（finding：ONE≠1，或 ALL_DISCOVERED 而 closure 非 COMPLETE） | — |
| 7 | 13 | GRADE_BELOW_POLICY（finding） | — |
| 7 | 14 | EVIDENCE_UNRESOLVED（finding：證據參照不可解或片段寫 UNRESOLVED，a＝筆數） | — |
| 7 | 15 | UNKNOWN_DEBT（finding：applicability 三值為 UNKNOWN） | — |
| 7 | 16 | CHECKLIST_UNCOVERED（finding：該 checklist id 沒有任何 requirement 滿足） | — |
| 7 | 17 | UNSUPPORTED（finding） | — |
| 7 | 18 | BLOCKED（finding：單位或知識被擋） | — |
| 7 | 19 | WAITING（finding：WAITING_KNOWLEDGE／WAITING_AUDIT／ROUTING_REQUIRED） | — |
| 7 | 21 | COVERAGE（finding：a＝已納入列數，c＝closure；PARTIAL／UNKNOWN 為 debt） | — |
| 8 | 01 | MAPPING_UNSIGNED：reviewedVersion≠packVersion（-ValidatePack／-Gate 的結論碼；gate.json 亦列 finding） | 1 |
| 9 | 01 | BAD_ARGS | 2 |
| 9 | 02 | ENV：環境錯（找不到 docs/ps-research、能力目錄、索引無法讀取、未預期例外） | 2 |
| 9 | 03 | JOB_NOT_FOUND | 2 |
| 9 | 04 | MUTEX_BUSY：同 job 的另一個 ps-spec 正在跑 | 3 |
| 9 | 05 | BAD_ID：jobId／packId 不符 `^[a-z0-9][a-z0-9-]{0,31}$`，或 Component 不符物件名文法 | 2 |
| 9 | 06 | LIB_VERSION：dot-source 的 lib 版本不符 | 2 |

### 4-02 INVALID 的原因碼（verdict.reasons；drill 4-02 的 r=）

`MISSING`（沒寫片段／空白）、`LINES_OVER`、`FENCE`（三反引號）、`WIKILINK`（`[[`）、`SLOT_MARKER`、`JSON_LEAK`、`TEMPLATE_LEAK`（含模板副本任一非標題行）、`SECTION_MISSING`、`HEADER_MISMATCH`、`COLUMN_COUNT`、`EMPTY_CELL`、`ITEM_UNKNOWN`（來源條目不在工單列舉）、`ENUM`、`EVIDENCE_UNKNOWN`（證據參照不在讀取集合）。`LINES_OVER`／`JSON_LEAK` 屬容量事件（4-05／4-06），不計 attempt。

## drill tuple（`ps-spec -Doctor -JobId <jobId> -Drill <stage>-<code>`）

每筆一行固定 tuple，只有 opaque ID（Rnn／Cnn／attemptId／序號）、factKind、模式、計數與封閉值；沒有路徑、檔名、物件名、hash、文字。

```text
D<stage>-<code> <id> <factKind> <mode> <k=v …>
D0-01 F1 GENERIC FILE c=MODIFIED
D2-06 R19 UNSUPPORTED UNSUPPORTED a=0
D3-04 R17 DATA.FILE_INPUT COMPOSE a0003 h=False
D4-02 R17 DATA.FILE_INPUT COMPOSE a0001 n=9 c=PARTIAL r=ITEM_UNKNOWN,EVIDENCE_UNKNOWN
D4-03 R17 DATA.FILE_INPUT COMPOSE a=2 c=BLOCKED
D5-04 R01 UI.COMPONENT_IDENTITY EXTRACT t=COMPONENT r=GRADE g=UNAUDITED
D6-02 R18 DATA.RECORD_USAGE COMPOSE c=SOURCE_CHANGED
D7-21 R05 UI.FIELD_INVENTORY EXTRACT a=0 c=PARTIAL
D7-16 C03 CHECKLIST ANY a=0 c=UNCOVERED
D8-01 PACK MAPPING ANY a=0 c=UNSIGNED
```

k 的意義：a＝計數（列數／attempt 數／版本）、c＝封閉狀態值、n＝片段行數、r＝原因碼或 need 理由（MISSING／GRADE／CALLEE）、t＝need 目標型別、g＝等級、h＝session 健康。

## 能力申請單 CAP-REQ（目錄外的需求）

需求對到 capabilities.json 以外的能力時，requirement 先填 `UNSUPPORTED`，並以下列表單申請——**只用公開詞彙**：NN 節名（相關物件／功能定位／畫面與欄位／行為邏輯／資料流／執行方式／權限／未解事項／Evidence 附錄）、物件型別（COMPONENT／RECORD／FIELD／PAGE／AE／SQR／SQC／SQL／PROCESS／MENU）、公開欄名、cardinality enum。禁止 checklist／template 文字與 C／S／R id；維護端只用合成 fixtures（TW_DEMO_*、PS_DEMO_*）實作。

```text
CAP-REQ: sources=[行為邏輯, Evidence 附錄], subject=COMPONENT, output=[trigger, condition, message], cardinality=ALL_DISCOVERED
```
