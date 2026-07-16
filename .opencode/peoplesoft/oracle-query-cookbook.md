# Oracle Query Cookbook（oracleMCP 查詢樣板）

`oracleMCP` 是通用 Oracle 查詢 MCP，連 PeopleSoft 資料庫。
本手冊提供各**協定角色**對應的 PeopleTools metadata 查詢樣板——
需要查 metadata 時**照抄樣板帶入參數**，不要自己發明 SQL。

## 使用規則（硬性）

```text
1. 只允許 SELECT。禁止 INSERT / UPDATE / DELETE / MERGE / DDL / PL/SQL 匿名區塊。
2. 每個查詢都要有列數上限：加 FETCH FIRST 200 ROWS ONLY（或 ROWNUM <= 200）。
3. 可能高基數的查詢（值清單、使用者清單）先跑 COUNT(*)，超過 200 只回彙總。
4. 使用者層級資料只回彙總（COUNT / 角色名），不列具名清單（遮罩原則）。
5. 查詢結果屬 metadata evidence：報告引用時附上「用的 SQL + 關鍵列」。
6. 下列表名 / 欄位為 PeopleTools 8.5x 常見結構；實際環境第一次使用前
   先驗證（查不到表 / 欄位時記入 gaps，不要瞎改表名硬湊）。
7. oracleMCP 的實際工具名（query / execute_sql…）以 OpenCode /mcp 清單為準，
   一律使用唯讀查詢工具。
```

## Effective Date 標準樣式（有 EFFDT 的表都要套）

```sql
AND A.EFF_STATUS = 'A'
AND A.EFFDT = (SELECT MAX(B.EFFDT) FROM <同表> B
                WHERE B.<同鍵> = A.<同鍵> AND B.EFFDT <= SYSDATE)
```

---

## 1. Object Origin（協定角色：ps_get_object_origin）

Prefix 判斷不用 SQL（比對 customization-profile 的 customPrefixes）。SQL 補兩件事：

**1a. 客製登錄（CUSTOM_REGISTRY）— 物件是否在客製 Project 內**

```sql
SELECT PROJECTNAME, OBJECTTYPE, OBJECTVALUE1
  FROM PSPROJECTITEM
 WHERE OBJECTVALUE1 = :objectName
FETCH FIRST 50 ROWS ONLY
```

> 客製 Project 清單 / 自訂登錄表依環境而定（customization-profile 的
> customObjectRegistry），有專屬登錄表時改查該表。

**1b. MODIFIED_DELIVERED 啟發式 — 原生名稱但被改過**

```sql
SELECT RECNAME, LASTUPDOPRID, LASTUPDDTTM
  FROM PSRECDEFN
 WHERE RECNAME = :recName
```

`LASTUPDOPRID <> 'PPLSOFT'` → 疑似被客戶修改（結論標 **INFERRED**，
確認要靠 Compare Report）。Page 用 `PSPNLDEFN`、Component 用 `PSPNLGRPDEFN`、
Menu 用 `PSMENUDEFN`，同樣看 `LASTUPDOPRID`。

---

## 2. UI 語意與選項（協定角色：ps_get_field_choices / ps_search_ui_semantics 反查）

**2a. Translate Values（含中文語系）**

```sql
SELECT A.FIELDVALUE, A.XLATLONGNAME, L.XLATLONGNAME AS XLAT_ZHT
  FROM PSXLATITEM A
  LEFT JOIN PSXLATITEMLANG L
    ON L.FIELDNAME = A.FIELDNAME AND L.FIELDVALUE = A.FIELDVALUE
   AND L.EFFDT = A.EFFDT AND L.LANGUAGE_CD = 'ZHT'
 WHERE A.FIELDNAME = :fieldName
   AND A.EFF_STATUS = 'A'
   AND A.EFFDT = (SELECT MAX(B.EFFDT) FROM PSXLATITEM B
                   WHERE B.FIELDNAME = A.FIELDNAME
                     AND B.FIELDVALUE = A.FIELDVALUE AND B.EFFDT <= SYSDATE)
FETCH FIRST 100 ROWS ONLY
```

**2b. 由選項文字反查欄位（「免役是哪個欄位的值？」）**

```sql
SELECT L.FIELDNAME, L.FIELDVALUE, L.XLATLONGNAME
  FROM PSXLATITEMLANG L
 WHERE L.LANGUAGE_CD = 'ZHT' AND L.XLATLONGNAME LIKE '%' || :displayText || '%'
FETCH FIRST 50 ROWS ONLY
```

**2c. 欄位 Label（含中文）**

```sql
SELECT A.FIELDNAME, A.LABEL_ID, A.LONGNAME, A.DEFAULT_LABEL, L.LONGNAME AS ZHT
  FROM PSDBFLDLABL A
  LEFT JOIN PSDBFLDLABLLANG L
    ON L.FIELDNAME = A.FIELDNAME AND L.LABEL_ID = A.LABEL_ID
   AND L.LANGUAGE_CD = 'ZHT'
 WHERE A.FIELDNAME = :fieldName
```

反查：`WHERE L.LANGUAGE_CD='ZHT' AND L.LONGNAME LIKE '%'||:text||'%'`。

