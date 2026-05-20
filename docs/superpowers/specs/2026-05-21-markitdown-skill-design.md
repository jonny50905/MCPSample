# markitdown Skill 設計文件

- **日期**：2026-05-21
- **狀態**：待 user 審核
- **目標**：撰寫一個 Claude Code skill，呼叫 Microsoft `markitdown` CLI，將 Office 檔案（Word / Excel / PowerPoint）轉成 Markdown。所有來源檔皆帶 AIP sensitivity label（部分加密），skill 須透過 Office COM 解密為無保護副本後才能轉換。

---

## 1. 範圍與觸發

### 1.1 Skill 安裝位置

- **路徑**：`D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md`
- **層級**：project-level（不建 Junction 到 `~/.claude/skills/`），只在這個 repo 下生效。
- **結構**：單檔 SKILL.md，無 reference 子檔。

### 1.2 支援副檔名

| 副檔名 | 對應 Office COM app |
|---|---|
| `.xlsx`, `.xls` | `Excel.Application` |
| `.docx`, `.doc` | `Word.Application` |
| `.pptx` | `PowerPoint.Application` |

範圍外（PDF / HTML / 圖片 / 音訊等）**不在此 skill 涵蓋**。Skill description 故意不提這些格式，避免 Claude 誤觸發。

### 1.3 Description（決定 Claude 何時觸發）

> Use when the user wants to convert Office documents (.xlsx / .xls / .docx / .doc / .pptx) to Markdown, or to read these documents' content as Markdown. Covers single-file conversion and batch conversion of all Office files under a folder (recursive). Source files are assumed to carry AIP sensitivity labels; the skill drives Office COM to produce unprotected copies before invoking markitdown. Outputs to `D:\MarkItDownOutPut\` mirroring source relative folder structure.

### 1.4 觸發決策表

| 使用者說 | 是否觸發 |
|---|---|
| 「幫我把 D:\Reports\Q1.xlsx 轉成 markdown」 | ✅ |
| 「D:\Reports\ 底下所有 Excel/Word 都轉成 markdown」 | ✅（批次） |
| 「讀一下這份 .docx 的內容」 | ✅（轉完後 Claude 接續 Read 輸出檔） |
| 「把 PDF 轉成 markdown」 | ❌ |
| 「寫一份 markdown 報告」 | ❌ |

---

## 2. 前置條件

Skill 在開始任何轉換前必須驗證以下三項，任一失敗即中止：

1. **markitdown CLI 已安裝**：`markitdown --version` 成功
   - 若失敗，提示 `pip install 'markitdown[all]'`，**不自動安裝**
2. **Office desktop 已安裝**：嘗試 `New-Object -ComObject Word.Application` 成功
   - 失敗訊息：`Office desktop (Word/Excel/PowerPoint) 未安裝或非 COM 可用版本`
3. **`config.json` 存在**：若不存在，進入「探索模式」（見 §6）

---

## 3. 輸出規則

### 3.1 輸出根目錄

