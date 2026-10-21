# 畫面元件盤點 SQL 紀錄（PeopleTools 8.59，2026-10）

> 這份整理「畫面元件、元件屬性、查值（Prompt）、Component 動作」盤點用到的 SQL，給管理者留存。
> 執行前把 `<schema>` 全部取代成擁有者名稱（不加引號）：agent 用的唯讀帳號只查得到「擁有者.表名」。
> 文中只有 PeopleTools 產品的表名、欄位名與代碼；數字結果是公司環境客製頁面（`TW_` 開頭）的彙總，沒有公司資料。
> 第 1 節是框架正式在用的查詢；第 2 節是代碼對照與確認方式；第 3 節是各輪驗證的查詢與結果；第 4 節是還沒定案的事。

## 目錄

1. 正式查詢（框架在用）
   - 1.1 Page 上的元件與屬性（cookbook §2l）
   - 1.2 Component 的動作與搜尋 Record（cookbook §2m）
2. 代碼對照（已確認的）
3. 驗證查詢與結果（依輪次）
4. 還沒定案
5. 來源

---

## 1. 正式查詢（框架在用）

### 1.1 Page 上的元件與屬性（cookbook §2l）

一個 Page 跑一次，一次最多 40 列。`:pageName` 填頁名；`:afterFieldNum` 第一次填 0，回滿 40 列時換成最後一列的 FIELDNUM 再跑，直到不滿 40 列。
Static Text、Frame、Group Box、Static Image、Horizontal Rule 不列（版面與裝飾）。解碼全在 SQL 裡、不含 `||`，結果可以直接當 NN 的證據。

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
       CASE WHEN P.ASSOCFIELDNUM > 0 THEN P.ASSOCFIELDNUM END AS RELATED_TO,
       CASE WHEN EXISTS (SELECT 1 FROM <schema>.PSPNLFIELD C
                          WHERE C.PNLNAME = P.PNLNAME AND C.ASSOCFIELDNUM = P.FIELDNUM) THEN 'DISPLAY_CONTROL' END AS DC,
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

| 欄 | 意思 |
|---|---|
| FIELDNUM | 元件在頁面上的順序，就是 App Designer Order 頁籤的 tab order |
| LVL | 層級：0＝頁面本身，1 以上＝在 Grid／Scroll 裡 |
| CODE、CONTROL | 元件代碼與名稱（第 2 節）；沒解碼的寫 OTHER，原始代碼看 CODE |
| RECNAME、FIELDNAME、LBLTEXT | 綁的 Record 欄位、標籤文字 |
| DO、INV | 設計期勾了 Display Only、Invisible |
| RELATED_TO | 本列是相關顯示（代碼旁的說明欄）時，指到的控制欄編號（**待第六輪確認**，見第 4 節） |
| DC | 有相關顯示以本列為控制欄（**同上待確認**） |
| KEY_FLAG、REQ、RDATE、AUPD | Record 欄位的設定：鍵、必填、合理日期檢查、存檔時自動押時間 |
| VALUES_EDIT | XLAT＝值要在 Translate 清單內；YES_NO＝只收 Y／N |
| PROMPT_REC | Prompt 表；`%` 開頭＝動態 prompt（執行期由另一個欄位的值決定） |
| PROMPT_EDIT | EDIT＝輸入值必須在 prompt 清單內；NO_EDIT＝只給查詢、不檢核；DYNAMIC＝動態 prompt |
| PROMPT_KIND | Prompt 表的種類：TABLE、VIEW、DERIVED、OTHER |
| PROMPT_KEYS | Prompt 表的鍵（依欄位順序，含 SETID、EFFDT 照實列） |
| GOTO_COMPONENT | Internal Link 按鈕轉到的 Component |
| SUBPAGE | Subpage、Secondary Page 的頁名（以它再跑一次本查詢，深度最多 8 層） |

寫進研究文件（NN「## 畫面元件」）時一列一個元件：

| 頁面 | # | 欄位 | 元件 | 屬性 | 查值 |
|---|---|---|---|---|---|
| TW_DEMO_PG | 4 | TW_DEMO_REQHDR.DEPTID | Edit Box | DISPLAY_CONTROL REQUIRED | PROMPT TW_DEMO_DEPTVW EDIT（VIEW；鍵 SETID,DEPTID,EFFDT） |
| TW_DEMO_PG | 5 | TW_DEMO_DEPTVW.DESCR | Edit Box | DISPLAY_ONLY RELATED_TO=4 |  |
| TW_DEMO_PG | 6 | TW_DEMO_REQHDR.REQ_TYPE | Drop-Down List Box |  | XLAT |
| TW_DEMO_PG | 11 | TW_DEMO_WRK.APPROVE_PB | Push Button/Hyperlink: PeopleCode Command |  |  |

