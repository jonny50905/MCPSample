# PeopleSoft 畫面元件代碼確認：工作報告（2026-10-14～10-21）

## 摘要

- **目的**：讓 AI 寫的研究文件（NN）與重建用的 Spec，能正確說出畫面上每個欄位「是什麼元件、唯讀還是可改、必不必填、
  輸入值去哪裡查、相關顯示對應哪個代碼欄、這個 Component 能不能新增或更正」。
- **難點**：這些設定在 PeopleTools 的表裡全是**數字代碼**，很多還是好幾個勾選加總成一個數字；Oracle 沒有公開完整對照，
  網路上只有零散、年代久遠、彼此矛盾的社群整理。每個代碼都要在公司環境實際確認，確認過的才能讓 AI 拿來翻譯。
- **做法**：分 **7 輪**、下了 **39 段 SQL**（驗證、授權檢查、App Designer 對照用）。每段 SQL 都設計成自己判斷對錯，輸出一行只有代碼與比例的結果，
  不帶任何公司資料；需要時再到 App Designer 拿已知的頁面、欄位、Component 逐一核對。
- **結果**：頁面元件 22 種代碼、元件屬性 4 個位元、Record 欄位設定 10 個位元、Component 動作 4 個位元、相關顯示的對應規則全部定案，
  寫進框架的 2 段正式查詢，研究文件新增「## 畫面元件」一節。過程中推翻了 3 次錯誤的假設，第 7 輪才定案。

---

## 1. 為什麼要做

研究文件原本只知道欄位的資料型別（字元、數字、日期），寫不出畫面長什麼樣子、哪些欄位不能改、哪些必填、下拉選單的值從哪裡來。
拿這樣的文件去重建功能，畫面與檢核規則會缺一大塊。

這些資訊都存在 PeopleTools 的定義表裡（頁面欄位表、Record 欄位表、Component 定義表），但存的是數字：

| 想知道的事 | 存在哪裡 | 怎麼存 |
|---|---|---|
| 這個欄位是什麼元件（輸入框、下拉選單、按鈕、Grid…） | 頁面欄位表的元件代碼 | 一個數字（0～32 之間），沒有官方對照 |
| 唯讀、隱藏、是不是相關顯示 | 頁面欄位表的使用旗標 | 多個勾選**加總**成一個數字 |
| 相關顯示（代碼旁的說明欄）對應哪個代碼欄 | 頁面欄位表的關聯欄號 | 一個編號，起算方式沒有文件 |
| 鍵、必填、Translate 檢核、Y/N、Prompt 檢核、自動押時間 | Record 欄位表的設定旗標 | 多個勾選加總成一個數字 |
| Component 能新增、修改、看歷史、更正 | Component 定義表的動作旗標 | 多個勾選加總成一個數字 |

只要有一個代碼翻錯，AI 就會很有自信地寫錯（例如把唯讀欄位寫成可改），而且讀的人很難發現。所以先確認、再使用。

---

## 2. 難在哪裡

1. **沒有官方對照表**。Oracle 只在 PeopleCode API 文件裡列了 Record 欄位設定的位元；頁面元件代碼、使用旗標、關聯欄號、Component 動作都沒有公開。
   社群整理多半是十幾年前的部落格，版本不同、彼此說法不一，只能當線索。
2. **一個數字裡藏好幾個勾選**。例如使用旗標 17＝唯讀（1）＋相關顯示（16）。要先猜出每個位元的意思，再設計能把它們分開驗證的查法。
3. **維護端看不到公司資料**。資料庫在公司內網，維護端無法連線；每輪 SQL 都由管理者在公司手動執行、把結果打字回報。
   所以 SQL 必須：自己判斷 OK／CHECK、輸出只有一行、只含代碼與比例、不含任何頁面名稱或資料值。
4. **正式環境的效能限制**。第一版對整張頁面欄位表做統計，在 PROD 上跑太久，改成只看客製頁面（名稱前綴走索引）、先分組再彙總。
5. **唯讀帳號的限制**。AI 用的唯讀帳號不能切換 schema、DBA 也不建同義字，不加擁有者的表名一律查不到。
   框架裡 61 段查詢樣板全部改寫成「擁有者.表名」，並加了唯讀帳號的授權檢查。
