---
name: ps-business-explain
description: 最終彙整 — 把各 flow 證據轉成業務說明；畫面文字與儲存值分開、CONFIRMED / INFERRED / DYNAMIC_RUNTIME 標註、原生僅列 Dependency。
---

# ps-business-explain：業務說明產出

## 職責

把各 flow Skill 收集到的 Evidence 統整成**業務人員看得懂**的說明。
這是整合流程的最後一步，只彙整、不再自行搜尋新物件
（缺證據時退回對應的 flow Skill 補查）。

## 結論必須區分的層次

```text
畫面文字：免役
儲存值：E
業務根物件：TW_MILITARY_DATA
物件來源：CUSTOM_PREFIX
PeopleCode 分支：CONFIRMED / INFERRED
SQL 更新：CONFIRMED / DYNAMIC_RUNTIME
原生物件：僅列為 Dependency
```

## 選項生命狀態（選項類問題必附）

每個選項先標三個證據維度，再下生命狀態結論：

```text
XLAT 狀態      ACTIVE / INACTIVE
程式邏輯       有（附 evidence IDs）/ 查無
資料分布       N 筆 / 0 筆（彙總數字）
```

- 「已停用 / 沒在用」要三重證據齊全才標 CONFIRMED；
  缺任何一項只能標 INFERRED，並寫明缺哪一項。
- 「僅定義未使用」（ACTIVE、程式查無、資料 0 筆）與
  「歷史遺留」（INACTIVE 但資料仍有 N 筆）是不同結論，分開講。

## Skill Rules

```text
Explain in business language first; keep technical object names as supporting
detail, not as the headline.

Never merge screen text and stored value into one claim — always state both
(e.g. 「免役」 is stored as MIL_STATUS = 'E').

Always report:
- the resolved business domain and root object policy
- the custom root objects with their origin classification
- delivered objects strictly as dependencies
- whether delivered fallback was used

Mark every statement with its confidence:
- CONFIRMED        backed by exact database chunks / metadata (cite evidence IDs)
- INFERRED         reasoned from multiple evidence items (cite them)
- DYNAMIC_RUNTIME  decided at runtime — say what is known statically and what
                   is not knowable without running the system

Do not present an INFERRED or DYNAMIC_RUNTIME statement as fact.
Do not include claims that have no evidence ID.

If the evidence is insufficient to answer part of the question, say which part
and which flow skill should be run to fill the gap.
```

## 輸出建議結構

```text
1. 一句話結論（業務語言）
2. 在哪裡維護（Component / Page，含畫面文字與語系）
3. 選項與儲存值對照＋生命狀態（如適用）
4. 什麼條件會變成哪個值 / 選擇後會發生什麼（PeopleCode / SQL / AE / SQR，逐項標 CONFIRMED / INFERRED / DYNAMIC_RUNTIME）
5. 資料流向（讀了什麼、更新了什麼）
6. 根物件與相依物件清單（origin 標註）
7. Evidence 清單——給人看的格式：`filePath:行號`（如
   `sqr/TWMIL001.sqr:61-120`）；chunkId 附在後面供機器重取
```

## Subagent 架構下的輸入

Orchestrator 模式時，輸入是各 subagent 的 JSON 報告
（`subagent-report-contract.md`），不是 raw evidence：
- 只彙整報告的 findings / dependencies / dynamicRuntimeWarnings / gaps。
- confidence 不可升級：報告標 INFERRED / DYNAMIC_RUNTIME 就照實保留。
- 需要引用原文時，按 evidence ID 請對應 subagent 定向補取單段，不重跑檢索。
- 多份報告衝突：以 confidence 高者為準；同級衝突如實並陳並標 INFERRED。

## 相關檔案

- `.opencode/peoplesoft/customization-profile.yaml`
- `.opencode/peoplesoft/business-domain-map.yaml`