（例子是合成名稱。）屬性欄依序串 DO、INV、DC、KEY_FLAG、REQ、RDATE、AUPD 有值的字樣，再接 `RELATED_TO=`、`LEVEL=`、`GOTO=`、`PAGE=`；
查值欄有 prompt 寫 `PROMPT <表> <EDIT 方式>（<種類>；鍵 <鍵>）`，沒有 prompt 寫 VALUES_EDIT。
這些都是設計期設定；PeopleCode 在執行期改的顯示、可改、必填另外寫在「行為邏輯」。

### 1.2 Component 的動作與搜尋 Record（cookbook §2m）

一個 Component 跑一次，寫成「## 畫面元件」表格的第一列。

```sql
SELECT TRIM(G.PNLGRPNAME) AS COMPONENT, G.ACTIONS AS CODE,
       CASE WHEN BITAND(G.ACTIONS, 1) > 0 THEN 'ADD' END AS ACT_ADD,
       CASE WHEN BITAND(G.ACTIONS, 2) > 0 THEN 'UPDATE_DISPLAY' END AS ACT_UPD,
       CASE WHEN BITAND(G.ACTIONS, 4) > 0 THEN 'UPDATE_DISPLAY_ALL' END AS ACT_ALL,
       CASE WHEN BITAND(G.ACTIONS, 8) > 0 THEN 'CORRECTION' END AS ACT_COR,
       CASE WHEN G.ACTIONS > BITAND(G.ACTIONS, 15) THEN G.ACTIONS - BITAND(G.ACTIONS, 15) END AS OTHER_BITS,
       TRIM(G.SEARCHRECNAME) AS SEARCH_REC, TRIM(G.ADDSRCHRECNAME) AS ADD_SEARCH_REC
  FROM <schema>.PSPNLGRPDEFN G
 WHERE G.PNLGRPNAME = :componentName
```

| 欄 | 意思 |
|---|---|
| CODE | PSPNLGRPDEFN.ACTIONS 原始數字 |
| ACT_ADD、ACT_UPD、ACT_ALL、ACT_COR | Add、Update/Display、Update/Display All、Correction（Component Properties → Use 的 Actions 勾選） |
| OTHER_BITS | 四個動作以外的位元，照數字寫、不猜意思 |
| SEARCH_REC、ADD_SEARCH_REC | 搜尋頁查的 Record、新增用的搜尋 Record（沒有＝新增也用 SEARCH_REC） |

寫進 NN 的第一列（頁面＝Component 名、#＝0、元件＝Component）：

| 頁面 | # | 欄位 | 元件 | 屬性 | 查值 |
|---|---|---|---|---|---|
| TW_DEMO_REQ | 0 |  | Component | ADD UPDATE_DISPLAY | SEARCH TW_DEMO_REQSRCH |

四個動作：ADD＝可以新增一筆新鍵值；UPDATE_DISPLAY＝改既有資料，有效日期的列只看得到目前與未來；UPDATE_DISPLAY_ALL＝看得到歷史列、
只能改目前與未來；CORRECTION＝連歷史列都能改。沒有有效日期列的 Component，後三者效果相同。使用者實際能用哪幾個，還要看權限
（Permission List 對該 Menu Item 授權的動作）。

---

## 2. 代碼對照（已確認的）

**元件代碼（PSPNLFIELD.FIELDTYPE）**

| 代碼 | App Designer 名稱 | §2l 的處理 | 怎麼確認的 |
|---|---|---|---|
| 0 | Static Text | 不列 | 第一輪 V6（特徵） |
| 1 | Frame | 不列 | 第一輪 V6 |
| 2 | Group Box | 不列（顯示條件走 §2h～§2i） | 第一輪 G1（98% 框內有元件） |
| 3 | Static Image | 不列 | 第一輪 V6 |
| 4 | Edit Box | Edit Box | 第一輪 V6 |
| 5 | Drop-Down List Box | Drop-Down List Box | 第一輪 V6 |
| 6 | Long Edit Box | Long Edit Box | 第一輪 V6 |
| 7 | Check Box | Check Box | 第一輪 V6 |
| 8 | Radio Button | Radio Button | 第一輪 V6 |
| 9 | Image | Image | 第一輪 V6 |
| 10 | Scroll Bar | Scroll Bar | 第五輪 R5A＋App Designer |
| 11 | Subpage | Subpage | 第一輪 V6 |
| 12 | Push Button/Hyperlink（Destination：PeopleCode Command） | Push Button/Hyperlink: PeopleCode Command | 第三輪 R3A（特徵） |
| 15 | Push Button/Hyperlink（Destination：External Link） | Push Button/Hyperlink: External Link | 第五輪 R5A＋App Designer |
| 16 | Push Button/Hyperlink（Destination：Internal Link） | Push Button/Hyperlink: Internal Link | 第三輪 R3A |
| 18 | Secondary Page | Secondary Page | 第三輪 R3A |
| 19 | Grid | Grid | 第二輪 R2C |
| 21 | Push Button/Hyperlink（Destination：Secondary Page） | Push Button/Hyperlink: Secondary Page | 第三輪 R3A |
| 23 | Horizontal Rule | 不列（裝飾線） | 第五輪 R5A＋App Designer |
| 24 | Tab Separator（Grid 分頁） | Tab Separator | 第五輪 R5A＋App Designer |
| 25 | HTML Area | HTML Area | 第三輪 R3A |
| 27 | Scroll Area | Scroll Area | 第三輪 R3A |
| 其他 | 客製頁面沒出現 | OTHER（代碼 n） | 社群表另有 13 Scroll Action、14 Toolbar Action、17 Process、20 Tree、26 Prompt Action、30 Chart 等按鈕／元件，沒在公司環境核對 |

