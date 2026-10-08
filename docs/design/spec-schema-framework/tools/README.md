# 設計期工具（Python 原型）

這些腳本只服務設計提案本身，做兩件事：

- 讓 `schemas/`、範例、渲染樣張與設計文件裡的表格來自同一份定義。
- 證明文件契約可以被機器檢查。

它們不是框架的一部分：不搬公司機，不進搬運包，也不被 `scripts/` 呼叫。實作時要移植成 PowerShell 5.1（主文件 §16），這裡的邏輯與範例資料可以當作對照實作與測試資料。

## 需求

Python 3.10 以上、`jsonschema` 4.18 以上（含 `referencing`）。

## 用法

```bash
python3 docs/design/spec-schema-framework/tools/build.py
```

依序執行：

| 腳本 | 做什麼 | 產出 |
|---|---|---|
| `schema_gen.py` | 共同定義、15 種文件型別、證據登錄的 JSON Schema（2020-12）；也是 types.md 欄位表的來源 | `schemas/*.schema.json` |
| `check_rank.py` | 跨文件參照只指向上游、文件層級無循環 | 失敗時結束碼非 0 |
| `example_inputs.py`、`example_gen.py` | 合成的申請／審核範例：輸入檔與全部項目（以自然鍵寫參照，再依序派 ID） | — |
| `assemble_check.py` | 組成 15 份 canonical 文件；計算 17、18；跑 schema 驗證與 L2、L3 檢核；解析並比對兩張 Mermaid 圖；產生最小合法文件 | `examples/walkthrough/canonical/`、`input/`、`gate-report.json`、`examples/minimal/` |
| `negative_check.py` | 壞範例：對範例做 9 種刻意破壞（缺欄位、模糊條件、填充字、未標示推論、推測用語、缺引用、往下游參照、不建置欄位、圖外轉移），每一種都必須被對應的檢核擋下 | `examples/negative-report.json` |
| `render.py` | 渲染器原型：canonical → 00-index 與各文件 Markdown（含重新產生的 Mermaid 圖、反查欄） | `examples/walkthrough/rendered/` |
| `sync_docs.py` | 把產生的表格與範例片段寫回設計文件的 `<!-- GEN:… -->` 區塊 | `../spec-schema-framework.md`、`types.md`、`walkthrough.md` |

`build.py` 最後確認兩件事，任一不符都算失敗：

- 檢核結果恰好是範例故意留下的兩條測試缺口，多一條或少一條都不行。
- 9 種壞範例全部被擋下。

## 範圍與限制

- `assemble_check.py` 的 Mermaid 解析器只支援範例用到的語法。完整語法支援是實作項目（主文件 §8.1）。
- 範例的 L4、L5 是假設值，這裡沒有呼叫任何模型。
- 範例資料全部合成。
