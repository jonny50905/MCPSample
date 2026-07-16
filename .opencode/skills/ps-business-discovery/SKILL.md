---
name: ps-business-discovery
description: PeopleSoft 業務問題入口（例：兵役資料在哪裡維護？）— 解析 business domain 與客製政策（CUSTOM_ONLY_ROOTS / CUSTOM_FIRST），定位業務根物件。
---

# ps-business-discovery：業務問題 → 根物件定位

## 職責

把「業務問題」對應到 PeopleSoft 的**業務根物件**（Component / Page / Record.Field），
並決定後續要交給哪些 flow Skill（ps-ui-flow、ps-peoplecode-flow、ps-sql-flow、
ps-sqr-flow、ps-ae-flow、ps-data-lineage、ps-process-flow、ps-security-flow），
最後由 ps-business-explain 產出業務說明。

## 前置：載入環境設定（必做）

搜尋任何 PeopleSoft 物件之前：

1. 載入 `.opencode/peoplesoft/customization-profile.yaml`
   （或呼叫 `ps_get_customization_profile`）。
2. 載入 `.opencode/peoplesoft/business-domain-map.yaml` 解析業務領域
   （或呼叫 `ps_search_business_domains`）。
3. 由命中的 domain 決定搜尋模式：
   `CUSTOM_ONLY_ROOTS` / `CUSTOM_FIRST` / `MIXED` / `DELIVERED_ALLOWED`。
4. **未命中 domain ≠ 不能查**：不得以「此領域不存在／不支援」拒答，
   改用 profile 的 `searchPolicy.defaultMode` 走同樣的搜尋順序，
   並在輸出註明未命中、建議把該領域補進 business-domain-map.yaml。

## 搜尋順序

```text
1. Business Domain Alias
2. Page 實際顯示文字            （ps_search_ui_semantics）
3. Page 欄位選項文字            （ps_search_ui_semantics / ps_get_field_choices）
4. 客製 Object Description
5. 客製 Record / Field Label
6. 客製 PeopleCode Chunk        （ps_search_source）
7. 客製 SQL Chunk               （ps_search_source）
8. 客製 SQR / SQC Chunk         （ps_search_source）
9. 客製 Object 關聯
10. 原生物件 fallback
```

在 `CUSTOM_ONLY_ROOTS` 模式下，第 10 步**預設不執行**
（除非 profile / domain 明確允許 deliveredFallback）。

## Custom Root 與 Delivered Dependency

```text
TW_MILITARY_DATA Component
  → TW_MILITARY Page
  → TW_MILITARY_REC
  → PeopleCode
  → 呼叫原生共用 Utility
```

正確結論：

```text
業務根物件：TW_MILITARY_DATA（來源：CUSTOM_PREFIX）
原生相依物件：某 PeopleSoft Utility（角色：DEPENDENCY）
```

**不可**將原生 Utility 說成「此業務功能的主要實作」。

## Skill Rules

```text
Before searching PeopleSoft objects, load the environment customization profile.

Classify each candidate as:
- CUSTOM_PREFIX
- CUSTOM_REGISTRY
- MODIFIED_DELIVERED
- DELIVERED
- UNKNOWN

A custom prefix is a strong ranking signal, but it is not the only evidence
that an object is customized.

Resolve the business domain before selecting root objects.

When the business domain uses CUSTOM_ONLY_ROOTS:
- Only customized objects may be selected as root business objects.
- Delivered objects may be included only as dependencies.
- Do not use a delivered object merely because its description resembles
  the business question.
- Do not perform delivered fallback unless the profile explicitly allows it.

When the business domain uses CUSTOM_FIRST:
- Search customized objects first.
- Search delivered objects only if customized evidence is insufficient.
- Clearly report when delivered fallback was used.

Prefer business-facing UI text and option labels over technical object names
when resolving a business question.

When no business domain matches the question:
- Do NOT refuse. Do NOT answer that the domain is unsupported or undefined.
- Use searchPolicy.defaultMode from the customization profile.
- Follow the normal search order and set businessDomain.domainId to null.
- Recommend adding the domain to business-domain-map.yaml.

Always report:
- the resolved business domain
- the search scope
- the root object policy
- object origins
- whether delivered fallback was used
```

## 輸出格式

```json
{
  "businessDomain": {
    "domainId": "military_service",
    "displayName": "兵役",
    "matchedAlias": "免役",
    "rootObjectPolicy": "CUSTOM_ONLY_ROOTS"
  },
  "searchScope": {
    "mode": "CUSTOM_ONLY_ROOTS",
    "customPrefixes": ["TW_"],
    "deliveredFallbackUsed": false
  },
  "candidateRoots": [
    {
      "objectType": "COMPONENT",
      "objectName": "TW_MILITARY_DATA",
      "origin": "CUSTOM_PREFIX",
      "status": "CONFIRMED",
      "evidenceIds": ["UI-E001", "OBJ-E001"]
    }
  ],
  "dependencies": [],
  "warnings": []
}
```

未命中 domain 時：`domainId` / `matchedAlias` 為 `null`，
`rootObjectPolicy` 與 `searchScope.mode` 取自 `searchPolicy.defaultMode`，
並在 `warnings` 加註「domain 未定義，建議補進 business-domain-map.yaml」。

## 整合流程（下游交棒）

```text
使用者業務問題
  ↓ 載入 Customization Profile → 解析 Business Domain → 決定搜尋模式
  ↓ 搜尋 UI 顯示文字 → 搜尋選項文字 → 映射 Component / Page / Record.Field
  ↓ 搜尋客製 PeopleCode / SQL / SQR / SQC Chunk → 取得精確 Database Chunk
  ↓ 追蹤 AE / Process / Security / Data Lineage → 必要時加入 Delivered Dependency
  ↓ ps-business-explain
```

## 防呆

```text
Do not assume a delivered PeopleSoft object implements the customer's business
process when the customization profile marks the domain as custom-only.

Do not treat TW_ as the only way to identify customization.

Do not ignore page display text — user-visible labels are primary business
search signals.

Do not call a delivered object the root business implementation when it is only
a dependency of a TW_ custom object.
```

## Orchestrator 模式（小 context 部署）

地端小 context 模型建議用 `.opencode/agent/ps-orchestrator.md`（primary agent）
承載本 skill：本 skill 只做 domain 解析與根物件定位；長文本檢索一律依
orchestrator 的委派表派給 ps-* subagents，主 context 只保留
`subagent-report-contract.md` 格式的 JSON 報告，不累積 raw chunks。

## 相關檔案

- `.opencode/peoplesoft/customization-profile.yaml`
- `.opencode/peoplesoft/business-domain-map.yaml`
- `.opencode/peoplesoft/mcp-tool-contracts.md`
- `.opencode/peoplesoft/progressive-source-retrieval.md`（長文本搜尋一律遵守）
