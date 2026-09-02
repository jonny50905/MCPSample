---
description: 分批稽核（auto-loop 專用）：依 docs/ps-research/<領域>/audit-parts/manifest.txt 只稽核本批檔案／範圍，結果只寫 audit-parts/；不寫 checklist、不寫 90-audit.md
agent: ps-deep-research
---
對 `docs/ps-research/$ARGUMENTS/` 執行**一個稽核批次**（L107／issue #22）。
**本指令不是稽核模式**：你 system prompt 的「稽核模式」章節在此**不適用**
——不寫 90-audit.md、不寫 checklist.md、不遞增輪次、不翻旗標、不歸檔、
不改任何 NN 檔、不寫 log.md。你只做三件事：read manifest → 逐筆委派
@ps-auditor → 把回報**照抄成表**寫進 manifest 指定的**那一個** part 檔。

**第一個回應必須是工具呼叫**：`read docs/ps-research/$ARGUMENTS/audit-parts/manifest.txt`
（$ARGUMENTS 應為單一領域目錄名；read 失敗且含空白時取第一個詞重試一次；
manifest 不存在 → 回報「無 manifest，本指令只供 auto-loop 呼叫」後結束）。
manifest 是外環產生的唯讀工單：目標輪次、旗標、本批檔案（每檔 Evidence
列數、範圍切段、任務 B claims）、領域任務、「## 輸出」唯一可寫路徑。
**不在清單內的檔一律不碰；清單怎麼切你怎麼做。**

## 委派規則

- **一個委派只做一件事**：一個檔的**一個範圍**的任務 A、或一個檔的任務 B
  ——禁止把多檔、多範圍、A＋B 塞進同一委派。委派對象只准 @ps-auditor。
- 併發：會查 oracleMCP 的（SQL 型證據重跑、任務 C）同時 ≤ 3；只用 ES＋Source
  的同時 ≤ 6；總數 ≤ 6。不要全循序。
- 任務 A 模板（只傳路徑，不貼內容）：
  `[任務] read docs/ps-research/$ARGUMENTS/<檔名> 執行任務 A（證據解引用），只驗 Evidence 附錄第 a~b 筆`
  ——範圍寫「全」時不加範圍限定；manifest 旗標為「待執行」時末尾加
  「本檔查無宣告抽驗全量做（不只抽 1~2 筆）」。
- 任務 B 模板：`[任務] read docs/ps-research/$ARGUMENTS/<檔名> 執行任務 B（反駁驗證），claims：<manifest 給的 claims 逐字>`
  ——**claims 只准用 manifest 給的**；manifest 註明無可抽取 claim 時不委派
  任務 B，該檔 VERIFIED／DISPUTED 填 0，明細加一列
  `| <檔> | claim UNVERIFIABLE | （無） | 行為邏輯節無可機械抽取的 CONFIRMED 行 | 回灌補寫 CONFIRMED 標註 |`。
- 委派失敗（回報空／只回「已讀取契約」／invalid tool JSON）→ 縮短 prompt
  重試一次；再失敗 → 該範圍整段記 UNVERIFIABLE（原因：委派失敗），
  **不得原樣重試第三次**。

## 計數規則（照抄，不詮釋）

auditor 每筆 verdict 只有 PASS／FAIL(原因)／UNVERIFIABLE(原因)；claim 只有
VERIFIED／DISPUTED／UNVERIFIABLE；自創詞就近映射（claim→DISPUTED、證據→FAIL）。
- PASS 欄＝PASS 與 PASS(LINE_DRIFT)；FAIL 欄＝所有 FAIL(*)；
  UNVERIFIABLE 欄＝UNVERIFIABLE(*)，**但 UNVERIFIABLE(PENDING_MANUAL) 另計
  PENDING_MANUAL 欄、不重複計**；VERIFIED／DISPUTED＝任務 B 結果。
- 每個範圍 PASS＋FAIL＋UNVERIFIABLE＋PENDING_MANUAL **必須等於範圍筆數**
  ——回報少了就再委派補齊；仍缺＝該範圍整段 UNVERIFIABLE（原因：auditor
  回報不足）。外環會機械核對，數字對不上＝本檔無收據＝白做。
