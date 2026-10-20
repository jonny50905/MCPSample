# 畫面元件 metadata 驗證 SQL（第五輪：和官方對照有出入的代碼）

> 接第四輪（`ui-metadata-check-r4.md`）。R4A～R4D 已和 Oracle 文件、社群整理的代碼表對過（對照表在本文後段）：USEEDIT、FIELDUSE 1／2／16、
> ACTIONS、框架已解碼的元件代碼都一致；Component 動作已進框架（cookbook §2m，L152）。對不上或還判不了的只剩兩件：
> 元件代碼 10、15、23、24（社群：Scroll Bar、External Link 按鈕、Horizontal Rule、Tab Separator；第三輪依特徵判成 MIXED／CONTAINER），
> 以及 FIELDUSE 8（社群：Display Control；第三輪 DC=NONE）。本輪兩句 SQL，都只看客製頁面（`TW_` 開頭，走索引）。
> 表名一律 `<schema>.表名`：執行前用編輯器把 `<schema>` 全部取代成擁有者名稱（不加引號），用 agent 的唯讀帳號跑。

## R5A 元件代碼 10、15、23、24（特徵＋App Designer 對照）

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

做法：19（Grid）、27（Scroll Area）一起列出來當對照。LVL＝在 scroll／grid 層裡（OCCURSLEVEL 大於 0）的比例、REC＝綁 Record 欄位的比例、
LBL＝有標籤文字的比例、GRID＝在層裡、而且同一頁前面有同層或上一層的 Grid 的比例。社群說法若成立：24（Grid 裡的 Tab Separator）GRID、LVL 都接近 100；
10（Scroll Bar，舊式的層級捲軸）LVL 接近 100；23（Horizontal Rule，裝飾線）REC 接近 0；15 只有 1 筆，看 App Designer。

怎麼看：

1. RESULT 欄每列照抄（只有代碼與比例）。
2. SAMPLE_PAGE／SAMPLE_NUM／SAMPLE_LABEL 只給你自己看、**不用回報**：在 App Designer 開 SAMPLE_PAGE，Order 頁籤找 Num＝SAMPLE_NUM 那一列
   （對不上就用 SAMPLE_LABEL 找），看它是什麼元件；按鈕／超連結再開屬性看 Destination。
3. 在 10、15、23、24 那四列後面加 `AD=…`：和社群說法一樣（10 Scroll Bar、15 Push Button/Hyperlink 的 Destination 是 External Link、
   23 Horizontal Rule、24 Tab Separator）寫 `AD=Y`；不一樣寫 App Designer 顯示的名稱。

## R5B FIELDUSE 8、16 和相關顯示的對應

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

做法：控制欄（CTL）＝被某個相關顯示的 ASSOCFIELDNUM 指到的欄位；相關顯示（REL）＝ASSOCFIELDNUM 大於 0 的欄位（R4A 的 H0）。
B8_N／B16_N＝FIELDUSE 帶 8／16 的欄位數；BOTH8＝控制欄裡帶 8 的、BOTH16＝相關顯示裡帶 16 的。

怎麼看：整行照抄。

- BOTH8 接近 CTL_N、也接近 B8_N → 8＝Display Control（和社群一致；第三輪 DC=NONE 是門檻設太嚴）。BOTH8 遠小於 CTL_N → 8 在這個環境不是 Display Control，
  框架維持用 ASSOCFIELDNUM 反查控制欄（cookbook §2l 現在的算法）。
- BOTH16 接近 REL_N、也接近 B16_N → 16＝Related Field，和 ASSOCFIELDNUM 大於 0 是同一件事（框架兩種都能用）。

## 和官方對照（R4A～R4D 與框架用到的代碼）

