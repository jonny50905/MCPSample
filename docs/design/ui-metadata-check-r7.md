# 畫面元件 metadata 驗證 SQL（第七輪：ASSOCFIELDNUM 是不是從 0 起算）

> 接第六輪（`ui-metadata-check-r6.md`）。R6＝N 1984、SAME 1005、H0 1984,149,8,97、H3 1697,236,30,339、B16 1984,2177、DUPID 0：
> 用 tab order（H0）或 Field ID（H3）找到的「控制欄」，有 Prompt 的比例都只在一般 Edit Box 的水準（H0 7.5%、H3 13.9%；一般 Edit Box 14%），
> 帶 8 的也很少——**兩種對應都不對**。另外，帶 Related Field（16）的欄位比 ASSOCFIELDNUM 大於 0 的多（2177 對 1984）：
> 有一批相關顯示的 ASSOCFIELDNUM 是 0。
> 新假設：ASSOCFIELDNUM 從 0 起算——控制欄的 tab order＝ASSOCFIELDNUM＋1，所以指到第 1 個欄位的相關顯示存的是 0（前幾輪用「大於 0」挑相關顯示，
> 把它們漏掉了）。第四輪 R4A 回報的「H0 P=54 R=22」和這次 R6 的 H0 對不上，比較像是 H1（＋1）那一行。
> 本輪改用 Related Field（16）挑相關顯示，比兩種「＋1」的對應。表名一律 `<schema>.表名`，用唯讀帳號跑；只看客製頁面。

## R7 控制欄的 tab order 是不是 ASSOCFIELDNUM＋1

```sql
WITH P AS (
  SELECT PNLNAME, FIELDNUM, TRIM(TO_CHAR(PNLFLDID)) AS FLDID, RECNAME, FIELDNAME, FIELDUSE, ASSOCFIELDNUM
    FROM <schema>.PSPNLFIELD
   WHERE PNLNAME LIKE 'TW\_%' ESCAPE '\'
),
D AS (
  SELECT R.RECNAME AS RREC, R.ASSOCFIELDNUM AS ASSOC,
         C1.FIELDNUM AS N1, C1.RECNAME AS REC1, C1.FIELDNAME AS FLD1, C1.FIELDUSE AS USE1,
         C4.FIELDNUM AS N4, C4.RECNAME AS REC4, C4.FIELDNAME AS FLD4, C4.FIELDUSE AS USE4
    FROM P R
    LEFT JOIN P C1 ON C1.PNLNAME = R.PNLNAME AND C1.FIELDNUM = R.ASSOCFIELDNUM + 1
    LEFT JOIN P C4 ON C4.PNLNAME = R.PNLNAME AND C4.FLDID = TO_CHAR(R.ASSOCFIELDNUM + 1)
   WHERE BITAND(R.FIELDUSE, 16) > 0
),
E AS (
  SELECT D.*,
         CASE WHEN TRIM(F1.EDITTABLE) IS NOT NULL THEN 1 ELSE 0 END AS P1,
         CASE WHEN TRIM(F1.EDITTABLE) = TRIM(D.RREC) THEN 1 ELSE 0 END AS R1,
         CASE WHEN TRIM(F4.EDITTABLE) IS NOT NULL THEN 1 ELSE 0 END AS P4,
         CASE WHEN TRIM(F4.EDITTABLE) = TRIM(D.RREC) THEN 1 ELSE 0 END AS R4
    FROM D
    LEFT JOIN <schema>.PSRECFIELDDB F1 ON F1.RECNAME = D.REC1 AND F1.FIELDNAME = D.FLD1
    LEFT JOIN <schema>.PSRECFIELDDB F4 ON F4.RECNAME = D.REC4 AND F4.FIELDNAME = D.FLD4
)
SELECT 'N=' || COUNT(*) || ' A0=' || SUM(CASE WHEN ASSOC = 0 THEN 1 ELSE 0 END)
       || ' H1=' || COUNT(N1) || ',' || SUM(P1) || ',' || SUM(R1) || ',' || SUM(SIGN(BITAND(NVL(USE1, 0), 8)))
       || ' H4=' || COUNT(N4) || ',' || SUM(P4) || ',' || SUM(R4) || ',' || SUM(SIGN(BITAND(NVL(USE4, 0), 8))) AS RESULT
  FROM E;
```

做法：相關顯示改用 FIELDUSE 帶 16 挑（含 ASSOCFIELDNUM 是 0 的）。H1＝控制欄的 tab order 是 ASSOCFIELDNUM＋1；H4＝控制欄的 Field ID 是 ASSOCFIELDNUM＋1。
H1、H4 後面各四個數，和 R6 一樣：找到的控制欄數、其中有 Prompt 的、Prompt 表＝相關顯示 Record 的、帶 8 的。A0＝ASSOCFIELDNUM 是 0 的相關顯示數。

怎麼看：整行照抄。哪一組的四個數明顯高（尤其第二個遠高於一般欄位的 14%、第四個接近第一個），那組就是對的對應，8 也同時確認是 Display Control。
兩組都不高 → ASSOCFIELDNUM 不是用這兩種方式指控制欄，改用 R7B 直接看。

## R7B（可選，最直接）App Designer 對一個例子

在 App Designer 打開一個有相關顯示的客製頁面（例如代碼欄旁邊顯示名稱的欄位，Use 頁籤勾了 Related Field），在 Order 頁籤記下它的**控制欄**的 tab order，
再跑（填那個相關顯示的頁面、Record、欄位）：

```sql
SELECT 'ASSOC=' || ASSOCFIELDNUM AS RESULT
  FROM <schema>.PSPNLFIELD
 WHERE PNLNAME = '<頁面>' AND RECNAME = '<相關顯示的 Record>' AND FIELDNAME = '<相關顯示的欄位>';
```

ASSOC＝控制欄的 tab order 減 1 → 從 0 起算（H1）成立。回報 ASSOC 與控制欄的 tab order 兩個數字就好（頁面、欄位名不用回報）。

## R7K 改用「鍵」與「帶 8」比各種對應（交給公司機的 Claude 跑）

判斷依據：真正的控制欄，欄位名通常是相關顯示那張 Record 的鍵（例如部門代碼是部門表的鍵），而且控制欄應該帶 8。NB（相關顯示的前一欄）當對照。

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

怎麼看：每種對應一列：N、KEY_PCT（控制欄是相關顯示 Record 的鍵的比例）、B8_PCT（控制欄帶 8 的比例）。兩個比例都明顯最高的就是對的。
公司機的 Claude 另外抽查幾個相關顯示（含 ASSOCFIELDNUM 是 0 的、tab order 與 Field ID 不一致的頁面），把整頁欄位列出來以語意判斷真正的控制欄。

## 結果（2026-10-21）

公司機的 Claude 跑 R7K 並抽查後回報：**H1 成立——控制欄 FIELDNUM＝ASSOCFIELDNUM＋1；FIELDUSE 位元 8＝Display Control。**
→ 查詢手冊 §2l 改成以 FIELDUSE 16 判斷相關顯示、RELATED_TO＝ASSOCFIELDNUM＋1、DISPLAY_CONTROL 看 FIELDUSE 8（L157）。

## 回報範本

```
R7 ___（整行）
（可選）R7B ASSOC=__，控制欄 tab order=__
```
