# 畫面元件 metadata 驗證 SQL（第六輪：相關顯示指到的是 tab order 還是 Field ID）

> 接第五輪（`ui-metadata-check-r5.md`）。R5A：10 Scroll Bar、15 External Link 按鈕、23 Horizontal Rule、24 Tab Separator 都和 App Designer 一致，
> 已進框架（cookbook §2l，L153）。R5B＝CTL_N 1105、B8_N 2044、BOTH8 84、REL_N 1984：用「ASSOCFIELDNUM＝控制欄的 tab order（FIELDNUM）」
> 找到的控制欄只有 8% 帶 8，帶 8 的欄位也只有 4% 是這樣找到的控制欄；可是帶 8 的欄位數（2044）和相關顯示的個數（1984）差不多。
> 兩種可能：(1) 8 在這個環境不是 Display Control；(2) ASSOCFIELDNUM 存的是控制欄的 Field ID（PNLFLDID：欄位放上頁面時給的編號，
> 調 tab order 不會變），不是 tab order——沒調過順序的頁面兩者相同，所以第四輪的 H0 看起來部分成立。本輪一句 SQL 同時比兩種對應。
> 表名一律 `<schema>.表名`：執行前取代成擁有者名稱（不加引號），用 agent 的唯讀帳號跑；只看客製頁面。

## R6 相關顯示的控制欄：tab order（H0）還是 Field ID（H3）

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

做法：每個相關顯示（ASSOCFIELDNUM 大於 0）各用兩種方式找控制欄——H0：tab order（FIELDNUM）等於 ASSOCFIELDNUM；H3：Field ID（PNLFLDID）
等於 ASSOCFIELDNUM。H0、H3 後面各四個數：找到的控制欄個數、其中有 prompt 的、prompt 表就是相關顯示 Record 的、FIELDUSE 帶 8 的。
SAME＝兩種方式找到同一欄的個數；B16＝相關顯示裡帶 16 的個數、所有帶 16 的欄位數；DUPID＝同一頁 Field ID 重複的組數（應為 0）。

怎麼看：整行照抄。

- H3 的四個數明顯比 H0 大，而且第四個（帶 8）接近第一個 → ASSOCFIELDNUM 存的是控制欄的 Field ID，8＝Display Control（和社群一致）。
  框架的相關顯示改成用 Field ID 對應。
- H3 的數比 H0 小或差不多 → 維持 tab order 的對應；8 在這個環境不是 Display Control。
- B16 的兩個數都接近 N → 16＝Related Field，和 ASSOCFIELDNUM 大於 0 是同一件事。

R6B（可選，App Designer 對照，R6 判不出來時再做）：找一個相關顯示欄位（Use 頁籤勾了 Related Field），記下它的 Related Control Field 是哪一欄；
在 Order 頁籤看那個控制欄的 tab order 和 Field ID，兩個數字不一樣的話跑下面這句，把 ASSOC 和那兩個數字一起回報：

```sql
SELECT 'ASSOC=' || ASSOCFIELDNUM AS RESULT
  FROM <schema>.PSPNLFIELD
 WHERE PNLNAME = '<頁面>' AND RECNAME = '<相關顯示的 Record>' AND FIELDNAME = '<相關顯示的欄位>';
```

## 回報範本

```
R6 ___（整行）
（可選）R6B ASSOC=__，控制欄 tab order=__、Field ID=__
```
