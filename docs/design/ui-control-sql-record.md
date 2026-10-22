# 畫面元件代碼確認紀錄（PeopleTools 8.59，2026-10）

> 目的：確認 PeopleTools 表裡每個數字代碼代表哪一種元件或設定，讓研究文件（NN）翻譯時不會誤判。
> 這裡只記「代碼＝什麼」與「怎麼確認的」，不記公司系統裡各有幾個。SQL 原文不在這裡，位置列在最後一節。

## 1. 確認了哪些代碼

| 代碼存在哪裡 | 代表什麼 | 用到的 SQL |
|---|---|---|
| PSPNLFIELD.FIELDTYPE | 頁面元件的種類（Edit Box、Grid、按鈕…） | V6、G1、R2B、R2C、R3A、R5A |
| PSPNLFIELD.FIELDUSE（位元相加） | 元件的設計期屬性（唯讀、隱藏、相關顯示…） | R3B、R4C、R5B、R6、R7 |
| PSPNLFIELD.ASSOCFIELDNUM | 相關顯示（代碼旁的說明欄）指到哪個控制欄 | R2A、R4A、R5B、R6、R7 |
| PSRECFIELDDB.USEEDIT（位元相加） | Record 欄位設定（鍵、必填、Translate、Y/N、Prompt…） | V5、R3C、R4B |
| PSRECFIELDDB.EDITTABLE、PSRECDEFN.RECTYPE | 查值的 Prompt 表與它的種類 | V4、V5 |
| PSDBFIELD.FIELDTYPE | 欄位資料型別 | V4 |
| PSPNLGRPDEFN.ACTIONS（位元相加） | Component 允許的動作 | R4D |
| 前提 | 表與欄位在不在、版本、唯讀帳號看不看得到 | V1、V2、V3、V3c、R2A、唯讀帳號 A 測試、R4E |

「位元相加」：一個欄位同時有好幾個勾選時，存的是各勾選代表數字的和。例如 FIELDUSE＝17＝1＋16，代表同時勾了 Display Only（1）與 Related Field（16）。
SQL 用 `BITAND(欄位, 位元) > 0` 判斷某個勾選有沒有勾。

---

## 2. 代碼對照

### 2.1 元件種類（PSPNLFIELD.FIELDTYPE）

| 代碼 | 元件（App Designer 名稱） | 研究文件怎麼寫 | 怎麼確認的 |
|---|---|---|---|
| 0 | Static Text | 不列（版面） | V6 |
| 1 | Frame | 不列（版面） | V6 |
| 2 | Group Box | 不列（版面；整塊顯示的條件另照查詢手冊 §2h～§2i） | G1 |
| 3 | Static Image | 不列（版面） | V6 |
| 4 | Edit Box | Edit Box | V6 |
| 5 | Drop-Down List Box | Drop-Down List Box | V6 |
| 6 | Long Edit Box | Long Edit Box | V6 |
| 7 | Check Box | Check Box | V6 |
| 8 | Radio Button | Radio Button | V6 |
| 9 | Image | Image | V6 |
| 10 | Scroll Bar（舊式的層級捲動） | Scroll Bar | R5A＋App Designer |
| 11 | Subpage | Subpage（再展開它裡面的元件） | V6 |
| 12 | Push Button/Hyperlink，Destination＝PeopleCode Command | Push Button/Hyperlink: PeopleCode Command | R3A |
| 15 | Push Button/Hyperlink，Destination＝External Link | Push Button/Hyperlink: External Link | R5A＋App Designer |
| 16 | Push Button/Hyperlink，Destination＝Internal Link（轉到別的 Component） | Push Button/Hyperlink: Internal Link | R3A |
| 18 | Secondary Page | Secondary Page | R3A |
| 19 | Grid | Grid | R2C＋App Designer |
| 21 | Push Button/Hyperlink，Destination＝Secondary Page | Push Button/Hyperlink: Secondary Page | R3A |
| 23 | Horizontal Rule（分隔線） | 不列（裝飾） | R5A＋App Designer |
| 24 | Tab Separator（把 Grid 的欄位分成分頁） | Tab Separator | R5A＋App Designer |
| 25 | HTML Area | HTML Area | R3A |
| 27 | Scroll Area | Scroll Area | R3A |
| 其他 | 客製頁面沒出現、沒確認 | OTHER（代碼 n），不猜 | — |