**頁面欄位設計期屬性（PSPNLFIELD.FIELDUSE，位元）**

| 位元 | 意思 | 狀態 |
|---|---|---|
| 1 | Display Only | 已確認（R4C） |
| 2 | Invisible | 已確認（R4C；公司頁面沒有只勾 Invisible 的，都是 1＋2） |
| 16 | Related Field | R4C：相關顯示都是 1＋16（Oracle：勾 Related Field 會自動勾 Display Only）；和 ASSOCFIELDNUM 的對應待 R6 |
| 8 | Display Control | 社群說法；R5B 對不上 → 待 R6 |

**Record 欄位設定（PSRECFIELDDB.USEEDIT，位元）**——和 Oracle PeopleCode API 文件一致

| 位元 | 意思 | 確認 |
|---|---|---|
| 1 | Key | 第一輪 V5 |
| 32 | List Box Item | 第一輪 V5 |
| 64 | Descending Key | 第一輪 V5 |
| 256 | Required | 第四輪 R4B |
| 512 | Translate Table Edit | 第一輪 V5 |
| 2048 | Search Key（Oracle：Search Item） | 第一輪 V5 |
| 4096 | Reasonable Date Test（Oracle：Date Range Edit） | 第一輪 V5 |
| 8192 | Yes/No Table Edit | 第一輪 V5 |
| 16384 | Prompt Table Edit（Oracle：Edit Table） | 第一輪 V5 |
| 32768 | Auto-Update（日期／時間型欄位才算） | 第一輪 V5（98.6% 是日期／時間型） |

**其他**

| 項目 | 對照 | 確認 |
|---|---|---|
| PSRECDEFN.RECTYPE | 0 Table、2 Derived/Work（已核對）；1、5、6 是三種 View（SQL／Dynamic／Query View） | 第一輪 V4 |
| PSRECFIELDDB.EDITTABLE | `%` 開頭＝動態 prompt | 第一輪 V5（DYN＝4182） |
| PSPNLGRPDEFN.ACTIONS | 1 Add、2 Update/Display、4 Update/Display All、8 Correction | R4D 實測 2＝只勾 Update/Display；管理者確認順序 |
| PSPNLFIELD.ASSOCFIELDNUM | 相關顯示 → 它的控制欄 | 待 R6（存的是 tab order 還是 Field ID） |
| PSPNLFIELD.FIELDNUM | App Designer Order 頁籤的 tab order | 第五輪（管理者以 SAMPLE_NUM 對 tab order） |

---

## 3. 驗證查詢與結果（依輪次）

| 輪次（日期） | 查了什麼 | 結果 |
|---|---|---|
| 第一輪（10-14～10-19） | 表與欄位在不在、PeopleTools 版本、欄位型別與 Record 型別代碼、USEEDIT 位元、元件代碼、Group Box、Prompt 分布 | 8.59；USEEDIT 主要位元成立；元件代碼 0～9、11 成立；Prompt 的 Record 7291 個（view 74%、EFFDT 鍵 20%、SETID 鍵 5%、指向不存在的 Record 107） |
| 第二輪（10-19） | PSPNLFIELD 有哪些欄、找校準頁 | 有 ASSOCFIELDNUM 與 7 個 GOTO 欄；19＝Grid |
| 第三輪（10-19） | 依特徵判其餘代碼、唯讀位元、鍵與必填 | 12、16、18、21、25、27 成立；10、23 MIXED，15、24 CONTAINER；唯讀帳號 A 測試 FAIL → 表名一律帶擁有者 |
| 第四輪（10-20，唯讀帳號） | 相關顯示指向、256、唯讀／隱藏位元、Component 動作、唯讀帳號缺表 | H0 最好；256＝Required；1＝Display Only、2＝Invisible；ACTIONS 2＝Update/Display；32 張表都看得到 |
| 第五輪（10-21，唯讀帳號） | 代碼 10、15、23、24；FIELDUSE 8、16 | 四個代碼以 App Designer 確認；8 和 tab order 對應的控制欄對不上 |
| 第六輪（待跑） | 相關顯示存的是 tab order 還是 Field ID | — |

第一、二輪的 SQL 是管理者用 admin 帳號、先設 CURRENT_SCHEMA 跑的，篇幅長、而且有些對整張表做統計（PROD 上會久），這裡不重列；
原文在 repo 的 `docs/design/ui-metadata-check-r1.md`、`ui-metadata-check-r2.md`。以下第三輪起的 SQL 都已寫成 `<schema>.表名`。

