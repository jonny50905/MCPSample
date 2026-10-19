# 畫面元件 metadata 驗證 SQL（第四輪）

> 接第三輪（`ui-metadata-check-r3.md`）。第三輪結果：12、16、18、21、25、27 依特徵成立；10、23 混用，15、24 是容器；
> FIELDUSE 16 是唯讀位元的候選；ASSOCFIELDNUM 指到的欄只有 8% 有 prompt（對應方式待查）；鍵欄位不會自動帶 256。
> 唯讀帳號 A 測試 FAIL：唯讀帳號只查得到「擁有者.表名」。**本輪起每個表名都寫 `<schema>.表名`**——執行前用編輯器把 `<schema>`
> 全部取代成擁有者名稱（不加引號），用 agent 的唯讀帳號跑。框架的查詢手冊同步改成這個寫法（L150、SOP-30）。

## R4A 相關顯示指到哪一欄（自己算）

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

做法：相關顯示（DESCR 那種）的控制欄通常有 prompt，而且相關顯示的 Record 就是那個 prompt 表。H0＝ASSOCFIELDNUM 就是控制欄的 FIELDNUM、
H1／H2＝差一號、NB＝相關顯示的前一個欄位、ALL＝客製頁面全部 Edit Box（對照用）。P＝指到的欄有 prompt 的比例、R＝prompt 表就是相關顯示的 Record 的比例。

怎麼看：整行照抄。P 和 R 都明顯最高的那一組就是對的對應方式；每組都低，代表 ASSOCFIELDNUM 不是相關顯示的連結。

## R4B 256 是不是「必填」（拿已知欄位核對）

先在 App Designer 打開一個客製 Record，找一個勾了 Required 的欄位、一個沒勾的欄位，把名稱填進去：

```sql
WITH K AS (
  SELECT 'REQ' AS KIND, '<必填欄的Record>' AS REC, '<必填欄>' AS FLD FROM DUAL UNION ALL
  SELECT 'OPT', '<非必填欄的Record>', '<非必填欄>' FROM DUAL
)
SELECT K.KIND || '=' || CASE WHEN BITAND(F.USEEDIT, 256) > 0 THEN 'Y' ELSE 'N' END AS RESULT
  FROM K JOIN <schema>.PSRECFIELDDB F ON F.RECNAME = K.REC AND F.FIELDNAME = K.FLD
 ORDER BY K.KIND;
```

怎麼看：回兩列，照抄（預期 `REQ=Y`、`OPT=N`）。少一列＝那個名稱打錯。

## R4C 唯讀、隱藏的位元（拿已知頁面欄位核對）

在 App Designer 打開一個客製頁面，從欄位屬性的 Use 頁籤找三個：勾了 Display Only 的、勾了 Invisible 的、兩個都沒勾的（可以在同一頁），填進去：

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

怎麼看：每列是「種類 欄位序號 BITS=…」，只抄種類和 BITS（同一欄位在頁面上出現兩次會有兩列，都抄）。

## R4D Component 允許的動作（Add、Update/Display…）

```sql
SELECT LISTAGG(ACTIONS || ':' || CNT, ' ') WITHIN GROUP (ORDER BY CNT DESC, ACTIONS) AS RESULT
  FROM (SELECT ACTIONS, COUNT(*) AS CNT
          FROM <schema>.PSPNLGRPDEFN
         WHERE PNLGRPNAME LIKE 'TW\_%' ESCAPE '\'
         GROUP BY ACTIONS);
```

再挑一個客製 Component，在 App Designer 看 Component Properties → Use 的 Actions 勾了哪些：

```sql
SELECT 'ACTIONS=' || ACTIONS AS RESULT
  FROM <schema>.PSPNLGRPDEFN
 WHERE PNLGRPNAME = '<Component名>';
```

怎麼看：第一句整行照抄（`值:個數`）；第二句抄 ACTIONS 的數字，再寫勾了哪幾個（Add／Update/Display／Update/Display All／Correction）。

## R4E 唯讀帳號還缺哪些表（用唯讀帳號跑）

agent 會用到的 32 張 PeopleTools 表，唯讀帳號看不到的會直接印出授權指令：

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

怎麼看：沒有列＝都查得到。有列＝把印出來的 GRANT 用**擁有者帳號**執行（報 ORA-00942＝本環境沒有這張表，略過）。
不補的話，用到那張表的查法（導覽入口、授權、排程）agent 會記 gaps。業務資料表（`PS_<RECNAME>`，選項分布與欄位使用剖析用）不在清單裡，沒權限的那張同樣記 gaps。

## 搬完新版之後（agent 端對端）

搬運包解開後，profile `oracle.currentSchema` 確認是擁有者名稱，問 agent 一題要查選項的問題（任挑一個有下拉選項的欄位）。
通＝答得出選項、沒有「currentSchema 未回填」或「查不到表」；不通＝把 agent 回的那句錯誤類型（例：ORA-00942、ORA-02421）告訴我，不用貼 SQL。
OpenCode 版也可以跑 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tests\test-oracle-runtime.ps1 -Scenario B1 -Runs 3`，結束碼 0＝通（SOP-30 第 7 步）。

## 回報範本

```text
R4A ___（整行）
R4B REQ=_ OPT=_
R4C DO BITS=___  INV BITS=___  EDIT BITS=___
R4D ___（整行）；ACTIONS=__，勾了 ___
R4E 沒有列／__ 列（已補）
端對端 通／不通（錯誤類型 ___）
```
