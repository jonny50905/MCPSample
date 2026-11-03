# 附錄

## A 名詞表
| 名詞 | 意思 |
|---|---|
| 來源 Spec | 輸入的 Spec 檔案，放在 `docs/business-spec/sample-jo/source`。唯讀，是唯一業務真相 |
| 業務需求文件 | 依本規範寫出的產出，放在 `docs/business-spec/sample-jo/out` |
| 需求 | 業務需求文件中有需求鍵的一條業務陳述 |
| 需求鍵 | 需求的穩定編號，格式 `<類別碼>-<三位序號>`，例 `RULE-007` |
| 類別碼 | SCOPE、FLOW、UI、DATA、RULE、STATE、PERM、EXT、ACC、OTHER，共 10 個 |
| 假設 | 來源缺漏、矛盾、未完成、看不懂時登記的待解事項，編號 `A-###` |
| 暫定做法 | 假設未關閉前，需求暫時採用的最保守做法 |
| 業務窗口 | 能拍板業務問題的人（代稱，不寫真名） |
| Spec 產製端 | 產出來源 Spec 的人或流程，能回頭補查舊系統 |
| 確認狀態 | 待確認、已確認、已交付、已驗收、排除，見 6.2 |
| 驗收情境 | 給業務人員操作驗證的情境，需求鍵類別 ACC |
| 衍生 | 來源沒有直接寫、但由其他需求機械推出的項目，目前只用於驗收情境；必須寫來源需求鍵 |
| 證據 | 支持一條需求或一筆假設的一段來源原文，編號 `E-###`，見第 10 章 |
| 補查 | 來源檔案不足以支持時，由外環向舊系統查詢；結果檔在 `evidence/`，只有「結果」節能當證據 |

## B Spec 文件與業務用途對照表
| 來源 Spec 檔 | 業務用途 |
|---|---|
| project.md | 本期目標與範圍補充 |
| research/01-job-opening-create.md | 建立與維護職缺的畫面、規則、權限 |
| research/02-job-opening-approval.md | 送審核准、開放後管理與驗收 |
| status.md | 職缺狀態與轉移觸發者 |

## C 範本
| 範本 | 一列 |
|---|---|
| 需求索引 | `\| FLOW-001 \| 流程與業務情境 \| 申請人填借用單並送審 \| E-007 \| 已確認 \| — \|` |
| 追蹤表 | `\| RULE-003 \| 借用期間最長 7 天，超過不能送審 \| 待確認 \| — \| — \| — \| 見 A-002 \|` |
| 假設 | `\| A-002 \| 矛盾 \| 借用期間上限，一處寫 7 天、一處寫 14 天（證據：E-044、E-045） \| 採限制較多的一邊：最長 7 天 \| RULE-003、ACC-009 \| Spec 產製端 \| 開放 \| — \|` |
| Spec 差異報告 | `\| 1 \| 03-rules.md §1 第 3 列 \| 修改 \| 最長 7 天 \| 最長 14 天 \| RULE-003 \| 改寫需求 \| FLOW-001、ACC-009 \|` |
| 證據 | `\| E-001 \| 檔案 \| spec-input/rules.md §2.1 \| 借用期間不得超過 30 天 \|` |
| 驗收紀錄 | `\| 1 \| ACC-009 \| 業務人員甲 \| 11/20 \| 借用 8 天，顯示「借用期間不得超過 7 天」，無法送審 \| 通過 \| — \| 無 \|` |

## D 參考文件
- 來源 Spec 各檔：
  - project.md／來源未標示
  - research/01-job-opening-create.md／來源未標示
  - research/02-job-opening-approval.md／來源未標示
  - status.md／來源未標示
- 本文件各檔：`README.md`、`01-goals.md`、`02-spec-overview.md`、`03-reading-guide.md`、`04-requirement-index.md`、`04-requirement-index-02.md`、`05-1-flows.md`、`05-2-screens.md`、`05-3-data.md`、`05-4-rules.md`、`05-5-states.md`、`05-6-permissions.md`、`05-7-interfaces.md`、`05-8-coverage.md`、`06-tracking.md`、`06-tracking-02.md`、`07-assumptions.md`、`08-spec-change.md`、`09-acceptance.md`、`10-evidence.md`、`appendix.md`、`progress.md`