| 項目 | 框架的解碼（依公司環境驗證） | Oracle 文件／社群整理 | 結論 |
|---|---|---|---|
| USEEDIT（R4B、第一輪 V5） | 1 Key、256 Required、512 Translate、4096 Reasonable Date、8192 Y/N、16384 Prompt Table Edit、32768 Auto-Update | Oracle PeopleCode API（QueryDBRecordField 的 Flag）：1 Key、2048 Search Item、32768 Auto Update；256 Required、512 Translate、4096 Date Range Edit、8192 Yes/No Table Edit、16384 Edit Table | 一致（4096 Oracle 叫 Date Range Edit，App Designer 欄位屬性叫 Reasonable Date Test，同一個設定） |
| FIELDUSE（R4C） | 1 Display Only、2 Invisible；相關顯示改用 ASSOCFIELDNUM | 社群：1 Display Only、2 Invisible、8 Display Control、16 Related Field、1024 Show Label；Oracle：勾 Related Field 會自動勾 Display Only | 1、2、16 一致（R4C 的相關顯示是 1,16）；8 和第三輪 DC=NONE 對不上 → R5B |
| ASSOCFIELDNUM（R4A） | 相關顯示 → 控制欄的 FIELDNUM（H0） | Oracle：相關顯示要指定一個 Display Control 欄位；欄位層的存法沒有官方文件 | 機制一致；R5B 用 8 位元再交叉驗一次 |
| ACTIONS（R4D） | 1 Add、2 Update/Display、4 Update/Display All、8 Correction（管理者確認順序） | 社群（PSAUTHITEM.AUTHORIZEDACTIONS，同一組位元）：1 Add、2 Update/Display、4 Update/Display All、8 Correction；128 各家說法不一（Data Entry 或「沒選」） | 一致 → 已進框架（§2m）；其他位元照數字寫、不猜 |
| FIELDTYPE（已解碼的） | 4 Edit Box、5 Drop-Down List Box、6 Long Edit Box、7 Check Box、8 Radio Button、9 Image、11 Subpage、12／16／21 按鈕、18 Secondary Page、19 Grid、25 HTML Area、27 Scroll Area | 社群：同；12／16／21 依按鈕的 Destination 分別是 PeopleCode Command、Internal Link、Secondary Page | 一致；元件名稱改成 App Designer 的叫法 |
| FIELDTYPE 10、15、23、24 | 未解碼（OTHER） | 社群：10 Scroll Bar、15 External Link（按鈕）、23 Horizontal Rule、24 Tab Separator | 第三輪特徵判不出 → R5A |

來源（Oracle 官方）：

- [QueryDBRecordField Class Properties（PeopleTools 8.61）](https://docs.oracle.com/cd/G36972_01/pt861pbr5/eng/pt/tpcr/QueryDBRecordFieldClassProperties-c07cc1.html)
- [Creating Display Control and Related Fields（PeopleTools 8.58）](https://docs.oracle.com/cd/F44947_01/pt858pbr3/eng/pt/tapd/task_CreatingDisplayControlandRelatedFields-077500.html)

來源（社群整理，非官方）：

- FIELDTYPE：[psoft4u](http://psoft4u.blogspot.com/2009/05/fieldtype-in-pspnlfield.html)、[PSST0101](https://psst0101.digitaleagle.net/2008/12/03/pspnldefnfieldtype/)
- FIELDUSE：[peoplesoftsqr.com](http://peoplesoftsqr.com/from-database-table-to-peoplesoft-page/)；勾 Related Field 自動勾 Display Only：[PeopleTools 8.50 Application Designer（鏡像）](https://www.zutshigroup.com/PSOL/pt850/eng/psbooks/tapd/htm/tapd14.htm)
- USEEDIT：[David Kurtz, USEEDIT values](https://www2.go-faster.co.uk/static/useedit.htm)
- ACTIONS／AUTHORIZEDACTIONS：[peoplesofttutorial.com](https://peoplesofttutorial.com/authorized-actions-in-psauthitem/)、[PeopleSoft DBA](https://peoplesoftdba.wordpress.com/2012/07/17/authorized-action-codes-in-psauthitem/)；
  四個動作的意思：[ctcLink Page Action Basics](https://cptc.teamdynamix.com/TDClient/222/Portal/KB/ArticleDet?ID=4395)

## 回報範本

```
R5A 10=…（RESULT 整行）AD=__；15=… AD=__；23=… AD=__；24=… AD=__；19、27 兩行照抄
R5B ___（整行）
```
