# 知識檢索契約（問答時怎麼用 wiki 與 NN 研究文件）

適用：ps-orchestrator 第 3 步（取代「只查 wiki」）。目的：已研究、已稽核的 NN 文件
（`docs/ps-research/<領域>/NN-<物件>.md`）和 Entity Wiki 一起成為問答的知識來源，
而且用固定的呼叫形狀、固定的預算、固定的來源標註——不是「自由翻文件」。

索引檔（機械產生、本機快取、勿手改）：
`docs/ps-research/knowledge/index.md`（領域／Wiki／NN 三張表）、
`docs/ps-research/knowledge/objects.md`（物件彙總表）。
索引只給**定位**（哪個檔、哪一節從第幾行起、幾行）與**旗標**（等級、有效性）；
**內容永遠讀原檔**。索引不存在或過時都有兜底（第 1 步末段、第 3 步雙端自檢）。

## 1. 定位（≤4 次 grep；只准下列呼叫形狀）

grep 工具不能指定單一檔案（path 只認目錄），所以一律 `path=目錄`＋`include=檔名`。
pattern 用 `[|] <物件名> [|]`（cell 錨定：直線放在字元類別裡，不用反斜線——反斜線經工具參數傳遞
容易掉，掉了 `|` 就變成「或」而命中整檔）才不會撈到別的物件的引用欄。

1. `grep(pattern="[|] <物件名> [|]", path="docs/ps-research/knowledge", include="index.md")`
   → 命中列可能來自「## Wiki」表（欄：物件／類型／狀態／有效性／人工／last_verified／來源數／引用NN／aliases）
   或「## NN」表（欄：領域／檔／主物件／續篇／等級／狀態／稽核／節（名@offset/limit）／證據／缺口／待補／hash；
   主物件欄永遠是純物件名，續篇檔另以「續篇」欄標「是」）。
2. 沒中 → `grep(pattern="<業務詞或 alias>", path="docs/ps-research/knowledge", include="index.md")`
   （命中 Wiki 表的 aliases 欄或 NN 表的主物件欄）。
3. 沒中 → `grep(pattern="[|] <物件名> [|]", path="docs/ps-research/knowledge", include="objects.md")`
   （物件彙總：類型／主物件於／引用NN數／引用於）→ 取「主物件於」或「引用於」的 `領域/檔`，
   回到 index.md 的 NN 列取節 offset／limit（再一次 grep，pattern=該檔名）。
4. 仍沒中、或 index.md 不存在 →
   `grep(pattern="<物件名>", path="docs/ps-research", include="[0-9][0-9]-*.md")` **一次**；
   命中的 NN 一律視為等級 `UNAUDITED`、來源標「索引過時」。
   索引檔不存在 → 答覆註明「知識索引未建（管理者跑 `scripts\ps-knowledge.ps1 -Rebuild`）」。

## 2. 挑選

- Wiki 列 ≤3（整檔 read；檔路徑固定 `docs/ps-research/wiki/<物件名>.md`，物件名逐字取自 Wiki 列第一欄；
  `status`／有效性看索引列，不看檔內）。
- NN 列 ≤3：等級順序 `AUDITED_CLEAN` ＞ `AUDITED_ISSUES` ＞ `UNAUDITED` ＞ `PARTIAL` ＞ `BLOCKED`；
  同級取稽核輪次新者。同主物件的續篇檔（`-2.md`）算同一個 NN 名額。
- 等級意義：`AUDITED_CLEAN`＝COMPLETE、最新記分卡零 FAIL 零 DISPUTED、無待補、稽核後未改；
  `AUDITED_ISSUES`＝稽核過但有 FAIL／DISPUTED／待補或稽核後改過；`UNAUDITED`＝沒進過記分卡；
  `PARTIAL`／`BLOCKED`＝檔頭狀態。

## 3. 片段讀取（只讀問題型別對應的節）

| 問題型別 | 讀哪一節 |
|---|---|
| 選項含意、欄位、畫面文字 | 畫面與欄位 |
| 行為、條件、存檔後動作 | 行為邏輯＋資料流 |
| 批次、排程、Run Control | 執行方式 |
| 誰能用、授權 | 權限 |
| 在哪裡進入、功能定位 | 功能定位（含導覽入口／Technical Menu） |
| 要證據參照 | Evidence 附錄 |

呼叫：`read(filePath="docs/ps-research/<領域>/<檔>", offset=<offset>, limit=<limit>)`
（offset／limit 逐字取自 NN 列「節」欄的 `節名@offset/limit`，**直接用、不加減**——limit 已含該節標題到
節末的行數；`@缺`＝該節不存在，不讀）。