6. **假設會錯，而且錯得很像對**。這次推翻了 3 次：
   - 位元 16 一開始看起來像「唯讀」，拿已知欄位核對才發現唯讀是 1，16 是「相關顯示」。
   - 相關顯示的關聯欄號，先後試了 6 種對應：控制欄的 tab order 等於關聯欄號、等於關聯欄號＋1、等於關聯欄號−1、相關顯示的前一個欄位、
     控制欄的 Field ID 等於關聯欄號、等於關聯欄號＋1。其中兩種在前幾輪看起來都說得通，第六輪才確定它們都不對，
     第七輪確認是「tab order＝關聯欄號＋1」（從 0 起算）。
   - 前幾輪用「關聯欄號大於 0」挑相關顯示，漏掉了指到第 1 個欄位的那批（它們的關聯欄號剛好是 0）。
7. **兩套前端都要一致**。框架有 OpenCode 與 Claude Code 兩版，查詢手冊、研究範本、子代理回報格式、補研究、Spec 引擎都要同步修改，
   再用 Windows PowerShell 5.1 的自動測試確認沒有改壞。

---

## 3. 七輪驗證的經過

| 輪次 | 日期 | 重點 | 結果 |
|---|---|---|---|
| 第一輪 | 10-14～10-19 | 環境前提、資料型別、Record 欄位設定位元、元件代碼 0～11 | 版本 8.59；Record 欄位設定位元成立；元件代碼 0～11 成立；第一版太慢改輕量版 |
| 第二輪 | 10-19 | 頁面欄位表有哪些欄、找一個頁面到 App Designer 核對 | 找到關聯欄號與按鈕目標欄；Grid 確認 |
| 第三輪 | 10-19 | 其餘元件代碼依特徵判斷、唯讀位元、必填旁證、唯讀帳號測試 | 6 種按鈕／版面代碼成立；4 種判不出；唯讀帳號查不到 → 框架改寫表名 |
| 第四輪 | 10-20 | 改用唯讀帳號；拿 App Designer 已知欄位核對必填、唯讀、隱藏、Component 動作 | 必填、唯讀、隱藏、Component 動作確認；框架加入「畫面元件」查詢 |
| （對照） | 10-20 | 與 Oracle 文件、社群整理比對 | Record 欄位設定與官方一致；4 個元件代碼與社群說法不一致 |
| 第五輪 | 10-21 | 4 個不一致的代碼拿到 App Designer 看 | 4 個都確認（捲軸、外部連結按鈕、分隔線、Grid 分頁） |
| 第六輪 | 10-21 | 相關顯示的對應：tab order 或 Field ID | 兩種都不對；發現關聯欄號為 0 的一批 |
| 第七輪 | 10-21 | 「從 0 起算」的假設；交給公司內可查 DB 的 Claude 抽查 | 確認：控制欄 tab order＝關聯欄號＋1；位元 8＝控制欄 |

---

## 4. 下了哪些 SQL、各自的用途

> SQL 名稱前的字母是輪次（V＝第一輪，R2～R7＝第二到第七輪）。每段的原文與「怎麼看」都在 repo 的 `docs/design/ui-metadata-check-r1.md`～`r7.md`。

### 第一輪：先確認環境，再驗最基本的代碼