### R3A 其餘元件代碼（依特徵判斷）

表名已補 `<schema>.`（當時是 admin 帳號設 CURRENT_SCHEMA 跑的）。

```sql
WITH P AS (
  SELECT PNLNAME, FIELDNUM, FIELDTYPE, RECNAME, FIELDNAME, SUBPNLNAME, GOTOPNLGRPNAME,
         FIELDLEFT, FIELDTOP, FIELDRIGHT, FIELDBOTTOM
    FROM <schema>.PSPNLFIELD
   WHERE PNLNAME LIKE 'TW\_%' ESCAPE '\'
     AND FIELDTYPE IN (10, 12, 15, 16, 18, 21, 23, 24, 25, 27)
),
F AS (
  SELECT P.FIELDTYPE,
         CASE WHEN TRIM(P.RECNAME) IS NOT NULL THEN 1 ELSE 0 END AS HASREC,
         CASE WHEN TRIM(P.SUBPNLNAME) IS NOT NULL THEN 1 ELSE 0 END AS HASSUB,
         CASE WHEN TRIM(P.GOTOPNLGRPNAME) IS NOT NULL THEN 1 ELSE 0 END AS HASGOTO,
         CASE WHEN D.FIELDTYPE = 1 THEN 1 ELSE 0 END AS ISLONG,
         CASE WHEN EXISTS (SELECT 1 FROM <schema>.PSPNLFIELD X
                            WHERE X.PNLNAME = P.PNLNAME AND X.FIELDNUM <> P.FIELDNUM
                              AND X.FIELDLEFT >= P.FIELDLEFT AND X.FIELDRIGHT <= P.FIELDRIGHT
                              AND X.FIELDTOP >= P.FIELDTOP AND X.FIELDBOTTOM <= P.FIELDBOTTOM)
              THEN 1 ELSE 0 END AS HASIN
    FROM P
    LEFT JOIN <schema>.PSDBFIELD D ON D.FIELDNAME = P.FIELDNAME AND TRIM(P.FIELDNAME) IS NOT NULL
),
T AS (
  SELECT FIELDTYPE, COUNT(*) AS CNT,
         ROUND(100 * AVG(HASREC)) AS REC_P, ROUND(100 * AVG(HASSUB)) AS SUB_P,
         ROUND(100 * AVG(HASGOTO)) AS GOTO_P, ROUND(100 * AVG(ISLONG)) AS LONG_P,
         ROUND(100 * AVG(HASIN)) AS IN_P
    FROM F
   GROUP BY FIELDTYPE
)
SELECT FIELDTYPE AS CODE,
       CASE FIELDTYPE WHEN 12 THEN 'BUTTON_PEOPLECODE' WHEN 16 THEN 'LINK_TO_COMPONENT'
                      WHEN 18 THEN 'SECONDARY_PAGE' WHEN 21 THEN 'BUTTON_TO_SECONDARY_PAGE'
                      WHEN 25 THEN 'HTML_AREA' WHEN 27 THEN 'SCROLL_AREA' ELSE 'OTHER' END AS GUESS,
       CNT,
       CASE WHEN FIELDTYPE = 12 AND REC_P >= 90 AND SUB_P < 10 AND GOTO_P < 10 THEN 'OK'
            WHEN FIELDTYPE = 16 AND GOTO_P >= 70 THEN 'OK'
            WHEN FIELDTYPE = 18 AND SUB_P >= 90 AND REC_P < 10 THEN 'OK'
            WHEN FIELDTYPE = 21 AND SUB_P >= 90 AND REC_P >= 50 THEN 'OK'
            WHEN FIELDTYPE = 25 AND LONG_P >= 50 THEN 'OK'
            WHEN FIELDTYPE = 27 AND IN_P >= 80 THEN 'OK'
            WHEN FIELDTYPE IN (12, 16, 18, 21, 25, 27) THEN 'CHECK'
            WHEN GOTO_P >= 70 THEN 'LINK'
            WHEN SUB_P >= 90 THEN 'SUBPAGE_LIKE'
            WHEN IN_P >= 80 THEN 'CONTAINER'
            WHEN IN_P < 20 THEN 'LINE_OR_SINGLE'
            ELSE 'MIXED' END AS RESULT
  FROM T
 ORDER BY FIELDTYPE;
```

判斷依據：12＝綁 Record 欄位、沒有 SUBPNLNAME 也沒有 GOTO 目標；16＝有 GOTOPNLGRPNAME；18＝有 SUBPNLNAME、沒綁 Record；21＝有 SUBPNLNAME、
綁 Record；25＝綁長字元欄位；27＝框裡有其他元件。結果：12、16、18、21、25、27 都 OK；10（30 筆）、23（59 筆）MIXED；15（1 筆）、24（9 筆）CONTAINER。

### R4A 相關顯示指到哪一欄