**首行自檢（每次 read 都做）**：回來的第一行必須以 `## ` 開頭，而且去掉空白與括號註記後的標題名
要以索引「節」欄的節名開頭（`## Evidence 附錄`、`## 未解事項（gaps）` 都算對上）。只檢查第一行，
不檢查最後一行。第一行不符、或 read 回 `Offset … out of range` → 以
`grep(pattern="^## <節名>", path="docs/ps-research/<領域>", include="<NN 檔名>")` 重新定位**一次**
（取第一筆的行號當 offset、limit 同原值），並把該檔等級視為 `UNAUDITED`、來源標「索引過時」。

預算：每個 NN ≤2 節、每節一次 read、每個 NN ≤1 次重定位；總計 ≤400 行、≤6 次 read（wiki 不計）。
超過就換下一等級的 NN，或在來源表標「片段未讀完」。

## 4. 知識夠不夠 vs 必須現查（子問句覆蓋）

把問題拆成子問句；每個子問句要有**一條帶證據參照的主張**才算覆蓋。以下**必須現查**（委派 subagent）：

- 沒有任何來源覆蓋該子問句。
- 問的是**現況**：值分布、筆數、還在不在用、誰現在能進、目前排程。
- 關鍵主張只有 INFERRED／DYNAMIC_RUNTIME。
- 來源等級不是 `AUDITED_CLEAN`，而且沒有 wiki `verified` 條目佐證同一事實。
- **wiki 與 NN 對同一事實矛盾**：兩者並陳、必現查、以現查結果為準
  （wiki `reviewed: true` 或 `human:<日期>` 較新只影響並陳順序，不免除現查）。
- 來源標了「索引過時」。

Wiki 列的有效性欄只有 `verified` 算已驗證；`draft` 是草稿；`stale`／`STALE_BY_SOURCE`／`EXPIRED`／`UNKNOWN`
一律視同 stale（來源 NN 被稽核判 FAIL、超過有效期、或無法判定），只當線索、必現查。

其餘情況：知識（wiki＋NN）沒有或不足才現查——這是既有的「wiki 沒有才現查」規則的擴大版。

## 5. 來源標註（每項結論）

`wiki（已驗證）`／`wiki（人工審定）`／`wiki（草稿，未經現查）`／`wiki（已過期／來源失效，未經現查）`／
`NN：<領域>/<檔>（AUDITED_CLEAN，第 N 輪）`／`NN：<領域>/<檔>（AUDITED_ISSUES｜UNAUDITED｜PARTIAL｜BLOCKED，未經現查）`／
`NN：<領域>/<檔>（索引過時）`／`本次現查`。
索引有效性 → 標籤：`verified`＝wiki（已驗證）（人工欄「是」＝wiki（人工審定））；`draft`＝wiki（草稿，未經現查）；
`stale`／`STALE_BY_SOURCE`／`EXPIRED`／`UNKNOWN`＝wiki（已過期／來源失效，未經現查）。
證據參照逐字複製 NN 附錄的 ChunkId（完整 36 字元）或 SQL；不得自己改寫。

## 6. 答覆結尾固定「## 來源表」

```text
## 來源表
| 子問句 | 來源 | 等級 | 證據參照 | 現查 |
|---|---|---|---|---|
| 免役選項存什麼值 | NN：兵役/03-TW_MIL001.md | AUDITED_CLEAN | ChunkId 3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d | 否 |
| 目前有幾筆免役 | 本次現查 | 現查 | SQL：SELECT … FROM PS_TW_MIL … | 是 |
```

封閉值：等級 ∈ {AUDITED_CLEAN, AUDITED_ISSUES, UNAUDITED, PARTIAL, BLOCKED, wiki verified, wiki draft,
wiki stale, 索引過時, 現查}；現查 ∈ {是, 否}。索引有效性 `stale`／`STALE_BY_SOURCE`／`EXPIRED`／`UNKNOWN`
在來源表一律寫 `wiki stale`。等級不是 `AUDITED_CLEAN` 也不是 `wiki verified` 的列，
現查必為「是」。每列來源與證據參照不得空白。

## 7. 產出前輕稽核（第 7 步的縮減）

wiki `verified` 與 NN `AUDITED_CLEAN` 的證據免驗。其他等級被引用的關鍵證據委派 @ps-auditor
任務 A 精簡版：只傳路徑＋「只驗 Evidence 附錄第 a~b 筆」，不貼內容。FAIL 的證據 → 對應結論降級或剔除。

## 8. 查不到與補研究建議

「查不到」的門檻不變：未經本次現查不得輸出查無。現查後仍缺、而且該物件已有 NN 檔時，
在答覆末尾印出固定指令請管理者提交補研究（模型**不寫** request 檔）：

```text
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-supplemental.ps1 -New -Target COMPONENT:<物件名> -FactKind <能力目錄代號> -Properties <屬性,屬性> -DomainHint <領域>
```

能力目錄代號與屬性見 `.opencode/peoplesoft/spec/capabilities.json`（例：`DATA.FILE_INPUT` 的 `present,layout,fields`）。
該領域尚無研究 → 建議 `/ps-research <領域>`；答錯的事實 → 建議 `/ps-correct <正確知識>`。