**2d. Page 上有哪些欄位（Page → Record.Field）**

```sql
SELECT PNLNAME, FIELDNUM, RECNAME, FIELDNAME, FIELDTYPE, LBLTYPE, LABEL_ID
  FROM PSPNLFIELD
 WHERE PNLNAME = :pageName
FETCH FIRST 200 ROWS ONLY
```

反查欄位在哪些 Page：`WHERE RECNAME = :rec AND FIELDNAME = :fld`。

**2e. Component ↔ Page ↔ Menu**

```sql
-- Component 含哪些 Page
SELECT PNLGRPNAME, PNLNAME, ITEMLABEL FROM PSPNLGROUP WHERE PNLGRPNAME = :componentName;
-- Page 屬於哪些 Component
SELECT PNLGRPNAME FROM PSPNLGROUP WHERE PNLNAME = :pageName;
-- Component 掛在哪些 Menu
SELECT MENUNAME, BARNAME, ITEMNAME FROM PSMENUITEM WHERE PNLGRPNAME = :componentName;
```

**2f. Prompt Table 與基數**

```sql
SELECT RECNAME, FIELDNAME, EDITTABLE
  FROM PSRECFIELDDB
 WHERE RECNAME = :recName AND FIELDNAME = :fieldName;
-- 先估基數再決定要不要列值（實體表名：SQLTABLENAME 空白時為 PS_<RECNAME>）
SELECT COUNT(*) FROM PS_<EDITTABLE>;
```

---

## 3. Process / 排程（協定角色：ps_get_process_usage）

```sql
-- 程式 → Process Definition
SELECT PRCSTYPE, PRCSNAME, DESCR FROM PS_PRCSDEFN WHERE PRCSNAME = :name;
-- 允許執行它的 Component（Run Control 頁面所在）
SELECT PRCSNAME, PNLGRPNAME FROM PS_PRCSDEFNPNL WHERE PRCSNAME = :name;
-- 被哪些 Job 包含
SELECT PRCSJOBNAME, PRCSNAME, PRCSJOBSEQ FROM PS_PRCSJOBITEM WHERE PRCSNAME = :name;
-- 已排程的請求（recurrence 名稱在此）
SELECT PRCSNAME, RECURNAME, RUNSTATUS, RUNDTTM
  FROM PSPRCSRQST WHERE PRCSNAME = :name AND RECURNAME <> ' '
FETCH FIRST 50 ROWS ONLY;
-- Recurrence 定義
SELECT * FROM PS_PRCSRECUR WHERE RECURNAME = :recurName;
```

---

## 4. Security（協定角色：ps_get_security_path）

```sql
-- Component → Permission List（經由 Menu Item）
SELECT DISTINCT A.CLASSID, A.MENUNAME, A.AUTHORIZEDACTIONS
  FROM PSAUTHITEM A
  JOIN PSMENUITEM M
    ON A.MENUNAME = M.MENUNAME AND A.BARITEMNAME = M.ITEMNAME
 WHERE M.PNLGRPNAME = :componentName
FETCH FIRST 100 ROWS ONLY;

-- Permission List → Roles
SELECT ROLENAME, CLASSID FROM PSROLECLASS WHERE CLASSID = :classId;

-- Role → 使用者「數量」（只回彙總，不列名單）
SELECT ROLENAME, COUNT(*) AS USER_CNT
  FROM PSROLEUSER WHERE ROLENAME = :roleName GROUP BY ROLENAME;

-- Row-level：Component 的 Search Record
SELECT PNLGRPNAME, SEARCHRECNAME, ADDSRCHRECNAME
  FROM PSPNLGRPDEFN WHERE PNLGRPNAME = :componentName;
```

---

## 5. AE 結構（協定角色：ps_get_ae_graph 近似）

```sql
-- AE 有哪些 Section
SELECT AE_APPLID, AE_SECTION, DESCR FROM PSAESECTDEFN WHERE AE_APPLID = :aeName;
-- Section 有哪些 Step
SELECT AE_SECTION, AE_STEP, AE_STMT_TYPE
  FROM PSAESTEPDEFN WHERE AE_APPLID = :aeName AND AE_SECTION = :section;
```

> Step 的 SQL / PeopleCode **內容**不從這裡撈——照長文本協定走
> PeoplecodeElasticSearch + PeoplecodeSource。

---

## 6. Record / Field 基本盤

```sql
-- Record 定義與實體表名（SQLTABLENAME 空白 → PS_<RECNAME>）
SELECT RECNAME, RECTYPE, SQLTABLENAME, RECDESCR FROM PSRECDEFN WHERE RECNAME = :recName;
-- Record 欄位清單（含 subrecord 展開）
SELECT RECNAME, FIELDNAME, FIELDNUM, EDITTABLE
  FROM PSRECFIELDDB WHERE RECNAME = :recName ORDER BY FIELDNUM
FETCH FIRST 200 ROWS ONLY;
-- 欄位被哪些 Record 使用（血緣輔助）
SELECT RECNAME FROM PSRECFIELDDB WHERE FIELDNAME = :fieldName
FETCH FIRST 100 ROWS ONLY;
```
