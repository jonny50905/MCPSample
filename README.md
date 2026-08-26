# HanshinChat MCP + OData + Elasticsearch

四個 .NET 8 專案：
- **`src/HanshinChat.OData.Api`** — read-only OData v4 API，吃本地 SQL Server 的 `HanshinChat` 資料庫
- **`src/HanshinChat.Mcp.Server`** — stdio MCP server，工具 description 完整版
- **`src/HanshinChat.Mcp.Server.Skill`** — stdio MCP server，工具 description 精簡版（搭配 Claude Code skill 使用）
- **`src/HanshinChat.Mcp.ElasticSearch.Skill`** — stdio MCP server，連 Elasticsearch，負責**第一層全文 / 關鍵字搜尋**（搭配 skill 使用）

```
                                ┌─► HanshinChat.Mcp.ElasticSearch.Skill ──(HTTP)─► Elasticsearch:9200    (第一層：全文搜尋 → MessageId)
Claude Code ──(stdio JSON-RPC)──┤
                                └─► HanshinChat.Mcp.Server(.Skill) ──(HTTP)─► HanshinChat.OData.Api ──(TDS)─► localhost\HanshinChat   (第二層：補明細)
```

**雙層搜尋：** Claude 先用 elasticsearch-skill 拿到命中 MessageId（含 highlight 片段），再用 hanshinchat-skill 補完整 metadata / 對話脈絡。

## 前置需求

- .NET 8 SDK
- 本地 SQL Server，DB 名稱 `HanshinChat`，使用 Windows 整合驗證
- Claude Code CLI

## 啟動

### 1. OData API

```powershell
cd D:\TMP\MCPDemo
dotnet run --project src\HanshinChat.OData.Api
```

預設 `http://localhost:5050`，常用入口：

| URL | 說明 |
|---|---|
| `/odata` | Service document（列出 entity sets） |
| `/odata/$metadata` | EDM schema |
| `/odata/Agents?$top=5` | Query example |
| `/odata/Messages?$filter=Intent eq 'greeting'&$top=10&$orderby=CreatedAt desc` | 篩選 + 排序 |
| `/odata/Conversations?$expand=Messages($top=3)` | $expand |
| `/swagger` | Swagger UI |

寫入動詞（POST / PUT / PATCH / DELETE / MERGE）一律回 `405 Method Not Allowed`。

### 2. MCP Server

Build 兩個 server：

```powershell
dotnet build src\HanshinChat.Mcp.Server
dotnet build src\HanshinChat.Mcp.Server.Skill
```

#### 原版（完整 description）

```powershell
claude mcp add -s user hanshinchat -- dotnet "D:\TMP\MCPDemo\src\HanshinChat.Mcp.Server\bin\Debug\net8.0\HanshinChat.Mcp.Server.dll"
```

#### Skill 面向版（精簡 description，搭配 Claude Code skill 省 token）

```powershell
claude mcp add -s user hanshinchat-skill -- dotnet "D:\TMP\MCPDemo\src\HanshinChat.Mcp.Server.Skill\bin\Debug\net8.0\HanshinChat.Mcp.Server.Skill.dll"
```

> 注意：執行時 OData API 必須正在跑。
> 兩個 server 共用同一個 OData API，可並行掛載作對照，或只掛 skill 版。
> 用 `claude mcp list` 確認已註冊；`/mcp` 可看工具清單。

### 3. Elasticsearch MCP Server（第一層搜尋）

Build：

```powershell
dotnet build src\HanshinChat.Mcp.ElasticSearch.Skill
```

註冊：

```powershell
claude mcp add -s user elasticsearch-skill -- dotnet "D:\TMP\MCPDemo\src\HanshinChat.Mcp.ElasticSearch.Skill\bin\Debug\net8.0\HanshinChat.Mcp.ElasticSearch.Skill.dll"
```

連線設定 `src/HanshinChat.Mcp.ElasticSearch.Skill/appsettings.json`：

```json
{
  "ElasticSearch": {
    "BaseUrl": "http://localhost:9200",
    "Username": null,
    "Password": null,
    "DefaultIndex": "hanshinchat-messages"
  }
}
```

> 假設 ES 索引已由其他系統建好（內含 HanshinChat 訊息）；本 MCP 不負責 indexing。
> 若 `Username` + `Password` 兩者皆有則用 Basic auth，否則匿名。