```sql
WITH P AS (
  SELECT PNLNAME, FIELDNUM, FIELDTYPE, RECNAME, FIELDNAME, ASSOCFIELDNUM
    FROM <schema>.PSPNLFIELD
   WHERE PNLNAME LIKE 'TW\_%' ESCAPE '\'
),
REL AS (SELECT * FROM P WHERE ASSOCFIELDNUM > 0),
H AS (
  SELECT 'H0' AS HYP, R.RECNAME AS RREC, C.RECNAME AS CREC, C.FIELDNAME AS CFLD
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FIELDNUM = R.ASSOCFIELDNUM
  UNION ALL
  SELECT 'H1', R.RECNAME, C.RECNAME, C.FIELDNAME
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FIELDNUM = R.ASSOCFIELDNUM + 1
  UNION ALL
  SELECT 'H2', R.RECNAME, C.RECNAME, C.FIELDNAME
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FIELDNUM = R.ASSOCFIELDNUM - 1
  UNION ALL
  SELECT 'NB', R.RECNAME, C.RECNAME, C.FIELDNAME
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FIELDNUM = R.FIELDNUM - 1
  UNION ALL
  SELECT 'ALL', NULL, P.RECNAME, P.FIELDNAME
    FROM P WHERE P.FIELDTYPE = 4 AND TRIM(P.RECNAME) IS NOT NULL
),
S AS (
  SELECT H.HYP, COUNT(*) AS N,
         ROUND(100 * AVG(CASE WHEN TRIM(F.EDITTABLE) IS NOT NULL THEN 1 ELSE 0 END)) AS PR,
         ROUND(100 * AVG(CASE WHEN TRIM(F.EDITTABLE) = TRIM(H.RREC) THEN 1 ELSE 0 END)) AS RM
    FROM H
    LEFT JOIN <schema>.PSRECFIELDDB F ON F.RECNAME = H.CREC AND F.FIELDNAME = H.CFLD
   GROUP BY H.HYP
)
SELECT LISTAGG(HYP || ':N=' || N || ',P=' || PR || ',R=' || RM, ' ') WITHIN GROUP (ORDER BY HYP) AS RESULT
  FROM S;
```

H0＝ASSOCFIELDNUM 就是控制欄的 FIELDNUM；H1／H2＝差一號；NB＝相關顯示的前一個欄位；ALL＝客製頁面全部 Edit Box（對照）。
P＝指到的欄有 prompt 的比例、R＝prompt 表就是相關顯示 Record 的比例。
結果：ALL N 15154 P 14 R 0；H0 N 1984 P 54 R 22；H2 N 1867 P 13 R 1；NB N 1984 P 41 R 17（H1 沒回）→ 當時判 H0（第五輪起存疑，見第 4 節）。

### R4B USEEDIT 256 是不是「必填」

```sql
WITH K AS (
  SELECT 'REQ' AS KIND, '<必填欄的Record>' AS REC, '<必填欄>' AS FLD FROM DUAL UNION ALL
  SELECT 'OPT', '<非必填欄的Record>', '<非必填欄>' FROM DUAL
)
SELECT K.KIND || '=' || CASE WHEN BITAND(F.USEEDIT, 256) > 0 THEN 'Y' ELSE 'N' END AS RESULT
  FROM K JOIN <schema>.PSRECFIELDDB F ON F.RECNAME = K.REC AND F.FIELDNAME = K.FLD
 ORDER BY K.KIND;
```

用 App Designer 找一個勾了 Required 的欄位、一個沒勾的。結果 REQ=Y、OPT=N → 256＝Required。

### R4C 唯讀、隱藏的位元

```sql
WITH K AS (
  SELECT 'DO' AS KIND, '<頁面1>' AS PNL, '<Record1>' AS REC, '<欄位1>' AS FLD FROM DUAL UNION ALL
  SELECT 'INV', '<頁面2>', '<Record2>', '<欄位2>' FROM DUAL UNION ALL
  SELECT 'EDIT', '<頁面3>', '<Record3>', '<欄位3>' FROM DUAL
),
B AS (SELECT POWER(2, LEVEL - 1) AS BIT FROM DUAL CONNECT BY LEVEL <= 31)
SELECT K.KIND || ' ' || F.FIELDNUM || ' BITS=' ||
       NVL((SELECT LISTAGG(B.BIT, ',') WITHIN GROUP (ORDER BY B.BIT) FROM B
             WHERE BITAND(F.FIELDUSE, B.BIT) > 0), 'NONE') AS RESULT
  FROM K JOIN <schema>.PSPNLFIELD F
    ON F.PNLNAME = K.PNL AND F.RECNAME = K.REC AND F.FIELDNAME = K.FLD
 ORDER BY K.KIND, F.FIELDNUM;
```

用 App Designer 找勾了 Display Only、Invisible、都沒勾的欄位。結果：勾 Display Only 的三個欄位都是 BITS 1,16（三個剛好都是相關顯示，16＝Related Field）、Display Only＋Invisible 是 1,2、
都沒勾的 NONE → 1＝Display Only、2＝Invisible。

### R4D Component 允許的動作

