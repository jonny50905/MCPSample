# HanshinChat MCP + OData

三個 .NET 8 專案：
- **`src/HanshinChat.OData.Api`** — read-only OData v4 API，吃本地 SQL Server 的 `HanshinChat` 資料庫
- **`src/HanshinChat.Mcp.Server`** — stdio MCP server，工具 description 完整版
- **`src/HanshinChat.Mcp.Server.Skill`** — stdio MCP server，工具 description 精簡版（搭配 Claude Code skill 使用）

```
Claude Code ──(stdio JSON-RPC)──► HanshinChat.Mcp.Server(.Skill) ──(HTTP)──► HanshinChat.OData.Api ──(TDS)──► localhost\HanshinChat
```

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

### 3. Claude Code Skill

Skill 檔案位於 `.claude/skills/hanshinchat-mcp/`，包含兩個檔案：

| 檔案 | 用途 |
|---|---|
| `SKILL.md` | 觸發條件 + 工具決策表，Claude 自動載入 |
| `tool-usage.md` | 每個工具的完整參數與範例，僅按需讀取 |

**Skill 讓 Claude 在呼叫 MCP 前先選對工具，避免誤用 `list_messages` 或直接 fallback 到 `query_odata`。**

Claude Code 只讀 `~/.claude/skills/`（user-level）。要讓 Skill 生效，需建立 Junction 指向本 repo：

```powershell
# 建立 user-level skills 目錄
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\skills"

# 建立 Junction（不需管理員權限，版控跟著 repo 走）
New-Item -ItemType Junction `
  -Path "$env:USERPROFILE\.claude\skills\hanshinchat-mcp" `
  -Target "D:\TMP\MCPDemo\.claude\skills\hanshinchat-mcp"
```

驗證：

```powershell
# 應列出 SKILL.md 和 tool-usage.md
ls "$env:USERPROFILE\.claude\skills\hanshinchat-mcp"
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
