# 業務需求文件撰寫規範：使用說明（給管理者）

> 這份規範已是 `/ps-spec` 的產出格式：兩版框架的 `peoplesoft/bizspec/standard.md` 與本目錄的 `standard.md` 逐字相同，
> `/ps-spec` 由外環 `scripts/ps-bizspec.ps1` 開 Sonnet session 照它寫、逐字比對第 10 章證據、補查並回填（操作見 SOP-31）。
> 下面是不經框架、直接拿規範給 Sonnet 用的方式。

`standard.md` 是一份給 Sonnet 照做的規範：把一組來源 Spec 整理成一份**只談業務需求、不談系統設計**的業務需求文件。
不綁定業務領域、模組或技術棧；來源 Spec 的格式也不限（一組 md、單一檔、csv 都可以）。

## 產出長什麼樣

`<輸出資料夾>` 裡一章一個檔（太長會拆續檔），入口是 `README.md`：

| 章 | 內容 | 檔 |
|---|---|---|
| 0 | 文件資訊與目次 | `README.md` |
| 1 | 目標：本期支援哪些業務、成功指標、不是目標 | `01-goals.md` |
| 2 | Spec 是什麼：唯一業務真相、來源各檔回答什麼、狀態標記、版本 | `02-spec-overview.md` |
| 3 | 怎麼讀 Spec：閱讀順序、Spec 地圖、範圍判讀（SCOPE）、常見誤讀 | `03-reading-guide.md` |
| 4 | 需求單元與需求鍵、分類、需求索引、checklist 怎麼用 | `04-requirement-index.md` |
| 5 | 流程、畫面與欄位、業務資料、業務規則、狀態、權限、外部往來、涵蓋表 | `05-1-flows.md`～`05-8-coverage.md` |
| 6 | 需求追蹤表與狀態值 | `06-tracking.md` |
| 7 | 缺口、矛盾與假設（A-###）、來源問題清單對照、怎麼關閉 | `07-assumptions.md` |
| 8 | Spec 改版怎麼處理 | `08-spec-change.md` |
| 9 | 驗收情境（ACC）、業務人員驗收紀錄、本期完成判定 | `09-acceptance.md` |
| 10 | 證據：每條需求與假設引用的來源原文（`E-###`，逐字摘錄）；補查紀錄 | `10-evidence.md` |
| 附錄 | 名詞表、Spec 文件用途速查、範本、參考文件 | `appendix.md` |

另有 `progress.md`：Sonnet 自己的進度檔，用來中斷後續寫。

## 怎麼用

1. 把 `standard.md` 放到工作資料夾（例：`docs\business-spec\standard.md`）。
2. 準備 `<來源資料夾>`：放來源 Spec 的全部檔案。只能是文字檔（`.md`、`.txt`、`.csv`、`.json`）；Word／Excel 先轉成 Markdown 或 csv
   （Excel 每個工作表一個 csv）。
3. 準備一個空的 `<輸出資料夾>`。
4. 開一個 Sonnet session（Claude Code 或 OpenCode 都可以），輸入：

   ```text
   讀 docs/business-spec/standard.md，照它把 <來源資料夾> 的來源 Spec 整理成業務需求文件，寫到 <輸出資料夾>。
   ```

5. **中斷或 context 滿了**：開新的 session，輸入同一句。它會讀 `<輸出資料夾>\progress.md`，從沒打勾的項目接續。
6. **來源 Spec 出新版**：新版放在另一個資料夾（舊版不動），輸入：

   ```text
   讀 docs/business-spec/standard.md。來源 Spec 出了新版，新版在 <新版資料夾>，舊版在 <來源資料夾>，業務需求文件在 <輸出資料夾>，照第 8 章處理。
   ```

7. **業務窗口回覆了假設**：輸入「讀 docs/business-spec/standard.md，照第 7 章 7.4 關閉 A-###：〈回覆內容〉」。

## 寫完之後你要做的事

- `07-assumptions.md`：每筆開放的假設依「該問誰」交業務窗口或 Spec 產製端，回覆後照上面第 7 步關閉。
- `06-tracking.md`：「已交付」「已驗收」只由人更新。
- `09-acceptance.md`：請業務人員照 9.1 的情境實際操作，結果記在 9.2。
- 寫完、自我檢查通過，都不等於業務驗收通過（見產出的 9.4）。

## 寫作節奏

規範要求 Sonnet 每次回應都小：一次只寫一章、每次寫檔不超過 150 行、寫完不讀回、只在最後做一次自我檢查。
這是為了避免長回應在 gateway 逾時，也讓 session 中斷時最多損失一章。

## 驗證紀錄

規範經三輪、共 9 份 Sonnet 獨立試寫，用兩組合成來源（不同領域、不同格式）與答案卷比對。
最後一輪三份都滿分，而且零編造、需求描述零系統設計外洩。指標如下：

| 指標 | 結果 |
|---|---|
| 假設 | 10～11 筆 |
| 待確認占比 | 17～23% |
| 驗收情境 | 69～80 條 |
| 同來源兩份的條數 | 流程差 1 條，其他各類相同 |

細節與重跑方式見 `validation/README.md`。

- 測試全過、自我檢查通過，只代表 Sonnet 照規範寫完了，不代表來源 Spec 本身正確。
- 第一次用真實來源 Spec 時，請記錄假設筆數、待確認占比、驗收情境條數，以及 Sonnet 的猶豫點。
  回報時只給數字與規範章節號，不給業務內容；規範的下一次修正以這些記錄為依據。