固定為 **`D:\MarkItDownOutPut\`**。Skill 在跑任何轉換前先 `New-Item -ItemType Directory -Force` 確保存在。

### 3.2 單檔輸出

- 來源：`D:\anywhere\report.xlsx`
- 輸出：`D:\MarkItDownOutPut\report.md`
- 命名規則：去掉副檔名後加 `.md`
- **直接覆寫**已存在的同名輸出檔（一致、可重跑）

### 3.3 批次輸出（鏡像來源相對路徑）

- 使用者指定來源資料夾 `$SourceRoot`（例：`D:\Reports`）
- 來源檔 `D:\Reports\Q1\Sales\jan.xlsx`，相對路徑 = `Q1\Sales\jan.xlsx`
- 輸出 = `D:\MarkItDownOutPut\Q1\Sales\jan.md`
- 子資料夾不存在即建

### 3.4 中繼檔（COM 解密產物）

- 中繼根：`D:\MarkItDownOutPut\.tmp\`
- 命名：**鏡像來源相對路徑**，並把 basename 改成 `<basename>.unprotected.<原副檔名>`
  - 例：來源 `D:\Reports\Q1\Sales\jan.xlsx`，中繼檔 = `D:\MarkItDownOutPut\.tmp\Q1\Sales\jan.unprotected.xlsx`
  - 單檔模式無相對路徑，直接 `D:\MarkItDownOutPut\.tmp\<basename>.unprotected.<ext>`
- 成功轉完即刪（連同空出的中繼子資料夾保留，整批結束時可選擇清空）
- 失敗時保留供 debug，並列入失敗清單

---

## 4. 單檔流程

```
1. 確保 D:\MarkItDownOutPut\ 與 D:\MarkItDownOutPut\.tmp\ 存在
2. 啟動對應的 Office COM app（隱藏視窗、停用 alert）
3. Open（ReadOnly=true）來源檔
4. 讀取當前 SensitivityLabel
5. 比對 config.json 的 allowed_downgrades 政策（§6）
6. 若需要降階：SetLabel(target, justification)
7. SaveAs2 到中繼路徑（同格式，例如 .docx → .docx）
8. Close 文件
9. markitdown <中繼檔> -o <最終輸出>
10. 刪除中繼檔
11. Quit Office app（若為單檔則直接關；若為批次則保留共用）
```

若使用者意圖是「讀內容」（如「讀一下這份 .docx」），Claude 在步驟 10 之後 Read 最終輸出檔並摘要回覆。

---

## 5. 批次流程（資料夾遞迴）

### 5.1 篩選

- `Get-ChildItem -LiteralPath $SourceRoot -Recurse -File`
- 副檔名 ∈ {`.xlsx`, `.xls`, `.docx`, `.doc`, `.pptx`}（不分大小寫）
- 跳過 Office 暫存鎖檔 `~$*`

### 5.2 COM app 共用

每種 Office app（Word/Excel/PowerPoint）**整批只啟動一個 instance**，按副檔名分桶處理：

1. 蒐集所有來源檔，依副檔名分到三個桶
2. 對每個非空桶：啟動對應 COM app → 跑全桶 → Quit + `ReleaseComObject`

避免每檔啟停 Office 帶來的數量級慢速。

### 5.3 失敗不中斷

每檔包在 `try/catch`。任何例外（COM 失敗、SetLabel 被拒、markitdown 非零 exit code）寫入 `$failures` 陣列，繼續下一檔。

### 5.4 結束彙整

```
=== markitdown 轉換結果 ===
成功: N 檔，輸出在 D:\MarkItDownOutPut\
失敗: M 檔（詳見下）

[policy-forbidden]
  D:\Reports\board\strategy.docx  (label: B)

[unknown-source-label]
  D:\Reports\partners\nda.docx  (label-id: <guid>)
  → 解法：執行 skill 的「探索模式」把新 tier 加進 config.json

[markitdown-failed]
  D:\Reports\old\legacy.xls  (markitdown stderr: ...)
```

---

## 6. AIP Label 降階與政策

### 6.1 探索模式（first-run setup）

若 `config.json` 不存在，skill 進入互動式探索：

1. 提示使用者準備一份 sample 檔（已標為任意 label、可開、有權限）
2. Word/Excel COM 開檔 → `Document.SensitivityLabel.GetLabel()`
3. 印出 `LabelId` 與 `LabelName`，問使用者「這份對應哪一階？(A / B / C-internal / C-external / 其他)」
4. 重複到使用者輸入「探索完成」
5. 詢問 `unprotected_target`（預設建議 `C-external`）
6. 詢問 `allowed_downgrades` 規則清單（預設建議 `[{from: "C-internal", to: "C-external"}]`）
7. 寫入 `config.json`
8. **驗證**：拿一份 unprotected_target 的 sample，跑一次 SaveAs2 + markitdown 讀取，若失敗警告「unprotected_target 可能仍有加密，請改設更低 tier」

### 6.2 config.json schema

```json
{
  "labels": {
    "A":          { "id": "<guid>", "name": "<display>" },
    "B":          { "id": "<guid>", "name": "<display>" },
    "C-internal": { "id": "<guid>", "name": "<display>" },
    "C-external": { "id": "<guid>", "name": "<display>" }
  },
  "unprotected_target": "C-external",
  "allowed_downgrades": [
    { "from": "C-internal", "to": "C-external" }
  ]
}
```

存放位置：`D:\TMP\MCPDemo\.claude\skills\markitdown\config.json`
**`.gitignore` 必須包含這個檔案**（label GUID 屬租戶隱私）。

### 6.3 每檔決策邏輯

**Justification 文字**（傳給 `SetLabel`）固定為：
`"Convert to Markdown via markitdown skill"`

```python
sourceLabelId = doc.SensitivityLabel.GetLabel().LabelId
sourceTier    = labels_inverse_lookup(sourceLabelId)   # 用 id 反查 tier 名
target        = config.unprotected_target
justification = "Convert to Markdown via markitdown skill"

if sourceTier is None:
    fail("unknown-source-label", sourceLabelId)

elif sourceTier == target:
    # 已在目標 tier，不用 SetLabel，直接 SaveAs2
    save_as_and_convert(no_setlabel=True)