- 「不列」＝不寫進研究文件的「## 畫面元件」表，不是頁面上沒有。
- Push Button/Hyperlink 依按鈕的 Destination 分成 12、15、16、21 四個代碼，研究文件在元件名稱後面接 Destination。
- 社群文件另列 13 Scroll Action、14 Toolbar Action、17 Process、20 Tree、26 Prompt Action、30 Chart 等，沒在公司環境確認，研究文件照 OTHER 寫。

### 2.2 元件的設計期屬性（PSPNLFIELD.FIELDUSE，位元相加）

| 位元 | 意思 | 研究文件寫法 | 狀態 |
|---|---|---|---|
| 1 | Display Only（唯讀） | DISPLAY_ONLY | 確認（R4C） |
| 2 | Invisible（隱藏） | INVISIBLE | 確認（R4C） |
| 16 | Related Field（相關顯示）；勾它會自動勾 Display Only，所以相關顯示是 1＋16 | RELATED_TO=<控制欄 tab order>（見 2.3） | 確認（R4C、R6、R7）；判斷是不是相關顯示一律看 16 |
| 8 | Display Control（相關顯示的控制欄） | DISPLAY_CONTROL | 確認（R7） |
| 4、32、1024… | 社群文件另列（文字顯示、多幣別、顯示標籤…） | 不用 | 沒確認 |

第三輪曾把 16 當成「唯讀」（R3B），第四輪用已知欄位核對後改正：唯讀是 1，16 是相關顯示。

### 2.3 相關顯示指到哪個控制欄（PSPNLFIELD.ASSOCFIELDNUM）

相關顯示是代碼欄旁邊顯示說明的欄位（例如部門代碼旁的部門名稱），ASSOCFIELDNUM 記著它是哪個控制欄的說明。

**確認（R7）：ASSOCFIELDNUM 從 0 起算——控制欄的 tab order（FIELDNUM）＝ASSOCFIELDNUM＋1**；指到第 1 個欄位的相關顯示存的是 0。
所以「是不是相關顯示」要看 FIELDUSE 16，不能看 ASSOCFIELDNUM 有沒有大於 0。研究文件的 RELATED_TO 寫的是控制欄的 tab order（SQL 已加 1）。

排除過的對應：控制欄 tab order＝ASSOCFIELDNUM（H0）、控制欄 Field ID＝ASSOCFIELDNUM（H3）、控制欄 Field ID＝ASSOCFIELDNUM＋1（H4）。

### 2.4 Record 欄位設定（PSRECFIELDDB.USEEDIT，位元相加）

| 位元 | 意思（App Designer Record Field 屬性） | 研究文件寫法 | 怎麼確認的 |
|---|---|---|---|
| 1 | Key | KEY | V5 |
| 32 | List Box Item（搜尋結果清單的欄位） | — | V5 |
| 64 | Descending Key | — | V5 |
| 256 | Required | REQUIRED | R4B（App Designer 勾了 Required 的欄位帶 256、沒勾的不帶） |
| 512 | Translate Table Edit（值要在 Translate 清單內） | XLAT | V5 |
| 2048 | Search Key | — | V5 |
| 4096 | Reasonable Date Test | REASONABLE_DATE | V5 |
| 8192 | Yes/No Table Edit（只收 Y／N） | YES_NO | V5 |
| 16384 | Prompt Table Edit（輸入值必須在 Prompt 清單內） | PROMPT … EDIT | V5 |
| 32768 | Auto-Update（存檔時系統自動押時間；只認日期／時間型欄位） | AUTO_UPDATE | V5 |
| 4、16、稽核位元 | System Maintained、Alternate Search Key 等 | 不用 | 沒確認 |

鍵欄位不會自動勾 Required（R3C），必填一律看 256。這組位元和 Oracle 官方 PeopleCode API 文件一致（4096 官方叫 Date Range Edit）。

### 2.5 查值（Prompt）

| 代碼／寫法 | 意思 | 怎麼確認的 |
|---|---|---|
| EDITTABLE 有值 | 這個欄位有 Prompt 表（查值按鈕） | V5 |
| EDITTABLE 以 `%` 開頭 | 動態 Prompt：Prompt 表在執行期由另一個欄位的值決定，要追 PeopleCode | V5 |
| USEEDIT 帶 16384 | 輸入值必須在 Prompt 清單內（研究文件寫 EDIT）；沒帶寫 NO_EDIT（只給查詢、不檢核） | V5 |
| Prompt 表的 RECTYPE | 0 實體表（TABLE）、2 Derived／Work（DERIVED）、1／5／6 三種 View（VIEW） | V4（0、2）；1、5、6 是 PeopleTools 定義 |

### 2.6 欄位資料型別（PSDBFIELD.FIELDTYPE）