工具清單：

| 工具 | 用途 |
|---|---|
| `search` | 全文 / 關鍵字搜尋（Lucene query string），回傳 hits + highlight |
| `count` | 估算命中筆數 |
| `get_document` | 已知 `_id` 取單筆 |
| `list_indices` | 列出可查的 index 名稱 |

工具選擇與雙層搜尋工作流詳見 `.claude/skills/elasticsearch-mcp/SKILL.md`。

### 4. Claude Code Skill

Skill 檔目錄：

| Skill | 路徑 | 用途 |
|---|---|---|
| `hanshinchat-mcp` | `.claude/skills/hanshinchat-mcp/` | OData 工具選擇指引 |
| `elasticsearch-mcp` | `.claude/skills/elasticsearch-mcp/` | 第一層全文搜尋工作流（先 ES → 再 hanshinchat 補明細） |
| `eli5` | `.claude/skills/eli5/` | `/eli5 <主題>` — 用大圖、少量文字產出 HTML 懶人包，把任何主題講到零基礎也懂 |

兩個 MCP skill 都包含 `SKILL.md`（觸發條件 + 工具決策表）與 `tool-usage.md`（按需讀取的詳細參數）；`eli5` 只有一個 `SKILL.md`。

> `eli5` 來源：Anthropic 官方社群 plugin repo [anthropics/claude-plugins-community](https://github.com/anthropics/claude-plugins-community/tree/main/eli5)（MIT，作者 Thariq Shihipar），原版收錄。

Claude Code 只讀 `~/.claude/skills/`（user-level）。要讓 Skill 生效，需各建一個 Junction 指向本 repo：

```powershell
# 建立 user-level skills 目錄
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\skills"

# Junction：hanshinchat-mcp
New-Item -ItemType Junction `
  -Path "$env:USERPROFILE\.claude\skills\hanshinchat-mcp" `
  -Target "D:\TMP\MCPDemo\.claude\skills\hanshinchat-mcp"

# Junction：elasticsearch-mcp
New-Item -ItemType Junction `
  -Path "$env:USERPROFILE\.claude\skills\elasticsearch-mcp" `
  -Target "D:\TMP\MCPDemo\.claude\skills\elasticsearch-mcp"

# Junction：eli5
New-Item -ItemType Junction `
  -Path "$env:USERPROFILE\.claude\skills\eli5" `
  -Target "D:\TMP\MCPDemo\.claude\skills\eli5"
```

驗證：

```powershell
ls "$env:USERPROFILE\.claude\skills\hanshinchat-mcp"
ls "$env:USERPROFILE\.claude\skills\elasticsearch-mcp"
ls "$env:USERPROFILE\.claude\skills\eli5"
```

## MCP 工具清單

| 工具 | 用途 |
|---|---|
| `query_odata` | 通用 — entity + $filter/$select/$orderby/$top/$skip/$expand/$count |
| `list_agents`, `get_agent` | 客服 |
| `list_conversations`, `get_conversation` | 對話 (可 $expand Messages) |
| `list_messages`, `search_messages`, `get_message` | 訊息 (`search_messages` 對 ContentJson 做 contains) |
| `list_nlu_logs`, `get_nlu_log` | NLU 呼叫紀錄 |

> 工具選擇指引詳見 `.claude/skills/hanshinchat-mcp/SKILL.md`。

## 設定

### OData base URL（給 MCP server 用）

`src/HanshinChat.Mcp.Server/appsettings.json`：

```json
{ "OData": { "BaseUrl": "http://localhost:5050/odata/" } }
```

### DB 連線字串

`src/HanshinChat.OData.Api/appsettings.json`：

```json
"ConnectionStrings": {
  "HanshinChat": "Server=localhost;Database=HanshinChat;Trusted_Connection=True;TrustServerCertificate=True;"
}
```

## Read-only 保證

寫入封鎖有 3 層：
1. `ReadOnlyMethodFilterMiddleware`：對 `/odata/*` 的所有寫入動詞回 405
2. Controllers 只暴露 GET，沒有寫入 action
3. `HanshinChatContext.SaveChanges{,Async}()` 覆寫為 `throw InvalidOperationException`，並全域 `NoTracking`