| SQL | 用途 | 對盤點的幫助 |
|---|---|---|
| V0（2 段） | 設定 schema、確認擁有者 | 讓後面的查詢找得到表 |
| V1 | 確認 AI 要用的定義表都看得到 | 排除權限問題，免得結果是空的被誤判 |
| V2 | 查 PeopleTools 版本 | 代碼可能隨版本不同，結論要標版本（8.59） |
| V3、V3b、V3c（共 4 段） | 確認後面要用的欄位都存在、找相關欄位的候選欄名 | 免得查詢在公司環境報錯；找出「關聯欄號」等候選欄 |
| V4a～V4d（4 段） | 欄位資料型別、Record 種類的代碼：拿已知欄位與 Record 比 | 確認字元／數字／日期、實體表／Derived 的代碼，Prompt 表種類要用到 |
| V5 | Record 欄位設定 10 個位元：用旁證自我核對（例：有 Prompt 檢核的欄位一定有 Prompt 表、Y/N 欄位一定是 1 碼） | 確認鍵、Translate、Y/N、Prompt 檢核、自動押時間等位元的意思 |
| V6 | 元件代碼 0～11：用特徵自我核對（例：核取方塊綁 1 碼欄位、子頁面有子頁名）；列出其他待確認的代碼 | 確認輸入框、下拉選單、核取方塊、選項按鈕、子頁面等；第一版在 PROD 太慢，改成只看客製頁面 |
| G1 | 代碼 2 是不是 Group Box：看框裡有沒有其他元件 | V6 的判斷條件對 Group Box 不準，改用形狀確認 |
| V7 | Prompt 的種類分布（view、有效日期、SetID） | 了解查值邏輯多半在 view 裡，決定研究要怎麼追 |
| 權限（3 段） | 給 AI 唯讀帳號的授權清單、授權後的檢查、同義字備案 | 讓 AI 自己能查這些表 |

### 第二輪：找到關鍵欄位、開始用 App Designer 核對

| SQL | 用途 | 對盤點的幫助 |
|---|---|---|
| R2A | 頁面欄位表有沒有「顯示控制」「關聯欄號」「按鈕目標」這類欄（一串 Y／N） | 找到關聯欄號與 7 個按鈕目標欄，之後判斷相關顯示與連結都靠它們 |
| R2B | 找一個有待確認代碼的客製頁面 | 讓管理者拿到 App Designer 逐一對照 |
| R2C | 列出那一頁的元件，對 App Designer 的類型 | 確認 Grid 的代碼 |

### 第三輪：依特徵判斷其餘代碼

| SQL | 用途 | 對盤點的幫助 |
|---|---|---|
| R3A | 其餘元件代碼：看有沒有子頁名、轉頁目標、綁欄位、長字元、框內有沒有元件 | 確認 3 種按鈕、次頁、HTML 區、捲動區；另 4 種判不出，留給第五輪 |
| R3B | 從相關顯示共有的位元找「唯讀」與「控制欄」的位元 | 找到 16（後來證明是相關顯示的旗標，不是唯讀） |
| R3C | 鍵欄位會不會自動算必填 | 證明不會，必填要另外核對 |
| 唯讀帳號測試 | AI 的唯讀帳號查不查得到 | 查不到 → 框架全面改寫表名（61 段樣板） |

### 第四輪：改用唯讀帳號，拿已知物件核對

| SQL | 用途 | 對盤點的幫助 |
|---|---|---|
| R4A | 相關顯示指到哪一欄：同時比 4 種對應 | 當時選出一種（後來第六、七輪修正） |
| R4B | 必填位元：拿 App Designer 勾了／沒勾 Required 的欄位比 | 確認 256＝必填 |
| R4C | 唯讀、隱藏位元：拿 App Designer 勾了 Display Only／Invisible 的欄位比 | 確認 1＝唯讀、2＝隱藏，並推翻「16＝唯讀」 |
| R4D（2 段） | Component 動作：拿已知 Component 比 | 確認 Add／Update/Display／Update/Display All／Correction 四個位元 |
| R4E | 唯讀帳號還缺哪些表的權限（32 張） | 確認 AI 用得到的表全部有權限 |

### 第五輪：和官方說法不一致的代碼

| SQL | 用途 | 對盤點的幫助 |
|---|---|---|
| R5A | 4 個代碼的特徵，加一個樣本頁讓管理者在 App Designer 找到那個元件 | 確認舊式捲軸、外部連結按鈕、分隔線、Grid 分頁 |
| R5B | 位元 8 是不是「控制欄」 | 和當時的相關顯示對應對不上 → 發現對應有問題 |

### 第六、七輪：把相關顯示的對應找出來

