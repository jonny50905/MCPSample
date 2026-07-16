---
name: ps-business-explain
description: Use as the final synthesis step of a PeopleSoft business investigation — turn evidence collected by ps-business-discovery / ps-ui-flow / ps-peoplecode-flow / ps-sql-flow / ps-sqr-flow / ps-data-lineage etc. into a business-language explanation, with clear separation of screen text vs stored value, custom root vs delivered dependency, and CONFIRMED vs INFERRED vs DYNAMIC_RUNTIME.
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
3. 選項與儲存值對照（如適用）
4. 選擇後會發生什麼（PeopleCode / SQL / AE / SQR，逐項標 CONFIRMED / INFERRED / DYNAMIC_RUNTIME）
5. 資料流向（讀了什麼、更新了什麼）
6. 根物件與相依物件清單（origin 標註）
7. Evidence 清單（evidence IDs）
```

## 相關檔案

- `.opencode/peoplesoft/customization-profile.yaml`
- `.opencode/peoplesoft/business-domain-map.yaml`
