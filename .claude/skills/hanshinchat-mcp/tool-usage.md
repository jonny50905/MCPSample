# HanshinChat MCP 工具參數細節

本檔由 `SKILL.md` 引用,僅在需要傳參數但不確定時才讀。

工具名稱前綴:`mcp__hanshinchat__*`(原版)或 `mcp__hanshinchat-skill__*`(skill 面向版)。
兩個 server 的工具名稱、參數、行為**完全一致**,只差工具的 description 詳簡程度。

---

## list_agents

列客服人員。

**參數:**
- `top` (int, 預設 50) — 最多回幾筆
- `isOnline` (bool, 可選) — 線上狀態篩選
- `nameContains` (string, 可選) — 名字含此子字串
- `employeeId` (string, 可選) — 員工編號精確匹配

**排序:** `Name asc`(固定)

**範例:**
- 找所有線上客服:`isOnline=true`
- 找姓「王」的客服:`nameContains="王"`

---

## get_agent

取單一 agent。

**參數:**
- `id` (uuid, 必填) — Agent Id

**坑:** 不知道 Id 就先用 `list_agents`。

---

## list_conversations

列對話。

**參數:**
- `top` (int, 預設 50)
- `mode` (string, 可選) — `"AI"` / `"Human"` / `"Queue"`
- `channel` (string, 可選) — `"Web"` / `"LINE"` 等
- `memberId` (string, 可選) — 精確匹配
- `startedAfter` (string, 可選) — UTC ISO-8601,例 `"2026-05-01T00:00:00Z"`
- `onlyOpen` (bool, 預設 false) — true 只回 `ClosedAt is null` 的
- `includeMessages` (bool, 預設 false) — true 會額外展開前 50 則訊息(`$orderby=CreatedAt`)

**排序:** `StartedAt desc`(固定)

**範例:**
- 今天還開著的對話:`onlyOpen=true, startedAfter="2026-05-20T00:00:00Z"`
- 連同訊息一起拿:`includeMessages=true`(會比較大)

---

## get_conversation

取單一對話。**預設會展開前 100 則 messages**(`$orderby=CreatedAt`)。

**參數:**
- `id` (uuid, 必填)
- `includeMessages` (bool, **預設 true**) — 設 false 只回對話本身,不展開訊息

**坑:** 預設展開造成回應變大;只要 metadata 時記得 `includeMessages=false`。

---

## list_messages

列訊息。**不能搜內容**,要搜內容用 `search_messages`。

**參數:**
- `top` (int, 預設 100, 上限 1000)
- `conversationId` (uuid, 可選) — 限定單一對話
- `senderType` (string, 可選) — `"User"` / `"Bot"` / `"Agent"`
- `intent` (string, 可選) — 精確匹配,例 `"greeting"`
- `includeDeleted` (bool, 預設 false) — 預設過濾 `IsDeleted=true`
- `order` (string, 預設 `"desc"`) — `"desc"` 新→舊 / `"asc"` 舊→新

**排序:** 依 `order` 參數,`CreatedAt` asc/desc

**範例:**
- 某對話的所有訊息(由舊到新):`conversationId=..., order="asc"`
- 所有打招呼:`intent="greeting"`
- 客服發的訊息:`senderType="Agent"`

---

## search_messages

訊息內容全文搜尋(`contains` 比對 `ContentJson`)。

**參數:**
- `text` (string, **必填**) — 子字串
- `top` (int, 預設 50)
- `conversationId` (uuid, 可選) — 限定單一對話

**內定篩選:** `IsDeleted eq false`(不搜已刪除)
**排序:** `CreatedAt desc`(固定)

**範例:**
- 找提到「退貨」的訊息:`text="退貨"`
- 限定某對話內搜尋:`text="運費", conversationId=...`

**坑:**
- 比對的是 `ContentJson` 的原始字串,可能包含 JSON 結構字元
- 不支援正則,只支援 substring

---

## get_message

取單一訊息。

**參數:**
- `id` (uuid, 必填)

---

## list_nlu_logs

列 NLU 模型呼叫記錄。用來偵錯 intent 分類、tool 選擇行為。

**參數:**
- `top` (int, 預設 50)
- `conversationId` (uuid, 可選)
- `stage` (string, 可選) — 例 `"intent"`, `"tool_selection"`
- `model` (string, 可選) — Model 名稱精確匹配
- `minLatencyMs` (int, 可選) — 只回延遲 ≥ 此值的(例 1000 = 1 秒以上)
- `onlyErrors` (bool, 預設 false) — 只回 `ErrorMessage != null` 的

**排序:** `CalledAt desc`(固定)

**範例:**
- 找超過 2 秒的呼叫:`minLatencyMs=2000`
- 找錯誤:`onlyErrors=true`
- 找特定階段:`stage="intent"`

---

## get_nlu_log

取單一 NLU log。

**參數:**
- `id` (uuid, 必填)

---

## query_odata

通用 OData v4 唯讀查詢(escape hatch)。**先確認 9 個專用工具都做不到再用。**

**參數:**
- `entity` (string, **必填**) — `"Agents"` / `"Conversations"` / `"Messages"` / `"NluCallLogs"`(其他會報錯)
- `filter` (string, 可選) — OData `$filter` 運算式
- `select` (string, 可選) — 逗號分隔欄位,例 `"Id,Name,CreatedAt"`
- `orderby` (string, 可選) — 例 `"CreatedAt desc"`
- `top` (int, 預設 50, 上限 1000)
- `skip` (int, 可選) — 分頁
- `expand` (string, 可選) — 例 `"Messages($top=10;$orderby=CreatedAt)"`
- `count` (bool, 可選) — true 會回 `@odata.count`

**範例:**
- 用 `$select` 節省 token:`entity="Messages", select="Id,Intent,CreatedAt", top=200`
- 複雜 filter:`entity="Messages", filter="(Intent eq 'greeting' or Intent eq 'farewell') and IsDeleted eq false"`
- 分頁:`entity="Conversations", top=50, skip=100, orderby="StartedAt desc"`
- 看總數:`entity="Messages", count=true, top=1`

**OData filter 操作符:**
- 比較:`eq`, `ne`, `gt`, `ge`, `lt`, `le`
- 邏輯:`and`, `or`, `not`
- 函數:`contains(field, 'x')`, `startswith(field, 'x')`, `endswith(field, 'x')`
- null 比對:`field eq null`, `field ne null`
- 字串值用單引號:`Intent eq 'greeting'`
- Guid 不用引號:`ConversationId eq 00000000-0000-0000-0000-000000000000`
- DateTime 用 ISO-8601 不加引號:`CreatedAt ge 2026-05-01T00:00:00Z`

**坑:**
- 字串中的單引號要用兩個單引號逸出:`'O''Brien'`
- 預設沒有 `IsDeleted eq false` 過濾(跟 `list_messages` 不一樣),要自己加
- entity 寫錯會回 JSON 錯誤,不會丟例外

---

## 共通回應格式

成功:OData JSON,通常是
```json
{
  "@odata.context": "...",
  "value": [ ... ]
}
```

或單筆(get_*):
```json
{
  "@odata.context": "...",
  "Id": "...",
  ...
}
```

失敗(`ok: false`):
```json
{
  "ok": false,
  "error": "...",
  "url": "...",
  "response": "..."
}
```

判斷成功:看有沒有 `@odata.context` 或 `value`;失敗看 `ok: false`。