| SQL | 用途 | 對盤點的幫助 |
|---|---|---|
| R6 | 同時比「tab order」與「Field ID」兩種對應 | 兩種都不對；發現關聯欄號為 0 的相關顯示 |
| R6B | App Designer 對一個例子（備用） | — |
| R7 | 同時比「tab order＋1」與「Field ID＋1」 | 交給公司內可查 DB 的 Claude 執行 |
| R7B | App Designer 對一個例子（備用） | — |
| R7K | 用更強的依據比 5 種對應：真正的控制欄，欄位名通常是相關顯示那張表的鍵，而且帶控制欄位元 | 公司內的 Claude 跑完再抽查實例：**控制欄 tab order＝關聯欄號＋1、位元 8＝控制欄**，定案 |

### 正式查詢（框架在用，研究時每個頁面跑一次）

| SQL | 用途 |
|---|---|
| 畫面元件查詢（查詢手冊 §2l） | 一個頁面一次：每個元件的種類、唯讀／隱藏、相關顯示與控制欄、鍵、必填、Translate／Y/N、Prompt 表與檢核方式、轉頁目標、子頁面；解碼全在 SQL 裡 |
| Component 動作查詢（查詢手冊 §2m） | 一個 Component 一次：允許的動作、搜尋用的 Record |

---

## 5. 確認了什麼（代碼對照摘要）

| 類別 | 確認的內容 |
|---|---|
| 頁面元件（22 種） | 靜態文字、框、Group Box、靜態圖、輸入框、下拉選單、長文字框、核取方塊、選項按鈕、圖片、舊式捲軸、子頁面、按鈕（執行 PeopleCode／外部連結／轉到別的 Component／開次頁）、次頁、Grid、分隔線、Grid 分頁、HTML 區、捲動區 |
| 元件屬性（4 個位元） | 1＝唯讀、2＝隱藏、8＝相關顯示的控制欄、16＝相關顯示 |
| 相關顯示的對應 | 控制欄的 tab order＝關聯欄號＋1（從 0 起算） |
| Record 欄位設定（10 個位元） | 鍵、清單欄位、遞減鍵、必填、Translate 檢核、搜尋鍵、合理日期、Y/N、Prompt 檢核、自動押時間 |
| Prompt | 有 Prompt 表、動態 Prompt（執行期才決定）、會不會檢核、Prompt 表是實體表／view／Derived |
| Component 動作（4 個位元） | 新增、修改、看歷史、更正 |

完整對照與每一項怎麼確認的，見 `docs/design/ui-control-sql-record.md`。

---

## 6. 怎麼確保是對的

- **自我核對**：每段 SQL 用旁證判斷 OK／CHECK（例：標成核取方塊的元件，綁的應該都是 1 碼欄位），不靠人看大量資料。
- **已知物件對照**：在 App Designer 打開已知的頁面、欄位、Component，看勾選與 SQL 解出來的是否一致。
- **官方與社群文件比對**：和 Oracle 文件一致的直接採用；不一致的再拿到 App Designer 確認。
- **假設互相比較**：同一段 SQL 同時算多種可能的對應，用「控制欄有沒有 Prompt」「控制欄是不是相關顯示那張表的鍵」這類可以分出高下的指標選出對的。
- **先在本機用假資料測過**：每段 SQL 送出前，都先在本機用合成資料（假名稱）跑過，確認語法正確、分得出對錯，才交給管理者執行。
- **第二雙眼睛**：最後一輪交給公司內可以查 DB 的 Claude 獨立執行並抽查實例。
- **只確認意思、不盤點數量**：比例只當判斷依據，紀錄不寫公司系統裡各有幾個。

---

## 7. 成果用在哪裡

- 兩版框架（OpenCode、Claude Code）的查詢手冊加了 2 段正式查詢；研究文件範本新增「## 畫面元件」一節，AI 研究有畫面的功能時會照表寫出每個元件。
- 已經寫好的研究文件可以用「補研究」補上這一節；重建用的 Spec 引擎也會讀這一節。
- 子代理回報格式、問答時要讀哪一節、搬運包、自動測試（含 Windows PowerShell 5.1 CI）都同步更新並通過。
- 每一步的原因與結果都記在框架的教訓帳本（L150～L157），之後接手的人可以重查。

## 8. 還沒做的事

