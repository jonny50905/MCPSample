---
name: hanshinchat-mcp
description: Use when querying HanshinChat data (customer service agents, conversations, messages, or NLU call logs) — before calling any mcp__hanshinchat__* or mcp__hanshinchat-skill__* tool, to select the right tool and avoid unnecessary query_odata fallback.
---

# HanshinChat MCP 工具選擇指引

## Overview

hanshinChat MCP 提供 **10 個唯讀工具**,查詢本地 HanshinChat 資料庫的 4 個 entity:
**Agents / Conversations / Messages / NluCallLogs**。

兩個並行的 MCP server 註冊名稱:
- `mcp__hanshinchat__*` — 原版(工具 description 較完整)
- `mcp__hanshinchat-skill__*` — skill 面向版(description 精簡,本 skill 補上脈絡)

**呼叫工具前,先用本頁的決策表選對工具。需要參數細節時,Read `tool-usage.md`(同目錄)。**

## 四個 Entity 心智模型

- **Agents** — 客服人員(Name / IsOnline / EmployeeId)
- **Conversations** — 一段對話(Mode / Channel / MemberId / StartedAt / ClosedAt)
- **Messages** — 對話中的訊息,內容在 `ContentJson` 欄位裡(Intent / SenderType / IsDeleted)
- **NluCallLogs** — NLU 模型呼叫記錄(Stage / Model / LatencyMs / ErrorMessage)

## 工具總覽 (10 個)

### List 系列 — 列表查詢,有篩選器

| 工具 | 用途 |
|---|---|
| `list_agents` | 列客服:名字模糊搜尋、線上狀態、員工編號 |
| `list_conversations` | 列對話:mode / channel / member / 起始時間 / 僅開啟中 |
| `list_messages` | 列訊息:conversation / sender type / intent(**不搜內容**) |
| `list_nlu_logs` | 列 NLU 記錄:偵錯 intent 分類、找慢呼叫、找錯誤 |

### Get 系列 — 已知 Id 才用,取單筆

`get_agent` / `get_conversation` / `get_message` / `get_nlu_log`

> `get_conversation` 預設會展開前 100 則 messages;只要對話本身請設 `includeMessages=false`。

### 特殊

| 工具 | 用途 |
|---|---|
| `search_messages` | 在訊息「內容」(`ContentJson`) 裡找關鍵字 |
| `query_odata` | **escape hatch** — 上面 9 個都做不到時才用 |

## 任務 → 工具 決策表

| 你想做 ... | 用哪個工具 |
|---|---|
| 找名字含「王」的客服 | `list_agents`(`nameContains`) |
| 找線上的客服 | `list_agents`(`isOnline=true`) |
| 找指定員工編號的客服 | `list_agents`(`employeeId`) |
| 列出最近的對話 | `list_conversations` |
| 找今天還沒結束的對話 | `list_conversations`(`onlyOpen=true, startedAfter`) |
| 找某 channel(LINE/Web)的對話 | `list_conversations`(`channel`) |
| 找某會員的對話 | `list_conversations`(`memberId`) |
| 看某對話的所有訊息 | `get_conversation(id)` 或 `list_messages(conversationId)` |
| 找所有 intent=greeting 的訊息 | `list_messages`(`intent`) |
| 找某使用者/Bot/客服發的訊息 | `list_messages`(`senderType`) |
| 在訊息**內容**裡找「退貨」這個字 | `search_messages`(`text`) |
| 看已刪除的訊息 | `list_messages`(`includeDeleted=true`) |
| 找慢的 NLU 呼叫(>1 秒) | `list_nlu_logs`(`minLatencyMs=1000`) |
| 找 NLU 錯誤 | `list_nlu_logs`(`onlyErrors=true`) |
| 找某 Stage 的 NLU 呼叫 | `list_nlu_logs`(`stage`) |
| 找某 Model 的 NLU 呼叫 | `list_nlu_logs`(`model`) |
| 已知 Id 取單筆 | `get_*`(對應 entity) |
| 跨 entity / 複雜聚合 / 9 個都做不到 | `query_odata` |

## 關鍵規則(避免踩雷)

1. **先 list,再 get** — 通常不知道 Id,要先 list 拿到 Id 才用 get_*。
2. **訊息內容在 ContentJson** — `list_messages` 篩不了內容,要搜內容用 `search_messages`。
3. **`get_conversation` 預設展開訊息** — 想只要對話本身,設 `includeMessages=false`。
4. **`list_messages` 預設不含已刪除** — 要看刪除訊息設 `includeDeleted=true`;`search_messages` 同樣只搜未刪除。
5. **`query_odata` 是最後手段** — 9 個專用工具能解決就別用。它的 `entity` 只允許 `Agents | Conversations | Messages | NluCallLogs`。
6. **時間格式 UTC ISO-8601** — `startedAfter` 範例:`2026-05-01T00:00:00Z`。
7. **唯讀** — 所有工具都是 GET,不會改任何資料。

## `list_messages` vs `search_messages`(最常搞混)

| 情境 | 用哪個 |
|---|---|
| 「找 intent 是 greeting 的訊息」(**結構化欄位**) | `list_messages` |
| 「找某對話的所有訊息」(**已知 conversationId**) | `list_messages` 或 `get_conversation` |
| 「找訊息中提到『退貨』」(**內容子字串**) | `search_messages` |
| 「找客服(SenderType=Agent)發的訊息」 | `list_messages` |

**判斷:篩 metadata → `list_messages`;搜 ContentJson 內容字串 → `search_messages`。**

## 何時 fallback 到 `query_odata`

只有以下情境才用:
- 需要 `$select` 只拿特定欄位(節省 token)
- 需要複雜的 `$filter`(例如 `or` 組合、不等於、比較)
- 需要 `$skip` 做分頁
- 需要組合的 `$expand`
- 需要 `@odata.count` 看總筆數

否則優先用 9 個專用工具。

## 需要參數細節時

**Read `tool-usage.md`(同目錄)** — 含每個工具的完整參數、預設值、範例、坑。
只在需要傳參數但不確定時才讀,避免浪費 token。
