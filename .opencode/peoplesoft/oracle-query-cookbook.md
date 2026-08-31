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
7a. **通道前置檢查（L103）**：可用工具清單裡**一個 `oracleMCP_` 前綴
   工具都沒有**＝通道未掛（SQLcl MCP 未啟動／VS Code 端已死），
   **不是工具名記錯、不是暫時故障、重試不會出現**。處置：**立即回報
   FAIL(ORACLE_MCP_DOWN) 並結束本委派**——禁止猜工具名重試
   （實案：模型自創 `oracle_sql_run` 反覆撞牆到被 doom_loop 攔截）。
   **換路查可以、冒充不行**：ES／Source／metadata MCP 有等價線索
   （程式碼、註解、metadata 定位）照常可查——但產物**只能以
   INFERRED＋CHUNK 證據**入報告，並記「DB 實際狀態待通道恢復驗證」；
   **不得**寫成 SQL 型證據（DB 狀態事實只有可重跑的 SELECT 驗得動，
   chunk 只能證明程式碼怎麼寫）、不得憑它宣稱查無、
   原 SQL 型待辦不因此視為完成。
8. **查詢前欄位驗證**：要用「樣板裡沒有的
   欄位名」或不確定欄位存不存在時，先跑
   SELECT column_name FROM all_tab_columns WHERE table_name='<大寫表名>'
   確認後再查——**禁止憑記憶寫欄位名**；驗證後仍無該欄位 →
   記 gaps，不要換個猜法再試。
8a. **表名同理，且禁止自行加減 `PS_` 前綴**：PeopleTools 系統表
   **不一定**有 PS_ 前綴——本 cookbook 樣板即並存兩型
   （`PSPRCSRQST` 無前綴、`PS_PRCSRECUR` 有前綴）。**樣板怎麼寫就怎麼查**；
   樣板沒有的表先跑
   SELECT table_name FROM all_tables WHERE table_name LIKE '%<關鍵字>%'
   確認實際表名。**「加了前綴查不到」不是資料不存在，是表名寫錯。**
9. **metadata MCP 不得作 evidence**：
   PeoplecodeMetadata 的工具（find_field_usage／search_component_metadata／
   get_ae_sql_metadata／**get_process_schedule_list**）回傳一律只作
   **定位線索**——證據契約只認 CHUNK 與 SQL 兩種。排程／metadata 類事實
   要當證據，就得用本 cookbook 的 SELECT 取得並附「SQL＋關鍵列」。
```

## 連線生命週期（每次任務照此順序，硬性）

SQLcl MCP 是**單工、有狀態**的：一個行程只有一條「目前連線」，指令依序執行。

```text
1. list-connections     → 取得可用的已儲存連線名（不要自己編連線名）
2. connect（帶連線名）   → 切換本行程的目前連線
3. 設 schema            → read customization-profile.yaml 取
                          oracle.currentSchema，執行一次
                          ALTER SESSION SET CURRENT_SCHEMA=<該值>
                          （**唯一准許的非 SELECT 語句**；
                          值為 FILL_ME → 跳過此步）
4. 查詢                 → 本次任務的查詢全部做完（裸表名即可，
                          schema 已由第 3 步解決——PeopleTools 表
                          不屬於登入帳號的 schema，漏這步會
                          view/table not found）
5. disconnect           → 用完必斷，不要佔住單工 server
```

逾時與平行規則：

```text
- connect 或任何查詢超過約 30 秒沒返回 → 停手，回報 status: BLOCKED，
  gaps 註明「oracleMCP 無回應」。
- 不准重試迴圈：卡住的呼叫重發只會排在後面繼續卡，還會佔住 server
  禍及其他 agent。
- 不要假設可以同時有第二條連線——「目前連線」是行程級全域狀態，
  交錯使用會把查詢跑在錯的連線上。
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

**2g. 選項使用實況（「哪些選項還在用？」）**

```sql
-- 各值的實際資料分布（只回彙總，不撈明細；實體表名規則見 §6）
SELECT <FIELDNAME>, COUNT(*) AS CNT
  FROM PS_<RECNAME>
 GROUP BY <FIELDNAME>
 ORDER BY CNT DESC
FETCH FIRST 50 ROWS ONLY
```