- 外部連結按鈕的網址存在哪一欄（沒查）。
- 權限表的動作代碼（和 Component 動作同一組位元，但其中一個位元的意思各家說法不一，還沒解碼）。
- 搜尋 Record 的搜尋條件欄位。
- 用新版框架實際研究一個有畫面的功能，確認「## 畫面元件」照表寫出（等公司機搬新版）。

---

## 附錄 A：代表性 SQL（看得出複雜度）

**A1 正式查詢：一個頁面的所有元件與屬性（查詢手冊 §2l）**——一段 SQL 同時解出元件種類、5 種屬性、相關顯示對應、
4 種 Record 設定、Prompt 表種類與鍵；`<schema>` 執行時換成擁有者名稱。

```sql
SELECT P.FIELDNUM, P.OCCURSLEVEL AS LVL, P.FIELDTYPE AS CODE,
       CASE P.FIELDTYPE WHEN 4 THEN 'Edit Box' WHEN 5 THEN 'Drop-Down List Box' WHEN 6 THEN 'Long Edit Box'
                        WHEN 7 THEN 'Check Box' WHEN 8 THEN 'Radio Button' WHEN 9 THEN 'Image'
                        WHEN 10 THEN 'Scroll Bar' WHEN 11 THEN 'Subpage'
                        WHEN 12 THEN 'Push Button/Hyperlink: PeopleCode Command'
                        WHEN 15 THEN 'Push Button/Hyperlink: External Link'
                        WHEN 16 THEN 'Push Button/Hyperlink: Internal Link' WHEN 18 THEN 'Secondary Page'
                        WHEN 19 THEN 'Grid' WHEN 21 THEN 'Push Button/Hyperlink: Secondary Page'
                        WHEN 24 THEN 'Tab Separator' WHEN 25 THEN 'HTML Area' WHEN 27 THEN 'Scroll Area'
                        ELSE 'OTHER' END AS CONTROL,
       TRIM(P.RECNAME) AS RECNAME, TRIM(P.FIELDNAME) AS FIELDNAME, TRIM(P.LBLTEXT) AS LBLTEXT,
       CASE WHEN BITAND(P.FIELDUSE, 1) > 0 THEN 'DISPLAY_ONLY' END AS DO,
       CASE WHEN BITAND(P.FIELDUSE, 2) > 0 THEN 'INVISIBLE' END AS INV,
       CASE WHEN BITAND(P.FIELDUSE, 16) > 0 THEN P.ASSOCFIELDNUM + 1 END AS RELATED_TO,
       CASE WHEN BITAND(P.FIELDUSE, 8) > 0 THEN 'DISPLAY_CONTROL' END AS DC,
       CASE WHEN BITAND(F.USEEDIT, 1) > 0 THEN 'KEY' END AS KEY_FLAG,
       CASE WHEN BITAND(F.USEEDIT, 256) > 0 THEN 'REQUIRED' END AS REQ,
       CASE WHEN BITAND(F.USEEDIT, 4096) > 0 THEN 'REASONABLE_DATE' END AS RDATE,
       CASE WHEN BITAND(F.USEEDIT, 32768) > 0 THEN 'AUTO_UPDATE' END AS AUPD,
       CASE WHEN BITAND(F.USEEDIT, 512) > 0 THEN 'XLAT' WHEN BITAND(F.USEEDIT, 8192) > 0 THEN 'YES_NO' END AS VALUES_EDIT,
       TRIM(F.EDITTABLE) AS PROMPT_REC,
       CASE WHEN TRIM(F.EDITTABLE) IS NULL THEN NULL
            WHEN SUBSTR(TRIM(F.EDITTABLE), 1, 1) = '%' THEN 'DYNAMIC'
            WHEN BITAND(F.USEEDIT, 16384) > 0 THEN 'EDIT' ELSE 'NO_EDIT' END AS PROMPT_EDIT,
       (SELECT CASE WHEN R.RECTYPE = 0 THEN 'TABLE' WHEN R.RECTYPE IN (1, 5, 6) THEN 'VIEW'
                    WHEN R.RECTYPE = 2 THEN 'DERIVED' ELSE 'OTHER' END
          FROM <schema>.PSRECDEFN R WHERE R.RECNAME = TRIM(F.EDITTABLE)) AS PROMPT_KIND,
       (SELECT LISTAGG(TRIM(K.FIELDNAME), ',') WITHIN GROUP (ORDER BY K.FIELDNUM)
          FROM <schema>.PSRECFIELDDB K
         WHERE K.RECNAME = TRIM(F.EDITTABLE) AND BITAND(K.USEEDIT, 1) > 0) AS PROMPT_KEYS,
       TRIM(P.GOTOPNLGRPNAME) AS GOTO_COMPONENT, TRIM(P.SUBPNLNAME) AS SUBPAGE
  FROM <schema>.PSPNLFIELD P
  LEFT JOIN <schema>.PSRECFIELDDB F ON F.RECNAME = P.RECNAME AND F.FIELDNAME = P.FIELDNAME
 WHERE P.PNLNAME = :pageName
   AND P.FIELDTYPE NOT IN (0, 1, 2, 3, 23)
   AND P.FIELDNUM > :afterFieldNum
 ORDER BY P.FIELDNUM
FETCH FIRST 40 ROWS ONLY
```

