# 畫面元件盤點紀錄（PeopleTools 8.59，2026-10）

> 這份記錄三件事：每支 SQL 盤點的是什麼、盤點出來的結果（代碼表）、SQL 結果怎麼解讀。
> 範圍是公司環境的客製頁面（名稱 `TW_` 開頭）；數字都是彙總，沒有公司資料。SQL 原文不在這裡，位置列在最後一節。

## 1. 為什麼要盤點、盤點哪些東西

研究文件原本只知道欄位的資料型別，不知道畫面上是什麼元件、是不是唯讀／隱藏／必填、輸入值去哪裡查、Component 允許新增還是只能修改。
這些設定在 PeopleTools 的表裡都存成**數字代碼**（有的是「位元相加」），官方沒有公開完整對照，所以先在公司環境逐一盤點、確認每個數字的意思，
確認過的才讓 agent 拿來翻譯。

| 盤點對象 | 存在哪裡 | 用到的 SQL |
|---|---|---|
| 頁面元件的種類（Edit Box、Grid、按鈕…） | PSPNLFIELD.FIELDTYPE | V6、G1、R2B、R2C、R3A、R5A |
| 元件的設計期屬性（唯讀、隱藏、相關顯示…） | PSPNLFIELD.FIELDUSE（位元相加） | R3B、R4C、R5B、R6 |
| 相關顯示（代碼旁的說明欄）指到哪個控制欄 | PSPNLFIELD.ASSOCFIELDNUM | R2A、R3B、R4A、R5B、R6 |
| Record 欄位設定（鍵、必填、Translate、Y/N、Prompt…） | PSRECFIELDDB.USEEDIT（位元相加） | V5、R3C、R4B |
| 查值：Prompt 表 | PSRECFIELDDB.EDITTABLE、PSRECDEFN.RECTYPE | V5、V7 |
| 欄位資料型別、Record 種類 | PSDBFIELD.FIELDTYPE、PSRECDEFN.RECTYPE | V4 |
| Component 允許的動作（新增、修改、看歷史、更正） | PSPNLGRPDEFN.ACTIONS（位元相加） | R4D |
| 前提：表與欄位在不在、版本、唯讀帳號看不看得到 | 資料字典、PSSTATUS | V1、V2、V3、V3c、R2A、唯讀帳號 A 測試、R4E |

「位元相加」：一個欄位同時有好幾個勾選時，存的是各勾選代表數字的和。例如 FIELDUSE＝17＝1＋16，代表同時勾了 Display Only（1）與 Related Field（16）。
SQL 用 `BITAND(欄位, 位元) > 0` 判斷某個勾選有沒有勾。

---

## 2. 盤點結果

### 2.1 元件種類（PSPNLFIELD.FIELDTYPE）

| 代碼 | 元件（App Designer 名稱） | 客製頁面筆數 | 研究文件怎麼寫 | 怎麼確認的 |
|---|---|---|---|---|
| 0 | Static Text | — | 不列（版面） | V6 |
| 1 | Frame | — | 不列（版面） | V6 |
| 2 | Group Box | — | 不列（顯示條件另外查） | G1：98% 框內有其他元件 |
| 3 | Static Image | — | 不列（版面） | V6 |
| 4 | Edit Box | 綁欄位的 15154 | Edit Box | V6 |
| 5 | Drop-Down List Box | — | Drop-Down List Box | V6 |
| 6 | Long Edit Box | — | Long Edit Box | V6 |
| 7 | Check Box | — | Check Box | V6 |
| 8 | Radio Button | — | Radio Button | V6 |
| 9 | Image | — | Image | V6 |
| 10 | Scroll Bar（舊式的層級捲動） | 30 | Scroll Bar | R5A＋App Designer |
| 11 | Subpage | — | Subpage | V6 |
| 12 | Push Button/Hyperlink：PeopleCode Command（按下去跑 PeopleCode） | 1088 | Push Button/Hyperlink: PeopleCode Command | R3A |
| 15 | Push Button/Hyperlink：External Link（開外部網址） | 1 | Push Button/Hyperlink: External Link | R5A＋App Designer |
| 16 | Push Button/Hyperlink：Internal Link（轉到別的 Component） | 30 | Push Button/Hyperlink: Internal Link | R3A |
| 18 | Secondary Page | 56 | Secondary Page | R3A |
| 19 | Grid | 587 | Grid | R2C＋App Designer |
| 21 | Push Button/Hyperlink：Secondary Page（開次頁） | 12 | Push Button/Hyperlink: Secondary Page | R3A |
| 23 | Horizontal Rule（分隔線） | 59 | 不列（裝飾） | R5A＋App Designer |
| 24 | Tab Separator（把 Grid 欄位分成分頁） | 9 | Tab Separator | R5A＋App Designer |
| 25 | HTML Area | 425 | HTML Area | R3A |
| 27 | Scroll Area | 588 | Scroll Area | R3A |
| 其他 | 客製頁面沒出現 | 0 | OTHER（代碼 n），不猜 | — |

