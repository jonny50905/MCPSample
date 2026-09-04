# <NN> <功能名>（[[<Component / 物件名>]]）

> 所屬總覽：[00-overview.md](00-overview.md)　狀態：COMPLETE | PARTIAL | BLOCKED
> Origin：<CUSTOM_PREFIX | …>　搜尋政策：<mode>　Delivered fallback：<未使用 | 使用於…>

<!-- 物件細節寫進 wiki entity 檔（../wiki/<物件名>.md），本文用 [[物件名]]
     連結、不重複詳述；本文專注「功能流程」的敘事。 -->

## 相關物件

| 物件 | 角色 |
|---|---|
| [[TW_XXX]] | 主 Component |
| [[PS_YYY]] | 寫入目標 |

## 功能定位

<誰在用、業務目的。一段話。>

### 導覽入口

<依 cookbook §2k 取得的 Portal Registry 入口；每個入口一列。沒查證就整段寫
 「Portal Registry 導覽入口：未確認（navigation metadata 尚未查證）」。>

| # | Portal | 入口型 | 導覽入口（Portal Registry 登錄路徑） | 可見性 | 語系／來源 | 證據 |
|---|---|---|---|---|---|---|
| 1 | EMPLOYEE | PORTAL_REGISTRY | 招募 > 應徵者管理 > 維護應徵者 | REGISTRY_DEFINED | ZHT／LANG（第 2 段 fallback ENG） | E01.4 |

<!-- 入口型：PORTAL_REGISTRY / CREF_LINK / NAV_COLLECTION / FLUID_TILE / NAVBAR / UNKNOWN
     可見性：REGISTRY_DEFINED（Registry 中登錄的入口，未經 user／security context 驗證）
             AUTHORIZED_FOR_CONTEXT（**本版不得產出**，需 user/security context）
             UNKNOWN_VISIBILITY（祖先 hidden-from-nav／CREF 過期／走訪未達根／未解析 surface）
     多入口就寫多列——CREF Link 讓同一畫面出現在多個位置，**壓成一列＝誤報**。
     未實作的 surface（Navigation Collection／Fluid Tile／NavBar）**即使查無也要在「未解事項」記一行 gap**，
     不得宣稱「唯一入口」。值域見 mcp-tool-contracts.md §3。 -->

### Technical Menu

<PSMENUITEM 的 MENUNAME / BARNAME / ITEMNAME，以「/」分隔，多筆用分號。
 這是 App Designer 技術選單 metadata，**不是使用者點得到的路徑**。>

RECRUITING / USE / MANAGE_APPLICANTS

<!-- 絕不可把這一段當成「導覽入口」的 fallback：8.4 之後 BARNAME（USE／PROCESS／
     INQUIRE…）在 PIA 沒有對應層級，串成 A > B > C 就是誤報（issue #24 Case 1）。
     兩段是兩個 claim，各自附證據，缺哪段就照實寫未確認。 -->

## 畫面與欄位

| 欄位 | 顯示文字 | 類型 | 選項（label ↔ 儲存值） | 生命狀態 |
|---|---|---|---|---|
| MIL_STATUS | 兵役狀態 | Translate | 免役=E / 服役中=S / … | E：使用中（資料 N 筆） |

<動態 label / 動態選項標 DYNAMIC_RUNTIME 並附 evidence。>

<!-- 物件無畫面（Function Library 等）：標題保留，內文寫
     「（無——Function Library，無使用者畫面）」——不適用要申報，
     不能省略標題（標題是機器契約，L103）。 -->

## 行為邏輯

<條件 → 動作，逐項標信心等級：>

- **CONFIRMED**：選 E 時開放免役原因並帶入日期（`<filePath>:<行號>`）
- **DYNAMIC_RUNTIME**：核准後回寫的目標表由設定檔決定（`<filePath>:<行號>`）

## 資料流

| 表 | 操作 | 來源 | 信心 |
|---|---|---|---|
| PS_TW_XXX | UPDATE | 存檔 PeopleCode | CONFIRMED |

## 執行方式

<線上操作 / 批次（Process、排程、Run Control 頁面）。>

## 權限

<Menu → Component → Permission List → Role（人數彙總）。>

## 未解事項（gaps）

- <查不到、超出 budget、工具受限的部分——誠實列出>

## Evidence 附錄

| # | 位置 | 說明 | 機器參照 |
|---|---|---|---|
| 1 | `peoplecode/TW_XXX/.../FieldChange.pcode:12-24` | E 分支條件 | ChunkId `3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d` |

<!-- ChunkId 一律逐字複製「完整 36 字元 UUID」（如上例長度）——
     它不是 git SHA，**禁止縮寫成前 8 碼**；縮寫會被稽核判
     FAIL(TRUNCATED_ID)、lint 也會抓。 -->
| 2 | SQL：`SELECT … FROM PSXLATITEM …` | 選項清單 | keyRows：E=免役… |
| 3 | `PS_PRCSRECUR`（RECURNAME='X'） | 排程週期 | 待人工SQL |

<!-- 機器參照欄只准放三種東西之一（lint 逐列檢查，L55）：
     (a) 完整 36 字元 ChunkId
     (b) 可重跑的 SELECT … FROM …
     (c) 待人工SQL ← **查不到時的合法出口**
     「ChunkId」「PeopleCode chunk」「OracleMCP SQL」這類**只是標籤不是證據**
     ——稽核重跑時跑不了任何東西，一律判違規。
     取不到證據時**照型別走對應出口**，不要用敘述搪塞：
       · SQL／metadata 型（查 DB 表）查不到 → 機器參照寫 `待人工SQL`
         （管理者自跑 SQL 後回填）
       · CHUNK 型（程式碼）取不到 → **移除該列**、把該主張降級 INFERRED
       兩者都要在「未解事項」記一行查法收據（查了什麼、怎麼查、結果如何）
     **更不要在 gaps 寫「環境限制」當跳過理由**——宣稱受限卻沒有任何一列
     走出口，lint 會直接點名（L56）；真的受限就走出口，那才叫申報。 -->
