---
name: elasticsearch-mcp
description: Use when doing full-text / keyword search over HanshinChat messages indexed in Elasticsearch — the FIRST layer of search. Always go through this before falling back to hanshinchat-skill's `search_messages` (which is a slow SQL LIKE scan).
---

# Elasticsearch MCP 第一層搜尋指引

## Overview

`elasticsearch-skill` 是 **第一層搜尋** 通道:HanshinChat 訊息已被索引到本地 Elasticsearch,Claude 在使用者要「搜尋訊息內容」、「找關鍵字」、「全文檢索」、「某時段提到 X 的對話」時,**先**用這個 MCP 拿到 MessageId 命中清單(含 highlight 片段),**再**用既有 `hanshinchat-skill` 補完整明細。

工具名稱前綴:`mcp__elasticsearch-skill__*`

**呼叫工具前,先用本頁的決策表選對工具。需要參數細節時,Read `tool-usage.md`(同目錄)。**

## 工具總覽 (4 個)

| 工具 | 用途 |
|---|---|
| `search` | 全文 / 關鍵字搜尋(Lucene query string),回傳 hits(_id、_score、_source、highlights) |
| `count` | 估算命中筆數;`search` 前先 `count` 避免撈太大 |
| `get_document` | 已知 `_id` 取單筆文件 |
| `list_indices` | 列出可查的 index 名稱(過濾系統 index) |

## 雙層搜尋工作流(核心)

```
使用者:「找上週客戶提到『運送』的訊息」
   │
   ▼
1. elasticsearch-skill `search`
   query = "Content:運送 AND CreatedAt:[2026-05-15 TO *]"
   → 拿到 hits[{ id, source, highlights }] 命中片段
   │
   ▼
2. 若需要完整對話脈絡 / 鄰近訊息 / 客服資訊:
   hanshinchat-skill `get_message(id)` 或 `get_conversation(conversationId)`
   │
   ▼
3. 整合回覆使用者
```

**規則:**
1. **搜內容字串 → 一律走 ES**,不要直接 `mcp__hanshinchat-skill__search_messages`(那是 SQL LIKE 全表掃)。
2. **沒拿到 id / 想要完整明細才走 hanshinchat-skill**。`search` 的 `_source` 已含 highlight 片段,夠用就不要再呼叫 OData。
3. **大量結果先 `count`**:`count(query)` 看總數,再決定 `search` 的 `size` / 是否加篩選收斂。
4. **未知 index 名稱先 `list_indices`**,別亂猜。

## 任務 → 工具 決策表

| 你想做 ... | 用哪個工具 |
|---|---|
| 找訊息內容裡含「退貨」 | `search`(`query="Content:退貨"`) |
| 限定欄位 + 篩選的搜尋 | `search`(`query="Intent:complaint AND AgentId:A001"`) |
| 加時間範圍 | `search`(`query="Content:運送 AND CreatedAt:[2026-05-15 TO *]"`) |
| 只想知道有多少筆命中 | `count` |
| 已知 _id 取單筆 | `get_document` |
| 查可用的 index 名稱 | `list_indices` |
| 限制回傳欄位節省 token | `search`(`fields=["MessageId","Intent","CreatedAt"]`) |
| 拿到 id 後要完整 metadata / conversation | 換用 `mcp__hanshinchat-skill__get_message` / `get_conversation` |

## Lucene query 速查

| 寫法 | 意義 |
|---|---|
| `Content:運送` | `Content` 欄位含「運送」 |
| `Content:"運送 延遲"` | 片語精準比對 |
| `Content:運送 AND Intent:complaint` | 兩個條件都成立 |
| `Intent:(complaint OR refund)` | 任一 |
| `CreatedAt:[2026-05-01 TO 2026-05-31]` | 時間範圍 |
| `CreatedAt:[2026-05-15 TO *]` | 從某時間至今 |
| `NOT IsDeleted:true` | 排除已刪除 |
| `*:*` | 全部文件(配 `count` 看總數) |

## 關鍵規則

1. **第一層 ES,第二層 hanshinchat-skill** — 搜內容走 ES,補明細走 OData。
2. **`search` 預設 `size=10`**,需要更多明確指定;同時用 `fields` 限制 `_source` 控 token。
3. **未指定 `index` 用 appsettings 的 `DefaultIndex`**(通常是 `hanshinchat-messages`);跨 index 才傳。
4. **Lucene 字串中遇特殊字元**(`/`、`:`、空白等)用雙引號包起來。
5. **唯讀** — 所有工具都是 search/get,不會改 ES 任何資料。

## 需要參數細節時

**Read `tool-usage.md`(同目錄)** — 含每個工具完整參數、回傳格式、Lucene query 進階範例、坑。
只在需要傳參數但不確定時才讀,避免浪費 token。