| 代碼 | 意思 | 怎麼確認的 |
|---|---|---|
| 0、1、2、4、6 | 字元、長字元、數字、日期、日期時間 | V4 |

### 2.7 Component 允許的動作（PSPNLGRPDEFN.ACTIONS，位元相加）

| 位元 | 動作（Component Properties → Use → Actions） | 意思 |
|---|---|---|
| 1 | Add | 可以新增一筆新鍵值 |
| 2 | Update/Display | 修改既有資料；有效日期的列只看得到目前與未來 |
| 4 | Update/Display All | 看得到歷史列，只能改目前與未來 |
| 8 | Correction | 連歷史列都能改 |

R4D：挑的客製 Component ACTIONS＝2，App Designer 只勾 Update/Display；管理者確認四個動作依序是 1、2、4、8。其他位元研究文件照數字寫 `OTHER=n`。

### 2.8 前提

| 項目 | 結果 |
|---|---|
| PeopleTools 版本 | 8.59（V2） |
| 需要的表與欄位 | 都在（V1、V3、V3c）；PSPNLFIELD 有 ASSOCFIELDNUM 與 7 個 GOTO 欄，沒有 DSPLCNTRLFLD、POPUPNAME（R2A） |
| agent 的唯讀帳號 | 只查得到「擁有者.表名」→ SQL 一律寫 `<schema>.表名`；用到的 32 張表都看得到（R4E） |
| tab order | PSPNLFIELD.FIELDNUM 就是 App Designer Order 頁籤的 tab order（R5A 對照時確認） |

---

## 3. 每支 SQL：確認什麼、輸出怎麼看、結論

### 第一輪（2026-10-14～19，admin 帳號，先設 CURRENT_SCHEMA）

| SQL | 確認什麼 | 輸出怎麼看 | 結論 |
|---|---|---|---|
| V1 | agent 要用的表看不看得到 | 沒有列＝都看得到 | 都看得到 |
| V2 | PeopleTools 版本 | 一個版本號 | 8.59 |
| V3、V3c | 後面要用的欄位在不在 | 沒有列＝都在 | 都在 |
| V4 | 欄位資料型別、Record 種類的代碼：拿已知欄位與 Record 比 | 每列 OK／CHECK；有沒有假設外代碼看兩個數字是不是 0 | 全 OK |
| V5 | USEEDIT 各位元：用旁證自我核對（帶 16384 的應該都有 Prompt 表、帶 8192 的應該是 1 碼欄位…） | 一行字，每項 OK／CHECK | 全部成立（Auto-Update 只認日期／時間型欄位） |
| V6 | 元件代碼 0～11：用特徵自我核對（Check Box 綁 1 碼欄位、Subpage 有子頁名…）；列出還沒確認的其他代碼 | 0～11 每列 OK／CHECK；最後一行是其他代碼與特徵旗標 | 0～9、11 成立（2 另以 G1 確認）；其他代碼交後續幾輪 |
| G1 | 代碼 2 是不是 Group Box：看框裡有沒有其他元件 | 一行：平均高度、框內有元件的比例、綁欄位的比例 | 2＝Group Box |

### 第二輪（2026-10-19）

| SQL | 確認什麼 | 輸出怎麼看 | 結論 |
|---|---|---|---|
| R2A | PSPNLFIELD 有哪些候選欄（顯示控制、相關顯示、按鈕目標） | 一串 Y／N | 有 ASSOCFIELDNUM 與 7 個 GOTO 欄 |
| R2B | 找一個有待確認代碼的客製頁面，拿去 App Designer 對 | 候選頁面與它有的代碼 | 挑到一頁 |
| R2C | 那一頁的元件在 App Designer 是什麼 | 對 Order 頁籤的 Type | 19＝Grid |

### 第三輪（2026-10-19）

| SQL | 確認什麼 | 輸出怎麼看 | 結論 |
|---|---|---|---|
| R3A | 其餘元件代碼：依特徵判斷（有沒有子頁名、GOTO 目標、綁欄位、長字元、框內有沒有元件） | 每個代碼一列：OK＝推測成立；其他寫特徵 | 12、16、18、21、25、27 成立；10、15、23、24 判不出 → R5A |
| R3B | 唯讀與 Display Control 的位元：從相關顯示共有的位元找 | 一行字：候選位元 | 找到 16（後來改正為相關顯示旗標）；Display Control 沒找到 |
| R3C | 鍵欄位會不會自動帶 256 | 兩個比例 | 不會 → 256 另外核對 |
| 唯讀帳號 A 測試 | 唯讀帳號用不帶擁有者的表名查得到嗎 | 通／不通 | 不通 → 框架改寫 `<schema>.表名` |