elif {"from": sourceTier, "to": target} in config.allowed_downgrades:
    try:
        doc.SensitivityLabel.SetLabel(labels[target].id, justification)
    except COMException as e:
        fail("no-downgrade-rights", str(e))
    save_as_and_convert()

else:
    fail("policy-forbidden", f"{sourceTier} → {target} 不在 allowed_downgrades")
```

### 6.4 失敗類型

| Reason | 何時 |
|---|---|
| `policy-forbidden` | 來源 tier → target 不在 `allowed_downgrades` |
| `unknown-source-label` | LabelId 不在 `config.json`，需重跑探索 |
| `no-downgrade-rights` | `SetLabel` COM call 被拒 |
| `office-not-installed` | 整批前置檢查失敗，整批中止 |
| `markitdown-failed` | COM 成功但 markitdown 退出非零 |
| `target-still-encrypted` | SaveAs2 後 markitdown 仍打不開，提示換更低 tier |
| `file-corrupt-or-locked` | COM 開檔即失敗 |

### 6.5 Audit log 影響

每次成功的 `SetLabel` 都會在 M365 audit log 記一筆。使用者已確認 `C-internal → C-external` 的降階符合公司政策。

---

## 7. SKILL.md 文件結構

```
---
name: markitdown
description: <§1.3 觸發描述>
---

# Office → Markdown (markitdown CLI + AIP-aware)

## 何時用這個 skill
- §1.4 決策表

## 前置條件
- §2 三項驗證

## 輸出規則
- §3 規則

## AIP Label 降階政策
- §6.2 config.json 範例
- §6.3 決策邏輯
- 第一次使用要跑探索模式

## 用法 A：單檔
- §4 流程
- 完整 PowerShell 片段

## 用法 B：批次（資料夾遞迴）
- §5 流程
- 完整 PowerShell 片段（含三 COM app 分桶）

## 探索模式（first-run）
- §6.1 步驟

## 副檔名範圍
- §1.2 表，及哪些不支援

## 跳過規則
- `~$*` 鎖檔

## 常見失敗與處理
- §6.4 失敗類型表
- 給每個 reason 一個建議下一步
```

---

## 8. 不在此 skill 範圍

明確列出以避免設計擴張：

- PDF / HTML / 圖片 / 音訊轉 Markdown
- 自動安裝 markitdown 或 Office
- 修改 AIP 政策本身（skill 只「使用」政策，不改）
- 跨 tenant / 多帳號處理
- 反向轉換（Markdown → Office）
- Markdown 後處理（例如自動分章、生成目錄）— 若使用者要，Claude 在轉完後另行處理

---

## 9. 已知風險與限制

| 風險 | 緩解 |
|---|---|
| COM 進程殘留（崩潰時 Word.exe 沒關） | finally 區塊呼叫 Quit + ReleaseComObject；批次結束額外掃描殘留 Office 進程並提示 |
| 中繼檔含解密內容洩漏 | 中繼根 `.tmp\` 排除於使用者一般瀏覽路徑；成功即刪；失敗保留時在最終回報中明列路徑 |
| `unprotected_target` 設錯仍加密 | 探索模式最後一步主動驗證；運作期遇到 `target-still-encrypted` 也會回報 |
| Office 版本差異使 SensitivityLabel API 不可用 | 前置檢查時試呼一次空 `SensitivityLabel` 屬性，沒有就提示升級 Office |
| Audit log 大量降階紀錄引起 IT 關注 | SKILL.md 明白告知每次 SetLabel 會留 audit log，並建議大量批次前先知會 IT |

---

## 10. 實作工作切片（給後續 writing-plans 用）

實作可拆成這些獨立可驗證的任務（順序、大致顆粒）：

1. 建立 `.claude/skills/markitdown/` 目錄、`config.json` 加入 `.gitignore`
2. 寫 SKILL.md 第 1 版的「觸發 / 前置 / 輸出規則」三節（最小可決策的內容）
3. 寫單檔流程的 PowerShell 片段（不含 COM，先驗 markitdown CLI 串接）
4. 把 COM 開檔 + SensitivityLabel 讀取的片段補進 SKILL.md
5. 補上 SetLabel 降階 + SaveAs2 + markitdown 三段串接
6. 寫批次流程片段（含 COM app 分桶共用）
7. 寫探索模式互動腳本片段 + config.json 寫入
8. 把失敗類型表、結尾彙整格式補齊
9. 用 5 ~ 10 份 sample 跑完整驗證：
   - 單檔 C-internal
   - 單檔 C-external（不降階）
   - 單檔 B（應 policy-forbidden）
   - 批次混合（含 ~$ 鎖檔、含未知 label）
10. 視驗證結果回填 SKILL.md「常見失敗與處理」段落