- 查無宣告抽驗結果**不計入四欄**，FALSE_NEGATIVE 只寫明細（類型
  「查無抽驗 FAIL(FALSE_NEGATIVE)」）。

## 輸出（只寫 manifest「## 輸出」所列的那一個檔）

檔案批次寫 `docs/ps-research/$ARGUMENTS/audit-parts/part-<批號>.md`，
**只有兩張表，欄名逐字照抄，一個範圍一列，檔案欄寫完整檔名**：

```markdown
## 記分卡
| 檔案 | 範圍 | PASS | FAIL | UNVERIFIABLE | PENDING_MANUAL | VERIFIED | DISPUTED |
|---|---|---|---|---|---|---|---|
| 01-TW_X.md | 1-10 | 8 | 2 | 0 | 0 | 3 | 0 |
| 01-TW_X.md | 11-15 | 5 | 0 | 0 | 0 | 0 | 0 |

## 明細
| 檔案 | 類型 | 內容 | 原因 | 處置 |
|---|---|---|---|---|
| 01-TW_X.md | 證據 FAIL(ID_RELINK) | ChunkId <完整 36 字元舊 id> | 文件說…；實際取到…；差異… | 換 id：<完整舊 UUID> → <完整新 UUID> |
```

- 明細：每筆非 PASS 判定一列（含 PENDING_MANUAL）；「內容」欄的 ChunkId
  **逐字取自該檔附錄，禁止縮寫、禁止捏造**（外環核對每個 id 都在該檔附錄）；
  「處置」欄：ID_RELINK 寫 `換 id：<舊> → <新>`、LINE_DRIFT 寫
  `更新行號 → <新>`、STALE_DATA 寫 `更新數值 → <新>`，其餘「回灌補查」；
  任務 B 的 DISPUTED 也進明細（類型「claim DISPUTED」，原因三要素）。

領域批次（manifest 批次 0）寫 `docs/ps-research/$ARGUMENTS/audit-parts/domain.md`：

```markdown
## 完整性
- 任務 C 覆蓋：完成 N／共 M 批（未完成批次：<逐批列出，或「無」>）
| 候選物件 | 型別 | 經由表 | 方向 | origin | 分類 | 理由 |
|---|---|---|---|---|---|---|
| TW_ABC | Component | PS_JOB | WRITE | CUSTOM_PREFIX | DOMAIN_ROOT | 命中 aliases「職缺」且 UI 選單屬本流程 |

## wiki 記分卡
| 檔案 | 範圍 | PASS | FAIL | UNVERIFIABLE | PENDING_MANUAL | VERIFIED | DISPUTED |
|---|---|---|---|---|---|---|---|
| wiki/TW_ABC.md | 全 | 4 | 0 | 1 | 0 | 0 | 0 |

## wiki 明細
| 檔案 | 類型 | 內容 | 原因 | 處置 |
|---|---|---|---|---|
```

- 任務 C：核心資料表清單 read `00-overview.md` 取得，**每批 ≤5 張表一個
  委派**（auditor 回傳結構化候選 name／type／viaTable／direction／origin），
  聯集後**逐候選過 Domain Gate 三分**（規則同你 system prompt 稽核模式：
  DOMAIN_ROOT＝業務證據＋origin 符合 business-domain-map 的 rootObjectPolicy；
  DEPENDENCY＝被 root 使用的共用／原生依附；OUT_OF_SCOPE＝僅因共用表反查到；
  判不準＝OUT_OF_SCOPE 待人工）。已有 NN 檔的物件不列。只有 DOMAIN_ROOT
  會被外環寫成 D 項——**你不寫 D 項**。
- wiki 抽驗：對 manifest 列出的每個 entity 路徑各委派一次任務 A（只傳路徑）。
- 覆蓋率行**必填數字**；委派失敗的批次逐批列出，禁止寫「無」充數。

## 交付＝檔案，不是對話

寫 part 檔用**整檔 write**（小檔一次寫完），寫完 **read 回來確認**兩張表
都在、每個檔每個範圍都有列，再結束。只在對話裡印表格而沒有 write＝本批
白做（外環只驗檔案）。**最終回覆只准一行：「已寫 <路徑>」**。
不得反問、不得婉拒、不得先輸出計畫。