```sql
SELECT LISTAGG(ACTIONS || ':' || CNT, ' ') WITHIN GROUP (ORDER BY CNT DESC, ACTIONS) AS RESULT
  FROM (SELECT ACTIONS, COUNT(*) AS CNT
          FROM <schema>.PSPNLGRPDEFN
         WHERE PNLGRPNAME LIKE 'TW\_%' ESCAPE '\'
         GROUP BY ACTIONS);
```

```sql
SELECT 'ACTIONS=' || ACTIONS AS RESULT
  FROM <schema>.PSPNLGRPDEFN
 WHERE PNLGRPNAME = '<Component名>';
```

結果：挑的客製 Component ACTIONS=2，App Designer 只勾 Update/Display → 2＝Update/Display；管理者確認四個動作依序是 1、2、4、8。

### R4E 唯讀帳號還缺哪些表

```sql
SELECT 'GRANT SELECT ON ' || UPPER('<schema>') || '.' || T.COLUMN_VALUE || ' TO ' || USER || ';' AS TODO
  FROM TABLE(SYS.ODCIVARCHAR2LIST(
       'PSSTATUS','PSPROJECTITEM','PSRECDEFN','PSRECFIELDDB','PSDBFIELD','PSDBFLDLABL','PSDBFLDLABLLANG',
       'PSXLATITEM','PSXLATITEMLANG','PSPNLDEFN','PSPNLFIELD','PSPNLGROUP','PSPNLGRPDEFN','PSMENUDEFN','PSMENUITEM',
       'PSSQLTEXTDEFN','PSPCMNAME','PSPRSMDEFN','PSPRSMDEFNLANG','PSPRSMSYSATTRVL','PSPRDMDEFN','PSOPTIONS',
       'PS_PRCSDEFN','PS_PRCSDEFNPNL','PS_PRCSJOBITEM','PSPRCSRQST','PS_PRCSRECUR',
       'PSAUTHITEM','PSROLECLASS','PSROLEUSER','PSAESECTDEFN','PSAESTEPDEFN')) T
 WHERE NOT EXISTS (SELECT 1 FROM ALL_OBJECTS O
                    WHERE O.OWNER = UPPER('<schema>') AND O.OBJECT_NAME = T.COLUMN_VALUE
                      AND O.OBJECT_TYPE IN ('TABLE', 'VIEW'));
```

沒有列＝32 張表都查得到；有列就把印出的 GRANT 用擁有者帳號執行。結果：沒有列。

### R5A 元件代碼 10、15、23、24（特徵＋App Designer）

```sql
WITH P AS (
  SELECT PNLNAME, FIELDNUM, FIELDTYPE, OCCURSLEVEL, RECNAME, FIELDNAME, LBLTEXT
    FROM <schema>.PSPNLFIELD
   WHERE PNLNAME LIKE 'TW\_%' ESCAPE '\'
     AND FIELDTYPE IN (10, 15, 19, 23, 24, 27)
),
F AS (
  SELECT P.*,
         CASE WHEN P.OCCURSLEVEL > 0 THEN 1 ELSE 0 END AS LVL1,
         CASE WHEN TRIM(P.RECNAME) IS NOT NULL THEN 1 ELSE 0 END AS HASREC,
         CASE WHEN TRIM(P.LBLTEXT) IS NOT NULL THEN 1 ELSE 0 END AS HASLBL,
         CASE WHEN EXISTS (SELECT 1 FROM <schema>.PSPNLFIELD G
                            WHERE G.PNLNAME = P.PNLNAME AND G.FIELDTYPE = 19 AND G.FIELDNUM < P.FIELDNUM
                              AND P.OCCURSLEVEL > 0 AND G.OCCURSLEVEL IN (P.OCCURSLEVEL, P.OCCURSLEVEL - 1))
              THEN 1 ELSE 0 END AS INGRID
    FROM P
)
SELECT 'CODE=' || FIELDTYPE || ' N=' || COUNT(*) || ' LVL=' || ROUND(100 * AVG(LVL1))
       || ' REC=' || ROUND(100 * AVG(HASREC)) || ' LBL=' || ROUND(100 * AVG(HASLBL))
       || ' GRID=' || ROUND(100 * AVG(INGRID)) AS RESULT,
       MIN(PNLNAME) KEEP (DENSE_RANK FIRST ORDER BY PNLNAME, FIELDNUM) AS SAMPLE_PAGE,
       MIN(FIELDNUM) KEEP (DENSE_RANK FIRST ORDER BY PNLNAME, FIELDNUM) AS SAMPLE_NUM,
       MIN(TRIM(LBLTEXT)) KEEP (DENSE_RANK FIRST ORDER BY PNLNAME, FIELDNUM) AS SAMPLE_LABEL
  FROM F
 GROUP BY FIELDTYPE
 ORDER BY FIELDTYPE;
```

LVL＝在層裡的比例、REC＝綁 Record、LBL＝有標籤、GRID＝前面有同層或上一層 Grid 的比例。SAMPLE_PAGE／SAMPLE_NUM 拿去 App Designer 的 Order 頁籤，
以 tab order 找那一列看元件。結果（CODE N LVL REC LBL GRID → App Designer）：

