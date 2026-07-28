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

<選單路徑、誰在用、業務目的。一段話。>

## 畫面與欄位

| 欄位 | 顯示文字 | 類型 | 選項（label ↔ 儲存值） | 生命狀態 |
|---|---|---|---|---|
| MIL_STATUS | 兵役狀態 | Translate | 免役=E / 服役中=S / … | E：使用中（資料 N 筆） |

<動態 label / 動態選項標 DYNAMIC_RUNTIME 並附 evidence。>

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