「—」＝V6 只回 OK、沒回筆數。客製頁面出現的代碼就是上表這些；13、14、17、20、26、30 等社群文件列的按鈕或元件，客製頁面沒有。

### 2.2 元件的設計期屬性（PSPNLFIELD.FIELDUSE，位元相加）

| 位元 | 意思 | 盤點結果 | 狀態 |
|---|---|---|---|
| 1 | Display Only（唯讀） | 勾 Display Only 的欄位都帶 1 | 確認（R4C） |
| 2 | Invisible（隱藏） | 勾 Display Only＋Invisible 的欄位是 1＋2；公司頁面沒有只勾 Invisible 的 | 確認（R4C） |
| 16 | Related Field（相關顯示） | 相關顯示幾乎都帶 16，也都帶 1（勾 Related Field 會自動勾 Display Only） | 確認是相關顯示的旗標；和 ASSOCFIELDNUM 是否一一對應待 R6 |
| 8 | Display Control（相關顯示的控制欄） | 帶 8 的欄位 2044 個，和相關顯示 1984 個相近；但用 tab order 找到的控制欄只有 8% 帶 8 | 待 R6 |
| 4、32、1024… | 社群文件另列（文字顯示、多幣別、顯示標籤…） | 沒盤點 | 框架不用 |

第三輪曾把 16 當成「唯讀」的位元（R3B），第四輪用已知欄位核對後改正：唯讀是 1，16 是相關顯示。

### 2.3 相關顯示指到哪個控制欄（PSPNLFIELD.ASSOCFIELDNUM）

相關顯示是代碼欄旁邊那個顯示說明的欄位（例如部門代碼旁的部門名稱），它記著自己是哪個「控制欄」的說明。
客製頁面有 1984 個相關顯示（ASSOCFIELDNUM 大於 0），97% 是 Edit Box。ASSOCFIELDNUM 存的數字有兩種可能：

- **H0**：控制欄的 tab order（FIELDNUM）。第四輪 R4A 比的幾種對應裡 H0 最好，但只有 54% 指到有 prompt 的欄位。
- **H3**：控制欄的 Field ID（PNLFLDID，欄位放上頁面時給的編號，調 tab order 不會變）。沒調過順序的頁面兩者相同，所以 H0 看起來對了一部分。

第五輪 R5B 的結果比較支持 H3，第六輪 R6 一次比兩種。確認前，研究文件的 RELATED_TO、DISPLAY_CONTROL 在調過順序的頁面可能指錯欄。

### 2.4 Record 欄位設定（PSRECFIELDDB.USEEDIT，位元相加）

| 位元 | 意思（App Designer Record Field 屬性） | 研究文件寫法 | 怎麼確認的 |
|---|---|---|---|
| 1 | Key | KEY | V5 |
| 32 | List Box Item（搜尋結果清單的欄位） | — | V5 |
| 64 | Descending Key | — | V5 |
| 256 | Required | REQUIRED | R4B（必填欄 Y、非必填欄 N） |
| 512 | Translate Table Edit（值要在 Translate 清單內） | XLAT | V5 |
| 2048 | Search Key | — | V5 |
| 4096 | Reasonable Date Test | REASONABLE_DATE | V5 |
| 8192 | Yes/No Table Edit（只收 Y／N） | YES_NO | V5 |
| 16384 | Prompt Table Edit（輸入值必須在 prompt 清單內） | PROMPT … EDIT | V5 |
| 32768 | Auto-Update（存檔時系統自動押時間） | AUTO_UPDATE | V5：帶 32768 的欄位 98.6% 是日期／時間型 |
| 4、16、稽核位元 | System Maintained、Alternate Search Key 等 | — | 沒盤點，框架不用 |

R3C 另外看到：客製 Record 的鍵欄位只有 23% 帶 256、非鍵欄位 5%——鍵不會自動勾 Required，必填要看 256。
這組位元和 Oracle 官方 PeopleCode API 文件列的一致（4096 官方叫 Date Range Edit）。

### 2.5 查值（Prompt）