| 代碼 | 結果 | App Designer |
|---|---|---|
| 10 | 30 100 0 100 0 | Scroll Bar |
| 15 | 1 0 00 100 0（照回報） | 按鈕，Destination External Link；管理者另註有填 Record name |
| 19 | 587 100 100 24 16 | Grid（對照） |
| 23 | 59 31 2 0 0 | Horizontal Rule |
| 24 | 9 100 0 100 100 | Tab Separator |
| 27 | 588 100 0 54 2 | Scroll Area（對照） |

### R5B FIELDUSE 8、16 和相關顯示的對應

```sql
WITH P AS (
  SELECT PNLNAME, FIELDNUM, FIELDTYPE, FIELDUSE, ASSOCFIELDNUM
    FROM <schema>.PSPNLFIELD
   WHERE PNLNAME LIKE 'TW\_%' ESCAPE '\'
),
CTL AS (
  SELECT DISTINCT PNLNAME, ASSOCFIELDNUM AS FIELDNUM FROM P WHERE ASSOCFIELDNUM > 0
),
R AS (
  SELECT CASE WHEN P.ASSOCFIELDNUM > 0 THEN 1 ELSE 0 END AS IS_REL,
         CASE WHEN C.FIELDNUM IS NOT NULL THEN 1 ELSE 0 END AS IS_CTL,
         SIGN(BITAND(P.FIELDUSE, 8)) AS B8,
         SIGN(BITAND(P.FIELDUSE, 16)) AS B16
    FROM P
    LEFT JOIN CTL C ON C.PNLNAME = P.PNLNAME AND C.FIELDNUM = P.FIELDNUM
   WHERE P.FIELDTYPE IN (4, 5, 6, 7, 8)
)
SELECT 'CTL_N=' || SUM(IS_CTL) || ' B8_N=' || SUM(B8) || ' BOTH8=' || SUM(IS_CTL * B8)
       || ' REL_N=' || SUM(IS_REL) || ' B16_N=' || SUM(B16) || ' BOTH16=' || SUM(IS_REL * B16) AS RESULT
  FROM R;
```

CTL＝被相關顯示的 ASSOCFIELDNUM（當成 tab order）指到的欄位；REL＝ASSOCFIELDNUM 大於 0 的欄位。
結果：CTL_N 1105、B8_N 2044、BOTH8 84、REL_N 1984（B16_N、BOTH16 沒回）——控制欄只有 8% 帶 8，帶 8 的欄位數卻和相關顯示個數相近，
懷疑 ASSOCFIELDNUM 存的是控制欄的 Field ID，不是 tab order。

### R6 相關顯示存的是 tab order（H0）還是 Field ID（H3）（待跑）

```sql
WITH P AS (
  SELECT PNLNAME, FIELDNUM, TRIM(TO_CHAR(PNLFLDID)) AS FLDID, RECNAME, FIELDNAME, FIELDUSE, ASSOCFIELDNUM
    FROM <schema>.PSPNLFIELD
   WHERE PNLNAME LIKE 'TW\_%' ESCAPE '\'
),
D AS (
  SELECT R.RECNAME AS RREC, R.FIELDUSE AS RUSE,
         C0.FIELDNUM AS N0, C0.RECNAME AS REC0, C0.FIELDNAME AS FLD0, C0.FIELDUSE AS USE0,
         C3.FIELDNUM AS N3, C3.RECNAME AS REC3, C3.FIELDNAME AS FLD3, C3.FIELDUSE AS USE3
    FROM P R
    LEFT JOIN P C0 ON C0.PNLNAME = R.PNLNAME AND C0.FIELDNUM = R.ASSOCFIELDNUM
    LEFT JOIN P C3 ON C3.PNLNAME = R.PNLNAME AND C3.FLDID = TO_CHAR(R.ASSOCFIELDNUM)
   WHERE R.ASSOCFIELDNUM > 0
),
E AS (
  SELECT D.*,
         CASE WHEN TRIM(F0.EDITTABLE) IS NOT NULL THEN 1 ELSE 0 END AS P0,
         CASE WHEN TRIM(F0.EDITTABLE) = TRIM(D.RREC) THEN 1 ELSE 0 END AS R0,
         CASE WHEN TRIM(F3.EDITTABLE) IS NOT NULL THEN 1 ELSE 0 END AS P3,
         CASE WHEN TRIM(F3.EDITTABLE) = TRIM(D.RREC) THEN 1 ELSE 0 END AS R3
    FROM D
    LEFT JOIN <schema>.PSRECFIELDDB F0 ON F0.RECNAME = D.REC0 AND F0.FIELDNAME = D.FLD0
    LEFT JOIN <schema>.PSRECFIELDDB F3 ON F3.RECNAME = D.REC3 AND F3.FIELDNAME = D.FLD3
),
A AS (
  SELECT COUNT(*) AS N, SUM(CASE WHEN N0 = N3 THEN 1 ELSE 0 END) AS SAME,
         COUNT(N0) AS N0, SUM(P0) AS P0, SUM(R0) AS R0, SUM(SIGN(BITAND(NVL(USE0, 0), 8))) AS B80,
         COUNT(N3) AS N3, SUM(P3) AS P3, SUM(R3) AS R3, SUM(SIGN(BITAND(NVL(USE3, 0), 8))) AS B83,
         SUM(SIGN(BITAND(RUSE, 16))) AS B16
    FROM E
),
U AS (
  SELECT (SELECT COUNT(*) FROM P WHERE BITAND(FIELDUSE, 16) > 0) AS B16ALL,
         (SELECT COUNT(*) FROM (SELECT PNLNAME, FLDID FROM P GROUP BY PNLNAME, FLDID HAVING COUNT(*) > 1)) AS DUPID
    FROM DUAL
)
SELECT 'N=' || A.N || ' SAME=' || A.SAME
       || ' H0=' || A.N0 || ',' || A.P0 || ',' || A.R0 || ',' || A.B80
       || ' H3=' || A.N3 || ',' || A.P3 || ',' || A.R3 || ',' || A.B83
       || ' B16=' || A.B16 || ',' || U.B16ALL || ' DUPID=' || U.DUPID AS RESULT
  FROM A CROSS JOIN U;
```