### 第四輪（2026-10-20，唯讀帳號）

| SQL | 確認什麼 | 輸出怎麼看 | 結論 |
|---|---|---|---|
| R4A | 相關顯示指到哪一欄：比幾種對應 | 每種對應的 P（指到的欄有 Prompt 的比例）、R（Prompt 表就是相關顯示 Record 的比例）；最高的就是對的 | 回報的最佳一組標成 H0；R6 重算 H0 對不上，那一組比較像 H1（＋1） |
| R4B | 256 是不是 Required：拿 App Designer 已知欄位比 | `REQ=Y`、`OPT=N` 就成立 | 成立 |
| R4C | 唯讀、隱藏的位元：拿已知欄位比 | 每個欄位的位元清單 | 1＝Display Only、2＝Invisible、相關顯示是 1＋16 |
| R4D | Component 動作：拿已知 Component 比 | ACTIONS 數字＋App Designer 勾了哪些 | 2＝Update/Display；順序 1、2、4、8 |
| R4E | 唯讀帳號缺哪幾張表 | 沒有列＝都有 | 都有 |

### 第五輪（2026-10-21，唯讀帳號）

| SQL | 確認什麼 | 輸出怎麼看 | 結論 |
|---|---|---|---|
| R5A | 代碼 10、15、23、24 | 各代碼的特徵，加一個樣本頁與 tab order，拿去 App Designer Order 頁籤找那個元件看類型 | 10 Scroll Bar、15 External Link 按鈕、23 Horizontal Rule、24 Tab Separator |
| R5B | FIELDUSE 8 是不是 Display Control | 控制欄（用 tab order 對應）裡帶 8 的有多少 | 對不上 → R6 |

### 第六輪（2026-10-21，唯讀帳號）

| SQL | 確認什麼 | 輸出怎麼看 |
|---|---|---|
| R6 | ASSOCFIELDNUM 存的是控制欄的 tab order（H0）還是 Field ID（H3）；FIELDUSE 8 是不是 Display Control | 一行：H0、H3 各四個數（找到的控制欄、其中有 Prompt 的、Prompt 表＝相關顯示 Record 的、帶 8 的）。H3 明顯比 H0 大、第四個接近第一個 → 存的是 Field ID、8＝Display Control；反過來 → 維持 tab order |
| R6B（可選） | 同上，用 App Designer 對一個相關顯示 | 相關顯示的 ASSOCFIELDNUM 等於控制欄的 tab order 還是 Field ID |

結論：H0、H3 都不對；ASSOCFIELDNUM 大於 0 的全部帶 16，另有一批帶 16 但 ASSOCFIELDNUM 是 0；Field ID 同頁不重複。

### 第七輪（2026-10-21，公司機 Claude 查 DB）

| SQL | 確認什麼 | 輸出怎麼看 |
|---|---|---|
| R7 | ASSOCFIELDNUM 是不是從 0 起算（控制欄 tab order＝ASSOCFIELDNUM＋1，H1；或 Field ID＋1，H4）；FIELDUSE 8 是不是 Display Control | 一行：A0（ASSOCFIELDNUM 是 0 的相關顯示）、H1 與 H4 各四個數（同 R6）。哪組明顯高、第四個接近第一個，就是那組 |
| R7B（可選） | 同上，用 App Designer 對一個相關顯示 | ASSOC＝控制欄 tab order 減 1 → H1 成立 |
| R7K | 同上，改用「控制欄的欄位名是相關顯示 Record 的鍵」與「控制欄帶 8」比 H0、H1、H3、H4 與前一欄 | 每種對應一列：KEY_PCT、B8_PCT；兩個都明顯最高的就是對的 |

結論：H1 成立——控制欄 tab order＝ASSOCFIELDNUM＋1；FIELDUSE 8＝Display Control（公司機的 Claude 跑 R7K 並抽查後判定）。

---

## 4. 框架正式在用的兩支查詢：輸出怎麼解讀

### 4.1 Page 上的元件（查詢手冊 §2l，一個 Page 一次）

每一列是頁面上的一個元件（版面元件與分隔線不列）。研究文件「## 畫面元件」一列一個元件：