```sql
-- 含停用的完整選項清單（判斷廢棄選項時不要過濾 EFF_STATUS）
SELECT A.FIELDVALUE, A.EFF_STATUS, A.EFFDT, A.XLATLONGNAME
  FROM PSXLATITEM A
 WHERE A.FIELDNAME = :fieldName
   AND A.EFFDT = (SELECT MAX(B.EFFDT) FROM PSXLATITEM B
                   WHERE B.FIELDNAME = A.FIELDNAME
                     AND B.FIELDVALUE = A.FIELDVALUE AND B.EFFDT <= SYSDATE)
FETCH FIRST 100 ROWS ONLY
```

> 「已經沒用到」的結論需要**三重證據**：XLAT 狀態（INACTIVE？）＋
> 程式邏輯（ps-peoplecode-flow 以該值搜尋是否命中）＋ 資料分布
> （上面的 COUNT 是否為 0）。只有部分證據時標 INFERRED。

**2h. 條件 UI：變異目標解析（Record.Field → 控制項）**

PeopleCode UI 狀態變異（Visible 等）的目標解析入口。**不濾 FIELDTYPE**——
目標可能是任何控制項，先取回再分流：`FIELDTYPE = 2`（Group Box）→ 2i；
`FIELDTYPE = 11`（Subpage）→ 2j；其他＝一般控制項，受影響者即其自身，
毋須後續查詢。

```sql
SELECT PNLNAME, PNLFLDID, FIELDNUM, FIELDTYPE, PNLFIELDNAME,
       RECNAME, FIELDNAME, SUBPNLNAME, LBLTEXT, OCCURSLEVEL,
       FIELDLEFT, FIELDTOP, FIELDRIGHT, FIELDBOTTOM, PTHIDEFIELDS
  FROM PSPNLFIELD
 WHERE RECNAME = :recName AND FIELDNAME = :fieldName
FETCH FIRST 50 ROWS ONLY
```

`PTHIDEFIELDS`（Group Box 專用，0/1）：1＝隱藏 Group Box 時框內欄位
一併隱藏（受影響控制項用 2i 展開）；0＝只隱藏外框（presentationOnly）。
同一 Record.Field 出現在多個 PNLNAME → 候選全數保留，
Component 歸屬以 PeopleCode 證據所在者優先。

**2i. Group Box 框內控制項（Classic 幾何範圍）**

參數逐項取自 2h 該 Group Box 列（:pageName←PNLNAME、:groupBoxId←PNLFLDID、
:groupLeft/Top/Right/Bottom←FIELDLEFT/TOP/RIGHT/BOTTOM）。
幾何包含是推斷——「框內」結論最高標 **INFERRED**
（Page 與控制項座標本身仍是 SQL 證據）。

```sql
SELECT PNLFLDID, FIELDNUM, FIELDTYPE, PNLFIELDNAME, RECNAME, FIELDNAME,
       SUBPNLNAME, LBLTEXT, OCCURSLEVEL
  FROM PSPNLFIELD
 WHERE PNLNAME = :pageName
   AND PNLFLDID <> :groupBoxId
   AND FIELDLEFT >= :groupLeft AND FIELDRIGHT <= :groupRight
   AND FIELDTOP >= :groupTop AND FIELDBOTTOM <= :groupBottom
 ORDER BY FIELDNUM
FETCH FIRST 200 ROWS ONLY
```

**2j. Subpage 展開與向上解析**

```sql
-- 展開：Subpage 內有哪些控制項（結果中 FIELDTYPE=11 者以其 SUBPNLNAME 遞迴展開）
SELECT PNLNAME, PNLFLDID, FIELDNUM, FIELDTYPE, PNLFIELDNAME,
       RECNAME, FIELDNAME, SUBPNLNAME, LBLTEXT, OCCURSLEVEL
  FROM PSPNLFIELD
 WHERE PNLNAME = :subpageName
 ORDER BY FIELDNUM
FETCH FIRST 200 ROWS ONLY;
-- 向上：這個 Subpage 被哪些 Page 掛載。PSPNLGROUP 只登記真正的 Page——
-- 變異目標長在 Subpage 上時，先向上找到掛載 Page（必要時遞迴），
-- 才能用 §2e 對映 Component。
SELECT PNLNAME FROM PSPNLFIELD
 WHERE SUBPNLNAME = :subpageName AND FIELDTYPE = 11
FETCH FIRST 50 ROWS ONLY;
```

Page → Component 對映用 §2e；控制項缺 LBLTEXT 時補中文 label 用 §2c。

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
