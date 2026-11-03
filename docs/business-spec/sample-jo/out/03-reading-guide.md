# 3 怎麼讀 Spec

## 3.1 閱讀順序
照下表順序讀來源 Spec；前面的內容是讀懂後面內容的前提。
| 順序 | 內容 | 來源位置 | 整理到 |
|---|---|---|---|
| 1 | 範圍 | project.md §本期目標、project.md §補充說明 | 3.3 |
| 2 | 業務資料 | research/01-job-opening-create.md §5、research/02-job-opening-approval.md §7 | 5.3 |
| 3 | 畫面 | research/01-job-opening-create.md §3、research/02-job-opening-approval.md §3、research/02-job-opening-approval.md §4 | 5.2 |
| 4 | 規則 | research/01-job-opening-create.md §4、research/02-job-opening-approval.md §5 | 5.4 |
| 5 | 狀態 | status.md §各狀態的意思、status.md §誰觸發 | 5.5 |
| 6 | 流程 | research/02-job-opening-approval.md §2、research/02-job-opening-approval.md §4 | 5.1 |
| 7 | 權限 | research/01-job-opening-create.md §6 | 5.6 |
| 8 | 外部往來 | research/02-job-opening-approval.md §6 | 5.7 |
| 9 | 驗收 | research/02-job-opening-approval.md §8 | 9.1 |

## 3.2 Spec 地圖
各類內容的位置見 3.1。本節說明來源的排版慣例與表格欄位意義，後續各章照這裡的解讀讀來源。

排版慣例：
| 慣例（原文或樣式） | 出現位置 | 意思 |
|---|---|---|
| 「—」 | research/01-job-opening-create.md §3.2 | 該格沒有內容 |
| 「待確認」（必填欄） | research/01-job-opening-create.md §3.2 | 該欄位是否必填尚未定案 |
| 「系統給號」（預設欄以「」框起） | research/01-job-opening-create.md §3.2 | 預設值，畫面上顯示的原文 |
| 「檢核見 R07」（說明欄的 R 加數字） | research/01-job-opening-create.md §3.2 | 指向規則表的規則編號；R11 以後在 research/02-job-opening-approval.md §5 |
| 「見 02 §2」 | research/01-job-opening-create.md §3.3 | 指向另一份研究文件的章節 |
| 「「D」＝草稿」（代碼值並列顯示文字） | research/01-job-opening-create.md §5 | 代碼值＝畫面顯示的名稱 |
| 狀態圖箭頭「A --> B : 動作」 | status.md §狀態圖 | 左邊是轉移前的狀態、右邊是轉移後的狀態、冒號後是觸發的動作；沒有冒號的箭頭，來源沒標觸發動作 |
| 標題「（實作說明）」 | research/02-job-opening-approval.md §7 | 該節以系統設計為主，只取其中的業務意義 |

表格欄位意義：
| 表格位置 | 欄位（原文） | 意思 | 整理到 |
|---|---|---|---|
| research/01-job-opening-create.md §1、research/02-job-opening-approval.md §1 | 物件 | 系統裡的物件名稱 | 不使用：屬系統設計 |
| research/01-job-opening-create.md §1、research/02-job-opening-approval.md §1 | 類型 | 系統物件的種類 | 不使用：屬系統設計 |
| research/01-job-opening-create.md §1、research/02-job-opening-approval.md §1 | 角色 | 該物件負責的功能 | 不整理 |
| research/01-job-opening-create.md §3.2、research/02-job-opening-approval.md §3 | 畫面標籤 | 畫面上看到的欄位名稱 | UI 欄位標籤 |
| research/01-job-opening-create.md §3.2、research/02-job-opening-approval.md §3 | 技術名 | 系統內的欄位名稱 | 不使用：屬系統設計 |
| research/01-job-opening-create.md §3.2、research/02-job-opening-approval.md §3 | 必填 | 是否必填；「是」必填、「否」選填 | UI 必填 |
| research/01-job-opening-create.md §3.2、research/02-job-opening-approval.md §3 | 預設 | 開啟畫面時帶入的值 | UI 預設 |
| research/01-job-opening-create.md §3.2、research/02-job-opening-approval.md §3 | 可改條件 | 什麼情況下可以修改 | UI 可改條件 |
| research/01-job-opening-create.md §3.2、research/02-job-opening-approval.md §3 | 顯示條件 | 什麼情況下會出現 | UI 出現條件 |
| research/01-job-opening-create.md §3.2、research/02-job-opening-approval.md §3 | 說明 | 欄位的業務意思與檢核提示 | UI 描述 |
| research/01-job-opening-create.md §3.3、research/02-job-opening-approval.md §4 | 按鈕 | 按鈕上的名稱 | UI 欄位標籤 |
| research/01-job-opening-create.md §3.3、research/02-job-opening-approval.md §4 | 技術名 | 系統內的按鈕名稱 | 不使用：屬系統設計 |
| research/01-job-opening-create.md §3.3、research/02-job-opening-approval.md §4 | 顯示條件 | 什麼狀態下按鈕會出現 | UI 出現條件 |
| research/01-job-opening-create.md §3.3、research/02-job-opening-approval.md §4 | 按下後 | 按下按鈕後的結果 | UI 描述 |
| research/01-job-opening-create.md §4、research/02-job-opening-approval.md §5 | 規則編號 | 來源自己的規則編號 | 證據 |
| research/01-job-opening-create.md §4、research/02-job-opening-approval.md §5 | 時機 | 什麼時候檢核 | RULE 時機 |
| research/01-job-opening-create.md §4、research/02-job-opening-approval.md §5 | 條件 | 規則成立的條件 | RULE 條件 |
| research/01-job-opening-create.md §4、research/02-job-opening-approval.md §5 | 結果 | 條件成立時的結果 | RULE 結果 |
| research/01-job-opening-create.md §4、research/02-job-opening-approval.md §5 | 訊息原文 | 畫面上顯示的訊息 | RULE 訊息原文 |
| research/01-job-opening-create.md §6 | 角色 | 使用系統的角色 | PERM 角色 |
| research/01-job-opening-create.md §6 | 認定方式 | 怎麼認定誰是這個角色 | PERM 角色定義 |
| research/01-job-opening-create.md §6 | 可用畫面 | 角色可以使用的畫面 | PERM 對象 |
| research/01-job-opening-create.md §6 | 可做的動作 | 角色可以做的動作 | PERM 可改 |
| research/01-job-opening-create.md §6 | 資料範圍 | 角色看得到的職缺範圍 | PERM 資料範圍 |
| research/02-job-opening-approval.md §6 | 對象 | 往來的對象或通知的收件人 | EXT 對象 |
| research/02-job-opening-approval.md §6 | 方向 | 取得或送出 | EXT 方向 |
| research/02-job-opening-approval.md §6 | 內容 | 交換的業務項目 | EXT 交換內容 |
| research/02-job-opening-approval.md §6 | 時機 | 什麼時候交換 | EXT 時機 |
| research/02-job-opening-approval.md §6 | 失敗時 | 對方沒回應或取不到時的處理 | EXT 失敗時業務處理 |

