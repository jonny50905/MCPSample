# 畫面元件 metadata 驗證 SQL（第二輪）

> 接第一輪（`ui-metadata-check-r1.md`；結果記在 `ui-control-lookup-dependency-memo.md` §7.1）。第一輪已確認欄位型別、Record 型別、
> Record 欄位 edit 位元（必填等少數待驗）、元件代碼 0～9 與 11（含 Group Box）。這一輪核對其餘元件代碼，並探查第三輪要用的欄位。
> 只讀 PeopleTools 定義表；回報只有代碼、Y/N 與 PeopleTools 的元件類型名稱，不含公司物件名。先做第一輪的 V0（設 schema）。

## R2A Page 欄位探查（一串 Y/N）

```sql
SELECT (SELECT LISTAGG(CASE WHEN A.COLUMN_NAME IS NULL THEN 'N' ELSE 'Y' END) WITHIN GROUP (ORDER BY C.SEQ)
          FROM (SELECT 1 AS SEQ, 'DSPLCNTRLFLD' AS CNAME FROM DUAL UNION ALL
                SELECT 2, 'ASSOCFIELDNUM' FROM DUAL UNION ALL
                SELECT 3, 'GOTOPORTALNAME' FROM DUAL UNION ALL
                SELECT 4, 'GOTONODENAME' FROM DUAL UNION ALL
                SELECT 5, 'GOTOMENUNAME' FROM DUAL UNION ALL
                SELECT 6, 'GOTOPNLGRPNAME' FROM DUAL UNION ALL
                SELECT 7, 'GOTOMKTNAME' FROM DUAL UNION ALL
                SELECT 8, 'GOTOPNLNAME' FROM DUAL UNION ALL
                SELECT 9, 'GOTOPNLACTION' FROM DUAL UNION ALL
                SELECT 10, 'POPUPNAME' FROM DUAL) C
          LEFT JOIN (SELECT DISTINCT COLUMN_NAME FROM ALL_TAB_COLUMNS WHERE TABLE_NAME = 'PSPNLFIELD') A
            ON A.COLUMN_NAME = C.CNAME) AS YN,
       (SELECT COUNT(DISTINCT COLUMN_NAME) FROM ALL_TAB_COLUMNS
         WHERE TABLE_NAME = 'PSPNLFIELD'
           AND (COLUMN_NAME LIKE 'GOTO%' OR COLUMN_NAME LIKE '%DSPL%' OR COLUMN_NAME LIKE '%CNTRL%'
                OR COLUMN_NAME LIKE '%ASSOC%' OR COLUMN_NAME LIKE '%POPUP%')
           AND COLUMN_NAME NOT IN ('DSPLCNTRLFLD', 'ASSOCFIELDNUM', 'GOTOPORTALNAME', 'GOTONODENAME', 'GOTOMENUNAME',
                                   'GOTOPNLGRPNAME', 'GOTOMKTNAME', 'GOTOPNLNAME', 'GOTOPNLACTION', 'POPUPNAME')) AS EXTRA
  FROM DUAL;
```

怎麼看：YN 是 10 個 Y／N（照順序：1 DSPLCNTRLFLD、2 ASSOCFIELDNUM、3～9 GOTOPORTALNAME／GOTONODENAME／GOTOMENUNAME／
GOTOPNLGRPNAME／GOTOMKTNAME／GOTOPNLNAME／GOTOPNLACTION、10 POPUPNAME）；EXTRA 是同類樣式但不在這 10 個裡的欄位數。照抄兩個值。

## R2B 找一個拿來核對的客製頁面

```sql
SELECT PNLNAME, LISTAGG(FIELDTYPE, ',') WITHIN GROUP (ORDER BY FIELDTYPE) AS CODES
  FROM (SELECT DISTINCT PNLNAME, FIELDTYPE FROM PSPNLFIELD
         WHERE PNLNAME LIKE 'TW\_%' ESCAPE '\'
           AND FIELDTYPE IN (10, 12, 15, 16, 18, 19, 21, 23, 24, 25, 27))
 GROUP BY PNLNAME
 ORDER BY COUNT(*) DESC, PNLNAME
 FETCH FIRST 5 ROWS ONLY;
```

怎麼看：列出包含最多「待核對代碼」的 5 個客製頁面。挑一個你能在 Application Designer（或 PIA）打開的頁面，頁名不用回報；
回報你挑的那一列的 CODES（只有數字）。

## R2C 這個頁面上的待核對元件

```sql
SELECT FIELDNUM, FIELDTYPE,
       CASE FIELDTYPE WHEN 10 THEN 'SCROLL_BAR?' WHEN 12 THEN 'PUSH_BUTTON?' WHEN 15 THEN 'BUTTON_OR_LINK?'
                      WHEN 16 THEN 'BUTTON_OR_LINK?' WHEN 18 THEN 'SECONDARY_PAGE?' WHEN 19 THEN 'GRID?'
                      WHEN 21 THEN 'BUTTON_TO_SECONDARY_PAGE?' WHEN 23 THEN 'LAYOUT?' WHEN 24 THEN 'LAYOUT?'
                      WHEN 25 THEN 'HTML_AREA?' WHEN 27 THEN 'SCROLL_AREA?' END AS GUESS,
       RECNAME, FIELDNAME, LBLTEXT, OCCURSLEVEL
  FROM PSPNLFIELD
 WHERE PNLNAME = 'PAGE_NAME_HERE'
   AND FIELDTYPE IN (10, 12, 15, 16, 18, 19, 21, 23, 24, 25, 27)
 ORDER BY FIELDNUM;
```

把 `PAGE_NAME_HERE` 換成 R2B 挑的頁名。GUESS 是我依第一輪旗標推的類型（帶問號＝待確認）。

怎麼看：在 Application Designer 打開同一個頁面，Order 頁籤的 Type 欄就是每個元件的類型（用 Num、Label 或 Record／Field 對到 FIELDNUM）；
沒有 Application Designer 就在 PIA 看（按鈕、超連結、表格、可捲動區塊、HTML 內容）。按鈕要另看它按下去做什麼（跑程式、開彈出頁、轉到別的畫面、外部網址）。
回報「代碼＝類型」，例如 `12=Push Button（跑 PeopleCode）、19=Grid、25=HTML Area`；同一代碼有兩種類型就都寫。

## 回報範本

```text
R2A YN=__________ EXTRA=__
R2B 挑的頁面 CODES=________
R2C 代碼=類型：__________
```

## 下一輪

依 R2A：唯讀、隱藏、必填存在哪個位元（相關顯示欄位一定唯讀，有 DSPLCNTRLFLD 就能自動算）、按鈕目標存在哪些欄位、Component 的可用模式。