H0、H3 後面各四個數：找到的控制欄數、有 prompt 的、prompt 表＝相關顯示 Record 的、帶 8 的。SAME＝兩種方式找到同一欄的個數；
B16＝相關顯示裡帶 16 的個數、所有帶 16 的欄位數；DUPID＝同一頁 Field ID 重複的組數（應為 0）。
H3 的數明顯比 H0 大、第四個接近第一個 → 存的是 Field ID、8＝Display Control；反過來 → 維持 tab order、8 不是 Display Control。

可選（App Designer 對照）：找一個相關顯示欄位，在 Order 頁籤看它的控制欄的 tab order 與 Field ID（兩個數字不同時），跑：

```sql
SELECT 'ASSOC=' || ASSOCFIELDNUM AS RESULT
  FROM <schema>.PSPNLFIELD
 WHERE PNLNAME = '<頁面>' AND RECNAME = '<相關顯示的 Record>' AND FIELDNAME = '<相關顯示的欄位>';
```

ASSOC 等於 tab order → H0；等於 Field ID → H3。

---

## 4. 還沒定案

- **相關顯示的對應（R6）**：§2l 的 RELATED_TO 現在直接輸出 ASSOCFIELDNUM、DC 以「別人的 ASSOCFIELDNUM＝本列 FIELDNUM」判斷。R6 若證實存的是
  Field ID，兩者都要改成以 PNLFLDID 對應（DC 可能改用 FIELDUSE 8）。調過 tab order 的頁面在改之前可能指錯欄。
- **15 External Link 的網址**：網址來源不在 §2l 查的欄位裡，沒查。
- **權限表的動作（PSAUTHITEM.AUTHORIZEDACTIONS）**：和 ACTIONS 同一組位元，但 128 的意思各家說法不一，還沒解碼。
- **搜尋 Record 的搜尋鍵與清單欄位**：§2m 只給 Record 名。

---

## 5. 來源

Oracle 官方：

- [QueryDBRecordField Class Properties（PeopleTools 8.61）](https://docs.oracle.com/cd/G36972_01/pt861pbr5/eng/pt/tpcr/QueryDBRecordFieldClassProperties-c07cc1.html)——USEEDIT 位元
- [Creating Display Control and Related Fields（PeopleTools 8.58）](https://docs.oracle.com/cd/F44947_01/pt858pbr3/eng/pt/tapd/task_CreatingDisplayControlandRelatedFields-077500.html)——相關顯示機制
- [PeopleTools 8.50 Application Designer（鏡像）](https://www.zutshigroup.com/PSOL/pt850/eng/psbooks/tapd/htm/tapd14.htm)——勾 Related Field 會自動勾 Display Only

社群整理（非官方）：

- FIELDTYPE：[psoft4u](http://psoft4u.blogspot.com/2009/05/fieldtype-in-pspnlfield.html)、[PSST0101](https://psst0101.digitaleagle.net/2008/12/03/pspnldefnfieldtype/)
- FIELDUSE：[peoplesoftsqr.com](http://peoplesoftsqr.com/from-database-table-to-peoplesoft-page/)
- USEEDIT：[David Kurtz, USEEDIT values](https://www2.go-faster.co.uk/static/useedit.htm)
- ACTIONS／AUTHORIZEDACTIONS：[peoplesofttutorial.com](https://peoplesofttutorial.com/authorized-actions-in-psauthitem/)、[PeopleSoft DBA](https://peoplesoftdba.wordpress.com/2012/07/17/authorized-action-codes-in-psauthitem/)、
  [ctcLink Page Action Basics](https://cptc.teamdynamix.com/TDClient/222/Portal/KB/ArticleDet?ID=4395)
