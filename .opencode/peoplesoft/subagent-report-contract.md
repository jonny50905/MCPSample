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
7. 來源 MCP 有提供檔案路徑（FilePath 欄位）時，evidence **必帶** filePath；
   給人看的引用一律寫「filePath:行號」，chunkId 保留作機器重取與防重的鍵
   ——兩者都要，不是二選一。oracleMCP 的 metadata 證據無檔案路徑，
   改附「使用的 SQL + 關鍵列」。
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
          "id": "CHK-SQR-001",
          "filePath": "sqr/TWMIL001.sqr",
          "lines": "61-120",
          "symbol": "UPDATE-MIL-STATUS",
          "sourceId": "SQR-TW_MIL001",
          "quote": "UPDATE PS_TW_MILITARY SET MIL_STATUS = 'D' ..."
        }
      ]
    }
  ],
  "dependencies": [
    { "type": "FUNCLIB", "name": "HR_COMMON_UTIL", "origin": "DELIVERED", "role": "DEPENDENCY" }
  ],
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