## 3.3 範圍判讀
| 需求鍵 | 範圍類型 | 項目 | 描述 | 證據 | 確認狀態 | 相關假設 |
|---|---|---|---|---|---|---|
| SCOPE-001 | 包含 | 職缺建立與送審 | 用人主管與招募人員在系統上建立職缺並送審，取代紙本職缺申請單的簽核 | E-001 | 已確認 | — |
| SCOPE-002 | 包含 | 職缺核准 | 依開缺人數走一層或兩層核准，核准後立即開放徵才 | E-002 | 已確認 | — |
| SCOPE-003 | 包含 | 職缺暫停、恢復與關閉 | 招募人員可暫停、恢復、關閉職缺 | E-003 | 已確認 | — |
| SCOPE-004 | 包含 | 職缺補足標示 | 已錄取人數達到開缺人數時，職缺自動標示為補足 | E-003 | 已確認 | — |
| SCOPE-005 | 包含 | 職缺相關通知 | 送審、退回、核准、補足時，相關人員收到通知 | E-004 | 已確認 | — |
| SCOPE-006 | 依賴 | 錄用作業：已錄取人數 | 已錄取人數由現有的錄用作業回寫 | E-005 | 已確認 | — |
| SCOPE-007 | 依賴 | 人事資料：職位、部門、工作地點與主管關係 | 職位、部門、工作地點與主管關係以人事資料為準，不在職缺功能內維護 | E-006 | 已確認 | — |
| SCOPE-008 | 排除 | 對外招募網站 | 來源註明本期不含；核准後不自動刊登到公司徵才網站，刊登仍由招募人員人工處理 | E-007 | 排除 | — |
| SCOPE-009 | 排除 | 面試排程 | 來源註明本期不含；面試時間的安排沿用現行做法，不在本系統處理 | E-008 | 排除 | — |
| SCOPE-010 | 排除 | 應徵者管理與錄用作業 | 來源註明本期不含 | E-005 | 排除 | — |
| SCOPE-011 | 排除 | 舊有紙本職缺申請單的轉入 | 來源註明舊有的紙本職缺申請單不轉入系統 | E-009 | 排除 | — |

來源 Spec 未區分核心與非核心，範圍內一律視為核心。

## 3.4 常見誤讀
| 位置 | 容易誤讀成 | 正確讀法 | 依據 |
|---|---|---|---|
| E-010 | 把狀態圖上的「已核准（開放徵才）」當成另一個狀態 | 括號是圖上的註記，狀態名稱是「已核准」 | E-011 |
| E-012 | 把相關物件表的「角色」欄當成使用職缺功能的角色 | 該欄寫的是物件負責的功能，使用者角色以角色與權限表為準 | E-013 |
| E-014 | 把驗收情境 1 的「開缺 3 人」當成只有 3 人才走一層核准 | 3 人只是範例，開缺 1 到 5 人都走一層核准 | E-015 |
| E-016 | 把「實作說明」整節當成與業務無關而略過 | 其中每次狀態變更要留下紀錄、每次核准或退回要留下審核紀錄是業務要求 | E-017 |
