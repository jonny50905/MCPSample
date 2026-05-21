# Elasticsearch MCP 工具參數細節

本檔由 `SKILL.md` 引用,僅在需要傳參數但不確定時才讀。

工具前綴:`mcp__elasticsearch-skill__*`
連線設定:`src/HanshinChat.Mcp.ElasticSearch.Skill/appsettings.json`(BaseUrl、Username、Password、DefaultIndex)

---

## search

全文 / 關鍵字搜尋 ── **第一層搜尋的主力工具**。

**參數:**
- `query` (string, **必填**) — Lucene query string,接給 ES 的 `query_string` query
- `index` (string, 可選) — 省略時用 appsettings 的 `DefaultIndex`
- `size` (int, 預設 10) — 回幾筆 hits
- `from` (int, 預設 0) — 分頁 offset
- `fields` (string[], 可選) — 限制 `_source` 只回這些欄位,省 token

**回傳:** ES 原生 search response(JSON),關注以下節點:

```json
{
  "hits": {
    "total": { "value": 42, "relation": "eq" },
    "hits": [
      {
        "_id": "abc123",
        "_score": 1.23,
        "_source": { "MessageId": "...", "Content": "...", "CreatedAt": "..." },
        "highlight": { "Content": ["...<em>運送</em>延遲..."] }
      }
    ]
  }
}
```

**Highlight 設定:** 所有欄位 `*`、`<em>` 標記、片段長 150、最多 3 段。

**Lucene query 範例:**
- 內容含關鍵字:`Content:運送`
- 片語(雙引號):`Content:"運送 延遲"`
- 多條件 AND:`Content:運送 AND Intent:complaint`
- OR 群組:`Intent:(complaint OR refund)`
- NOT:`Content:運送 AND NOT Intent:greeting`
- 時間範圍:`CreatedAt:[2026-05-01 TO 2026-05-31]`、`CreatedAt:[2026-05-15 TO *]`
- 排除已刪除:`Content:退貨 AND NOT IsDeleted:true`
- 全部文件:`*:*`(配 `count` 看總數)

**節省 token 範例:**
- `fields=["MessageId","ConversationId","Intent","CreatedAt"]` → `_source` 只回這四欄

**坑:**
- query 必須是合法 Lucene,語法錯會回 ES error JSON(`{"error": {...}}`)
- query 內含 `:` 或空白要用雙引號:`Content:"http://example.com"`
- `size` 上限預設 10000,過大會被 ES 擋

---

## count

只看命中筆數,不撈內容。**`search` 之前先 `count` 估量**,避免太大。

**參數:**
- `query` (string, **必填**) — Lucene query string(用 `*:*` 查全部)
- `index` (string, 可選)

**回傳:** ES `_count` response

```json
{ "count": 42, "_shards": { ... } }
```

**範例:**
- 全部文件:`query="*:*"`
- 某 intent 多少筆:`query="Intent:complaint"`
- 某時段:`query="CreatedAt:[2026-05-15 TO *]"`

---

## get_document

已知 `_id` 取單筆。

**參數:**
- `id` (string, **必填**) — 文件 `_id`(注意是 ES doc id,不一定等於 MessageId,但常見 mapping 會把 MessageId 設成 _id)
- `index` (string, 可選)

**回傳:** ES `_doc` response

```json
{
  "_index": "hanshinchat-messages",
  "_id": "abc123",
  "found": true,
  "_source": { ... }
}
```

**坑:** id 不存在會回 `{ "found": false }`(HTTP 404 → wrapper 仍回原文,不算錯)。

---

## list_indices

列出所有非系統 index(過濾以 `.` 開頭)。

**參數:** 無

**回傳:** `_cat/indices` 的 JSON 陣列(已過濾)

```json
[
  { "index": "hanshinchat-messages", "docs.count": "12345", "store.size": "5mb", "health": "green", "status": "open" }
]
```

**用途:** 不知道 index 名稱、想驗證 ES 連得到、想看 doc 數量。

---

## 共通回應格式

成功:ES 原生 JSON(視 endpoint 而定)。
失敗:
```json
{ "ok": false, "error": "...", "url": "...", "response": "..." }
```

判斷:有 `ok: false` 就是 wrapper 端攔截到的錯誤(HTTP 非 2xx 或 exception);沒有則是 ES 原文。

---

## 與 hanshinchat-skill 串接

**典型流程:**
```
1. search(query="Content:運送", fields=["MessageId","ConversationId"])
   → hits[].MessageId 拿到一串 id
2. 逐筆呼叫 mcp__hanshinchat-skill__get_message(id=MessageId)
   或一次呼叫 mcp__hanshinchat-skill__get_conversation(id=ConversationId)
   → 補完整 metadata、Intent 分類、客服資訊
```

**重點:不要直接呼叫 `mcp__hanshinchat-skill__search_messages` 對內容做 LIKE 全表掃**,效能差且不支援片語/範圍/欄位。