| 項目 | 盤點結果 |
|---|---|
| 被當 Prompt 表的 Record | 7291 個（全環境，V7） |
| 其中是 view 的 | 5395 個（74%）：查值邏輯多半在 view 的 SQL 裡 |
| 以 EFFDT 為鍵 | 1429 個（20%）：查值會看有效日期 |
| 以 SETID 為鍵 | 372 個（5%）：查值會看 SetID |
| EDITTABLE 指向不存在的 Record | 107 個：範圍內遇到就開問題單 |
| 動態 Prompt（EDITTABLE 以 `%` 開頭） | 4182 列（V5）：Prompt 表在執行期由另一個欄位決定，要追 PeopleCode |

研究文件的查值寫法：`PROMPT <Prompt 表> <EDIT／NO_EDIT／DYNAMIC>（<TABLE／VIEW／DERIVED>；鍵 …）`。
EDIT＝輸入值必須在清單內（16384 有勾）；NO_EDIT＝只給查詢、不檢核；DYNAMIC＝動態 Prompt。

### 2.6 欄位資料型別與 Record 種類

| 欄位 | 代碼 | 意思 | 怎麼確認的 |
|---|---|---|---|
| PSDBFIELD.FIELDTYPE | 0、1、2、4、6 | 字元、長字元、數字、日期、日期時間 | V4a、V4c |
| PSRECDEFN.RECTYPE | 0 | 實體表 | V4b |
| PSRECDEFN.RECTYPE | 2 | Derived／Work Record（只在畫面上，不存資料庫） | V4b |
| PSRECDEFN.RECTYPE | 1、5、6 | 三種 View（SQL、Dynamic、Query View），研究文件都寫 VIEW | PeopleTools 定義 |

### 2.7 Component 允許的動作（PSPNLGRPDEFN.ACTIONS，位元相加）

| 位元 | 動作（Component Properties → Use → Actions） | 意思 |
|---|---|---|
| 1 | Add | 可以新增一筆新鍵值 |
| 2 | Update/Display | 修改既有資料；有效日期的列只看得到目前與未來 |
| 4 | Update/Display All | 看得到歷史列，只能改目前與未來 |
| 8 | Correction | 連歷史列都能改 |

R4D：挑的客製 Component ACTIONS＝2，App Designer 只勾 Update/Display；管理者確認四個動作依序是 1、2、4、8。
其他位元研究文件照數字寫 `OTHER=n`，不猜意思。

### 2.8 環境前提

| 項目 | 結果 |
|---|---|
| PeopleTools 版本 | 8.59（V2） |
| 需要的表與欄位 | 都在（V1、V3、V3c）；PSPNLFIELD 有 ASSOCFIELDNUM 與 7 個 GOTO 欄，沒有 DSPLCNTRLFLD、POPUPNAME（R2A） |
| agent 的唯讀帳號 | 只查得到「擁有者.表名」（唯讀帳號 A 測試 FAIL：不加擁有者 ORA-00942、ALTER SESSION ORA-02421）→ SQL 一律寫 `<schema>.表名`；32 張表都看得到（R4E） |

---

## 3. 每支 SQL：盤點什麼、輸出怎麼看、結果

### 第一輪（2026-10-14～19，admin 帳號，先設 CURRENT_SCHEMA）

