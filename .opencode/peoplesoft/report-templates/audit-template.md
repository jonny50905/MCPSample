# <領域> 稽核報告（90-audit）

> 稽核輪次：<N>　稽核日期：<YYYY-MM-DD>　範圍：<已完成的 N 個檔案>　執行：/ps-audit

<!-- 本報告每輪整檔重寫：判定只來自本輪 auditor 回報，禁止沿用上一輪
     的數字或內容；輪次未較上一輪 +1 ＝未重驗。 -->

## 總覽記分卡

| 檔案 | 證據 PASS | FAIL | UNVERIFIABLE | Claim VERIFIED | DISPUTED | 燈號 |
|---|---|---|---|---|---|---|
| 01-… | 8 | 0 | 1 | 4 | 0 | 🟡 |

燈號：🟢 無 FAIL / DISPUTED；🟡 僅 UNVERIFIABLE；🔴 有 FAIL 或 DISPUTED

## FAIL / DISPUTED 明細

| 檔案 | 類型 | 內容 | 原因 | 處置 |
|---|---|---|---|---|
| 01-… | 證據 FAIL | ChunkId … | quote 非 ChunkText 子字串 | 回灌補查 |

## 完整性（換角度 diff）

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
