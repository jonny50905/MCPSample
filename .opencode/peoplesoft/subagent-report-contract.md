# Subagent Report Contract（回報契約）

所有 ps-* subagent 的**最終輸出只能是一份符合本契約的 JSON**，
前後不加說明文字。目的：raw chunks 留在 subagent context，
orchestrator 主 context 只累積小而結構化的報告。

## 硬規則（違反即報告不合格）

```text
1. 報告內不得出現大段原始碼：
   - 單一 quote ≤ 5 行
   - 全報告引用總量 ≤ 20 行
   - 引用永遠可省略；evidence ID（chunkId + 行號 + sourceHash）才是必要項
2. findings 內每個 claim 必附 ≥ 1 個 evidence ID；
   沒有 evidence 的內容寫入 gaps，不寫入 findings。
3. confidence 只能是 CONFIRMED / INFERRED / DYNAMIC_RUNTIME。
4. 查無 / 不確定 / 超出 budget：用 status=PARTIAL 或 BLOCKED + gaps 說明，
   不得編造物件名稱或執行期結果。
5. 報告目標長度 ≤ 600 tokens（軟性）；findings 依相關性排序，最多 8 筆。
6. delivered 物件一律進 dependencies，不進 findings 的主要實作敘述
   （CUSTOM_ONLY_ROOTS 模式下尤其如此）。
7. evidence 分兩種（`kind`），欄位不得混用、不得補假值：
   - `CHUNK`（來自 ES / Source）：欄位**逐字取自** `get_chunks_details` 回傳——
     `id` ← `ChunkId`（Elasticsearch chunk UUID；**非 UUID 格式＝捏造**）、
     `filePath` ← `FilePath`、`lines` ← `StartLine`-`EndLine`、
     `quote` ← `ChunkText` 節錄（≤ 5 行）；選填 `objectName` ← `ObjectName`、
     `event` ← `EventName`、`fieldName` ← `FieldName`。
     給人看的引用寫「filePath:行號」，id 供機器重取。
   - `SQL`（來自 oracleMCP）：附 `sql` 與 `keyRows`（關鍵列摘要），
     **沒有 id、也不准自創 id**——`SQL-XLAT-1` 這種自編字串＝報告不合格。
     **僅限本次實際執行過的 SELECT 與其結果**——程式碼裡的 SQL 語句
     （AE_SQL Action、SQR 段、PeopleCode 內嵌 SQL）屬**原始碼**，
     一律用 `CHUNK` 證據引用，不得標成 `SQL`。
   - **只有這兩種**。`PeoplecodeMetadata` 的回傳＝定位線索（地位同 ES
     搜尋結果），不得寫成 evidence 條目；只有定位、未經 CHUNK／SQL 查證
     的 finding 最高標 INFERRED。
   - **證據格式三鐵律**（缺一該筆不得列入 findings，改放 gaps）：
     (1) CHUNK 型必附**完整 36 字元** ChunkId；(2) 行號必須對應
     **當前**取回內容（引用時同步更新）；(3) **任何欄位禁止縮寫**
     （id、路徑、quote 皆逐字取自工具回傳）。
8. **禁止捏造識別碼**：id / filePath / lines 只能來自工具回傳；
   工具沒提供的欄位一律省略，不得補一個「看起來像」的值。
9. 長文本分析必附 `coverage`：本次分析的程式單位、其**結構行號範圍**、
   已取回並分析的行號區間；單位內未覆蓋的行號區間**必須**同時出現在
   `gaps`，不可默默省略。`quote` 節錄要挑**支撐 claim 的關鍵行**
   （判斷條件、寫入語句），不是 chunk 開頭幾行。
```

## JSON 結構

```json
{
  "agent": "ps-sqr-flow",
  "task": "一句話重述被委派的問題",
  "status": "COMPLETE | PARTIAL | BLOCKED",
  "searchScope": {
    "mode": "CUSTOM_ONLY_ROOTS",
    "customPrefixes": ["TW_"],
    "deliveredFallbackUsed": false
  },
  "coverage": [
    {
      "unit": "UPDATE-MIL-STATUS",
      "structureLines": "61-120",
      "analyzedLines": "61-120"
    }
  ],
  "findings": [
    {
      "claim": "UPDATE-MIL-STATUS 將 DISCHARGE_DT 已到期者的 MIL_STATUS 更新為 'D'",
      "confidence": "CONFIRMED",
      "objects": [
        { "type": "SQR", "name": "TW_MIL001", "origin": "CUSTOM_PREFIX" }
      ],
      "operations": [
        { "table": "PS_TW_MILITARY", "field": "MIL_STATUS", "op": "UPDATE" }
      ],
      "evidence": [
        {
          "kind": "CHUNK",
          "id": "9b2f5c1e-4a3d-4f0a-8f21-7e5d0c9a1b2c",
          "filePath": "sqr/TWMIL001.sqr",
          "lines": "61-120",
          "objectName": "TW_MIL001",
          "quote": "UPDATE PS_TW_MILITARY SET MIL_STATUS = 'D' ..."
        }
      ]
    }
  ],
  "dependencies": [
    { "type": "FUNCLIB", "name": "HR_COMMON_UTIL", "origin": "DELIVERED", "role": "DEPENDENCY" }
  ],
  "_sqlEvidenceExample": {
    "kind": "SQL",
    "sql": "SELECT FIELDVALUE, XLATLONGNAME FROM PSXLATITEM WHERE FIELDNAME = 'MIL_STATUS' ...",
    "keyRows": ["E=免役 (ACTIVE)", "A=替代役 (ACTIVE)"]
  },
  "dynamicRuntimeWarnings": [
    "LOAD-HISTORY 讀取的 table 由 [$hist_table] 執行期組成（CHK-SQR-003）"
  ],
  "gaps": [
    "PRINT-REPORT 未展開（與本題無關）"
  ],
  "suggestedNext": [
    { "agent": "ps-metadata-flow", "task": "TW_MIL001 的排程與 Run Control" }
  ]
}
```

## 欄位說明

| 欄位 | 必填 | 說明 |
|---|---|---|
| `agent` | ✔ | 回報的 subagent 名稱 |
| `task` | ✔ | 一句話重述任務（供 orchestrator 對帳） |
| `status` | ✔ | COMPLETE：已回答；PARTIAL：部分回答（見 gaps）；BLOCKED：無法進行（工具失敗 / 查無） |
| `searchScope` | ✔ | 實際使用的搜尋模式；用了 delivered fallback 必須在此如實回報 |
| `coverage[]` | 長文本必填 | 程式單位、結構行號範圍、已分析行號區間；未覆蓋區間必同時列於 gaps |
| `findings[]` | ✔（可為空陣列） | 每筆 = 一個可獨立驗證的 claim；`operations` 僅資料操作類 finding 需要 |
| `dependencies[]` | ✔（可為空陣列） | 原生 / 相依物件，只能出現在這裡 |
| `dynamicRuntimeWarnings[]` | ✔（可為空陣列） | 所有 DYNAMIC_RUNTIME 事項集中列出 |
| `gaps[]` | ✔（可為空陣列） | 未涵蓋範圍與原因（budget 到頂 / 與題無關 / 查無） |
| `suggestedNext[]` | 選填 | 建議 orchestrator 的後續委派 |

## Orchestrator 端的使用規則

- 報告是**彙整素材**，不是給使用者的最終答案；最終說明由
  ps-business-explain 規則產出。
- 引用報告時帶 evidence IDs；需要原文時按 ID 定向補取，不重跑檢索。
- 多份報告衝突時：以 confidence 高者為準；同級衝突如實並陳並標 INFERRED。
