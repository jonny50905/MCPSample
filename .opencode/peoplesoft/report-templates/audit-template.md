# <領域> 稽核報告（90-audit）

> 稽核輪次：<N>　稽核日期：<YYYY-MM-DD>　範圍：<已完成的 N 個檔案>　執行：/ps-audit

<!-- 本報告每輪整檔重寫：判定只來自本輪 auditor 回報，禁止沿用上一輪
     的數字或內容；輪次未較上一輪 +1 ＝未重驗。 -->

## 總覽記分卡

| 檔案 | 證據 PASS | FAIL | UNVERIFIABLE | Claim VERIFIED | DISPUTED | 燈號 |
|---|---|---|---|---|---|---|
| 01-… | 8 | 0 | 1 | 4 | 0 | 🟡 |
| **合計** | **8** | **0** | **1** | **4** | **0** | 🟢x／🟡y／🔴z |

<!-- 最後一列必為「合計」：各欄加總＋燈號分佈——趨勢追蹤靠它。 -->

燈號：🟢 無 FAIL / DISPUTED；🟡 僅 UNVERIFIABLE；🔴 有 FAIL 或 DISPUTED

## FAIL / DISPUTED / UNVERIFIABLE 明細

<!-- 三種非過判定**每一筆都要有一列**，UNVERIFIABLE 不得只出現在
     記分卡數字——原因欄逐字取自 auditor 回報（逾時／連線失敗／
     chunk 查無／工具不可用…），這是判斷環境問題 vs 資料問題的依據。
     DISPUTED 列的原因欄必含三要素：原 claim 一句、稽核取到的證據
     （ChunkId:行號）、矛盾點一句——缺任一＝不可裁決＝不合格判定。
     FAIL 類型詞彙表（原因欄使用）：TRUNCATED_ID／FABRICATED／
     WRONG_KIND／STALE_DATA／ID_RELINK／NOT_FOUND／MISSING_CHUNK_ID／
     INCOMPLETE_CHUNK；行號漂移但 quote 命中＝PASS(LINE_DRIFT) 附
     新行號，不是 FAIL。
     UNVERIFIABLE(PENDING_MANUAL)＝待人工SQL 申報列——照列進明細與
     記分卡，**不回灌 A 項**（人工待辦不是新問題）。 -->

<!-- 「處置」欄＝下一輪的可執行工單。稽核已經查到答案的類型，答案
     必須寫在這一欄，否則下一輪只拿得到 A 行的計數、要再付一次檢索成本：
       ID_RELINK  → `換 id：<完整舊 UUID> → <完整新 UUID>`（**兩個都要完整
                    36 字元**；lint 會機械解析這一欄開成 [回灌] 工單，
                    舊值是修復者定位「哪一列」的唯一線索）
       LINE_DRIFT → `更新行號 → <新行號>`
       STALE_DATA → `更新數值 → <新值>`
     其餘（NOT_FOUND／FABRICATED／WRONG_KIND…）才寫「回灌補查」。 -->

| 檔案 | 類型 | 內容 | 原因 | 處置 |
|---|---|---|---|---|
| 01-… | 證據 FAIL | ChunkId … | quote 非 ChunkText 子字串 | 回灌補查 |
| 02-… | 證據 UNVERIFIABLE | SQL … | oracleMCP 逾時（~30s） | 回灌重驗 |
| 03-… | 證據 FAIL(ID_RELINK) | 舊 ChunkId | id 失聯，二次定位已取得新 id | 換 id：<完整舊 UUID> → <完整新 UUID> |

## 上輪回灌項覆核（第 2 輪起必填；首輪寫「無上輪」）

<!-- 上輪 A 項逐項覆核：原判定屬實？誤報數是「稽核員品質指標」，
     長期追蹤。本節**不取代**總覽記分卡——記分卡永遠是本輪全量
     重驗的數字。 -->

| A 項 | 原判定 | 覆核結果 | 處置 |
|---|---|---|---|
| A6 … | 證據 FAIL | 屬實（已修）\| 誤報 \| 不可查 | <一句話> |

## 完整性（換角度 diff）

<!-- 覆蓋率必填（L81）：任務 C 是**分批委派**的，而委派會失敗
     （subagent 只回報「已讀取契約」就結束＝委派卡死的指紋）。
     **「查了沒發現」與「根本沒查成」不得共用同一格**——有未完成批次卻
     只寫「無」＝假陰性的完整性宣稱，比不寫更糟。
     覆蓋率那行沒填＝本節結論不可信（lint -StrictAudit 會擋）。 -->

- 任務 C 覆蓋：<完成 N／共 M 批>（未完成批次：<逐批列出，或「無」>）
- 資料角度發現、功能地圖沒有的物件：<清單，或「無」>

## 已回灌 checklist 的行動項

<!-- 順序約束：這些行必須「先」實際寫進 checklist.md，再抄錄到本節。
     任何非 PASS／VERIFIED 判定 ≥ 1 而 checklist.md 沒有對應 A<n> 行
     ＝流程錯誤，不得產出本報告。回灌以「檔」為單位彙整（一檔一行），
     禁止逐筆開項。判定詞彙限契約五詞：PASS/FAIL/UNVERIFIABLE（證據）、
     VERIFIED/DISPUTED/UNVERIFIABLE（claim）；auditor 自創詞就近映射
     （claim→DISPUTED、證據→FAIL）。 -->

- [ ] A1 補查 01-<物件名>.md：FAIL 2／DISPUTED 3／UNVERIFIABLE 1（稽核）

## 系統性錯誤觀察（同類 FAIL ≥ 2 → 建議 /ps-lesson）

- <觀察，或「無」>