| SQL | 盤點什麼 | 輸出怎麼看 | 結果 |
|---|---|---|---|
| V1 | agent 要用的 PeopleTools 表看不看得到 | 沒有列＝都看得到；有列＝看不到的表名 | 設好 schema 後都看得到 |
| V2 | PeopleTools 版本 | 一個版本號 | 8.59 |
| V3 | 後面要用的欄位在不在 | 沒有列＝都在；有列＝缺的欄名 | 都在 |
| V3c | 查詢手冊 §2h～§2j 用到的 Page 欄位在不在 | 沒有列＝都在 | 都在 |
| V4a | 欄位資料型別代碼：拿已知欄位比 | 每列標 OK／CHECK | 全 OK（0 字元、1 長字元、2 數字、4 日期、6 日期時間） |
| V4b | Record 種類代碼：拿已知 Record 比 | 每列標 OK／CHECK | 全 OK（0 實體表、2 Derived） |
| V4c | 有沒有假設以外的代碼 | 兩個數字，都 0＝沒有 | 0、0 |
| V4d | 欄位大寫格式的代碼 | OK＋兩個數字 | OK |
| V5 | Record 欄位設定的位元：用旁證自我核對（例：帶 16384 的應該都有 Prompt 表、帶 8192 的應該是 1 碼欄位） | 一行字，每項 OK／CHECK，另附 DYN 數字 | 除 Auto-Update 98.6%（門檻 99）外全 OK；DYN 4182 |
| V6 | 元件種類代碼 0～11：用特徵自我核對（例：Check Box 應綁 1 碼欄位、Subpage 應有子頁名）；其他代碼列出筆數與特徵旗標 | 0～11 每列 OK／CHECK；最後一行 `代碼:筆數:旗標`（S＝有子頁名、N＝沒綁欄位、L＝綁長字元） | 0～9、11 除 Group Box 外全 OK；其他代碼 10:30:N、12:1088、15:1、16:30:N、18:56:S:N、19:587、21:12:S、23:59:N、24:9:N、25:425:L、27:588:N |
| G1 | Group Box 確認（V6 的代碼 2 報 CHECK） | GB_H／EB_H 平均高度、GB_IN 框內有元件的比例、GB_REC 綁欄位的比例 | GB_IN 98、GB_REC 78 → 2＝Group Box（常綁一個欄位讓 PeopleCode 隱藏整塊）；EB_H 是負的，座標上下的意思依元件而不同 |
| V7 | Prompt 的分布 | 五個數字 | 7291、5395、1429、372、107（見 2.5） |
| 權限檢查 | 唯讀帳號有沒有那 14 張表 | 沒有列＝都有 | 管理者授權後都有 |

### 第二輪（2026-10-19）

| SQL | 盤點什麼 | 輸出怎麼看 | 結果 |
|---|---|---|---|
| R2A | PSPNLFIELD 有哪些候選欄（顯示控制、相關顯示、按鈕目標） | 一串 Y／N＋多出幾個同類欄 | NYYYYYYYYN、EXTRA 3：沒有 DSPLCNTRLFLD、POPUPNAME；有 ASSOCFIELDNUM 與 7 個 GOTO 欄 |
| R2B | 找一個待核對代碼最多的客製頁面 | 5 個頁面與各自的代碼 | 挑到的頁面有 12、19、21、25、27 |
| R2C | 那一頁的元件在 App Designer 是什麼 | 管理者對 Order 頁籤的 Type | 19＝Grid |

### 第三輪（2026-10-19）

| SQL | 盤點什麼 | 輸出怎麼看 | 結果 |
|---|---|---|---|
| R3A | 其餘元件代碼：依特徵判斷（有沒有子頁名、GOTO 目標、綁欄位、長字元、框內有沒有元件） | 每個代碼一列：OK＝推測成立；其他代碼寫特徵（LINK、CONTAINER、MIXED…） | 12、16、18、21、25、27 OK；10、23 MIXED；15、24 CONTAINER |
| R3B | 相關顯示與唯讀位元：相關顯示一定唯讀，找它們共有的位元 | 一行字：REL_N 相關顯示數、REL_EB Edit Box 比例、CTL_PROMPT 控制欄有 prompt 的比例、DO／DC 候選位元 | REL_N 1984、REL_EB 97、CTL_PROMPT 8、DO=16、DC=NONE（之後改正：16 是相關顯示旗標，唯讀是 1） |
| R3C | 鍵欄位會不會自動帶 256 | 兩個比例 | KEY_REQ 23、NONKEY_REQ 5 → 不會，256 另外核對 |
| 唯讀帳號 A 測試 | agent 的唯讀帳號用不加擁有者的表名查得到嗎 | 通／不通 | 不通 → 框架改成 `<schema>.表名` |

### 第四輪（2026-10-20，唯讀帳號）

| SQL | 盤點什麼 | 輸出怎麼看 | 結果 |
|---|---|---|---|
| R4A | 相關顯示指到哪一欄：比幾種對應（H0 tab order、差一號、前一欄） | 每種對應：N 筆數、P 指到的欄有 prompt 的比例、R prompt 表就是相關顯示 Record 的比例；P、R 最高的就是對的 | ALL N 15154 P 14 R 0；H0 N 1984 P 54 R 22；H2 N 1867 P 13 R 1；NB N 1984 P 41 R 17 → H0 最好（第五輪起存疑） |
| R4B | 256 是不是 Required：拿 App Designer 已知欄位比 | `REQ=Y`、`OPT=N` 就成立 | REQ=Y、OPT=N |
| R4C | 唯讀、隱藏的位元：拿已知欄位比 | 每個欄位的位元清單 | Display Only 的 1,16；Display Only＋Invisible 的 1,2；都沒勾的 NONE |
| R4D | Component 動作：拿已知 Component 比 | ACTIONS 數字＋App Designer 勾了哪些 | 2＝只勾 Update/Display |
| R4E | 唯讀帳號還缺哪幾張表（32 張） | 沒有列＝都有；有列是要補的 GRANT | 沒有列 |