| 輸出欄 | 意思 | 寫到研究文件的哪一格 |
|---|---|---|
| FIELDNUM | tab order | # |
| RECNAME、FIELDNAME（沒綁欄位用 LBLTEXT） | 綁的欄位 | 欄位 |
| CONTROL（沒解碼時看 CODE） | 元件種類（2.1） | 元件 |
| DO、INV、DC、KEY_FLAG、REQ、RDATE、AUPD | 唯讀、隱藏、控制欄、鍵、必填、合理日期、自動押時間 | 屬性（有值的依序串起來） |
| RELATED_TO、LVL、GOTO_COMPONENT、SUBPAGE | 相關顯示指到的控制欄、層級、轉到的 Component、子頁名 | 屬性（`RELATED_TO=`、`LEVEL=`、`GOTO=`、`PAGE=`） |
| PROMPT_REC、PROMPT_EDIT、PROMPT_KIND、PROMPT_KEYS | Prompt 表、檢不檢核、表的種類、表的鍵 | 查值 |
| VALUES_EDIT | 沒有 Prompt 時：XLAT 或 YES_NO | 查值 |

例（合成名稱）：

| 頁面 | # | 欄位 | 元件 | 屬性 | 查值 |
|---|---|---|---|---|---|
| TW_DEMO_PG | 4 | TW_DEMO_REQHDR.DEPTID | Edit Box | DISPLAY_CONTROL REQUIRED | PROMPT TW_DEMO_DEPTVW EDIT（VIEW；鍵 SETID,DEPTID,EFFDT） |
| TW_DEMO_PG | 5 | TW_DEMO_DEPTVW.DESCR | Edit Box | DISPLAY_ONLY RELATED_TO=4 |  |
| TW_DEMO_PG | 6 | TW_DEMO_REQHDR.REQ_TYPE | Drop-Down List Box |  | XLAT |

讀法：第 4 欄是部門代碼，必填、要從部門 view 選（輸入值會被檢核，view 以 SETID、DEPTID、EFFDT 為鍵）；第 5 欄是它旁邊唯讀的部門名稱；
第 6 欄是下拉選單，值來自 Translate 清單。這些都是設計期設定；PeopleCode 在執行期改的顯示、可改、必填寫在研究文件的「行為邏輯」。

### 4.2 Component 的動作與搜尋 Record（查詢手冊 §2m，一個 Component 一次）

一列：ACT_ADD／ACT_UPD／ACT_ALL／ACT_COR 有值＝那個動作有勾（2.7）；OTHER_BITS 有值＝四個動作以外的位元；SEARCH_REC＝搜尋頁查的 Record；
ADD_SEARCH_REC＝新增用的搜尋 Record（沒有＝新增也用 SEARCH_REC）。寫成「## 畫面元件」的第一列：

| 頁面 | # | 欄位 | 元件 | 屬性 | 查值 |
|---|---|---|---|---|---|
| TW_DEMO_REQ | 0 |  | Component | ADD UPDATE_DISPLAY | SEARCH TW_DEMO_REQSRCH |

讀法：這個 Component 可以新增、可以修改現行資料，但看不到歷史列、也不能更正；搜尋頁查 TW_DEMO_REQSRCH。使用者實際能用哪幾個動作還要看權限。

---

## 5. 還沒定案

- 代碼 15 External Link 的網址存在哪個欄位：沒查。
- 權限表 PSAUTHITEM.AUTHORIZEDACTIONS：和 ACTIONS 同一組位元；128 社群多寫 Data Entry，沒在公司環境確認，還沒解碼。
- 搜尋 Record 的搜尋鍵與清單欄位：§2m 只給 Record 名。

## 6. SQL 原文位置（repo）

| SQL | 檔案 |
|---|---|
| V1～V7、G1、權限檢查 | `docs/design/ui-metadata-check-r1.md`（整份可跑版 `ui-metadata-check-r1.sql`） |
| R2A～R2C | `docs/design/ui-metadata-check-r2.md` |
| R3A～R3C、唯讀帳號 A 測試 | `docs/design/ui-metadata-check-r3.md` |
| R4A～R4E | `docs/design/ui-metadata-check-r4.md` |
| R5A、R5B（含官方／社群對照表與來源連結） | `docs/design/ui-metadata-check-r5.md` |
| R6、R6B | `docs/design/ui-metadata-check-r6.md` |
| R7、R7B、R7K | `docs/design/ui-metadata-check-r7.md` |
| 正式查詢 §2l、§2m | `.opencode/peoplesoft/oracle-query-cookbook.md`（Claude Code 版：`claude-code/.claude/peoplesoft/oracle-query-cookbook.md`） |

第一到三輪的 SQL 是 admin 帳號設 CURRENT_SCHEMA 跑的，表名沒有帶擁有者；用唯讀帳號重跑要先把表名改成 `<schema>.表名`。