**A2 第七輪：一次比較 5 種相關顯示的對應**——每種對應算「控制欄是不是相關顯示那張表的鍵」與「控制欄有沒有帶控制欄位元」兩個比例。

```sql
WITH P AS (
  SELECT PNLNAME, FIELDNUM, TRIM(TO_CHAR(PNLFLDID)) AS FLDID, RECNAME, FIELDNAME, FIELDUSE, ASSOCFIELDNUM
    FROM <schema>.PSPNLFIELD
   WHERE PNLNAME LIKE 'TW\_%' ESCAPE '\'
),
REL AS (SELECT * FROM P WHERE BITAND(FIELDUSE, 16) > 0),
H AS (
  SELECT 'H0' AS HYP, R.RECNAME AS RREC, C.FIELDNAME AS CFLD, C.FIELDUSE AS CUSE
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FIELDNUM = R.ASSOCFIELDNUM
  UNION ALL
  SELECT 'H1', R.RECNAME, C.FIELDNAME, C.FIELDUSE
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FIELDNUM = R.ASSOCFIELDNUM + 1
  UNION ALL
  SELECT 'H3', R.RECNAME, C.FIELDNAME, C.FIELDUSE
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FLDID = TO_CHAR(R.ASSOCFIELDNUM)
  UNION ALL
  SELECT 'H4', R.RECNAME, C.FIELDNAME, C.FIELDUSE
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FLDID = TO_CHAR(R.ASSOCFIELDNUM + 1)
  UNION ALL
  SELECT 'NB', R.RECNAME, C.FIELDNAME, C.FIELDUSE
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FIELDNUM = R.FIELDNUM - 1
),
HK AS (
  SELECT H.HYP, H.CUSE,
         CASE WHEN EXISTS (SELECT 1 FROM <schema>.PSRECFIELDDB K
                            WHERE K.RECNAME = H.RREC AND K.FIELDNAME = H.CFLD AND BITAND(K.USEEDIT, 1) > 0)
              THEN 1 ELSE 0 END AS ISKEY
    FROM H
)
SELECT HYP, COUNT(*) AS N, ROUND(100 * AVG(ISKEY)) AS KEY_PCT, ROUND(100 * AVG(SIGN(BITAND(CUSE, 8)))) AS B8_PCT
  FROM HK
 GROUP BY HYP
 ORDER BY HYP;
```

## 附錄 B：詳細文件

| 文件 | 內容 |
|---|---|
| `docs/design/ui-control-sql-record.md` | 代碼確認紀錄：每個代碼是什麼、怎麼確認、輸出怎麼讀 |
| `docs/design/ui-metadata-check-r1.md`～`r7.md` | 七輪驗證 SQL 原文、怎麼看、各輪結果 |
| `docs/design/ui-control-lookup-dependency-memo.md` | 起始的缺口盤點與規劃（§7） |
| `.opencode/peoplesoft/lessons/applied.md` | 框架教訓帳本（L150～L157） |