### 第五輪（2026-10-21，唯讀帳號）

| SQL | 盤點什麼 | 輸出怎麼看 | 結果 |
|---|---|---|---|
| R5A | 代碼 10、15、23、24 是什麼（和社群說法不一致的四個） | 每個代碼：N 筆數、LVL 在層裡的比例、REC 綁欄位、LBL 有標籤、GRID 在 Grid 裡；再用樣本在 App Designer Order 頁籤以 tab order 找到那個元件看類型 | 10 Scroll Bar、15 External Link 按鈕、23 Horizontal Rule、24 Tab Separator（數字見下表） |
| R5B | FIELDUSE 8、16 和相關顯示的對應 | CTL_N 控制欄數、B8_N 帶 8 的欄位數、BOTH8 兩者都是；REL_N、B16_N、BOTH16 同理 | CTL_N 1105、B8_N 2044、BOTH8 84、REL_N 1984 → 8 和用 tab order 找到的控制欄對不上 |

R5A 的數字（N、LVL、REC、LBL、GRID）：

| 代碼 | N | LVL | REC | LBL | GRID | App Designer |
|---|---|---|---|---|---|---|
| 10 | 30 | 100 | 0 | 100 | 0 | Scroll Bar |
| 15 | 1 | 0 | 00（照回報） | 100 | 0 | 按鈕，Destination External Link（另註有填 Record name） |
| 19 | 587 | 100 | 100 | 24 | 16 | Grid（對照） |
| 23 | 59 | 31 | 2 | 0 | 0 | Horizontal Rule |
| 24 | 9 | 100 | 0 | 100 | 100 | Tab Separator |
| 27 | 588 | 100 | 0 | 54 | 2 | Scroll Area（對照） |

這次也確認了：PSPNLFIELD.FIELDNUM 就是 App Designer Order 頁籤的 tab order。

### 第六輪（待跑）

| SQL | 盤點什麼 | 輸出怎麼看 |
|---|---|---|
| R6 | 相關顯示的 ASSOCFIELDNUM 存的是控制欄的 tab order（H0）還是 Field ID（H3） | `N= SAME= H0=a,b,c,d H3=a,b,c,d B16=x,y DUPID=z`：a 找到的控制欄數、b 其中有 prompt 的、c prompt 表＝相關顯示 Record 的、d 帶 8 的；H3 明顯大於 H0、且 d 接近 a → 存的是 Field ID、8＝Display Control；反過來 → 維持 tab order。B16 兩個數接近 N → 16 和 ASSOCFIELDNUM 一一對應。DUPID 應為 0 |

---

## 4. 框架正式在用的兩支查詢：結果怎麼解讀

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

- 相關顯示的對應（2.3）與 FIELDUSE 8（2.2）：等 R6。
- 代碼 15 External Link 的網址存在哪個欄位：沒查。
- 權限表 PSAUTHITEM.AUTHORIZEDACTIONS：和 ACTIONS 同一組位元，但 128 的意思各家說法不一，還沒解碼。
- 搜尋 Record 的搜尋鍵與清單欄位：§2m 只給 Record 名。

## 6. SQL 原文位置（repo）

| SQL | 檔案 |
|---|---|
| V1～V7、G1、權限檢查 | `docs/design/ui-metadata-check-r1.md`（整份可跑版 `ui-metadata-check-r1.sql`） |
| R2A～R2C | `docs/design/ui-metadata-check-r2.md` |
| R3A～R3C、唯讀帳號 A 測試 | `docs/design/ui-metadata-check-r3.md` |
| R4A～R4E | `docs/design/ui-metadata-check-r4.md` |
| R5A、R5B（含官方／社群對照表與來源連結） | `docs/design/ui-metadata-check-r5.md` |
| R6 | `docs/design/ui-metadata-check-r6.md` |
| 正式查詢 §2l、§2m | `.opencode/peoplesoft/oracle-query-cookbook.md`（Claude Code 版：`claude-code/.claude/peoplesoft/oracle-query-cookbook.md`） |

第一到三輪的 SQL 是 admin 帳號設 CURRENT_SCHEMA 跑的，表名沒有帶擁有者；用唯讀帳號重跑要先把表名改成 `<schema>.表名`。
