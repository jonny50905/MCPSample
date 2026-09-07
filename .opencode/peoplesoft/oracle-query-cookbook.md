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

## 連線生命週期（硬性；連線的擁有者是主 agent）

SQLcl MCP 是**單工、有狀態**的：一個行程只有一條「目前連線」，指令依序執行。
**定案**：這條連線是 MCP server 全域單例——main 與所有 subagent 共用同一個開關，
任何一方 `disconnect` 就把其他人一起斷線。所以：**開，只有主 agent 做；關，誰都不做；查，subagent 做。**

**主 agent（ps-orchestrator／ps-deep-research／ps-audit-orchestrator）——每題／每批開場，無條件；做完才准查 wiki、委派、作答**：

```text
0. 工具清單裡沒有任何 oracleMCP_ 工具 → ORACLE_MCP_DOWN（規則 7a），不試 connect，如實回報。
   工具名（底線）：list_connections／connect／run_sql／disconnect
1. list_connections     → 開場就做（無條件、不跳過）；取得已儲存連線名清單（不要自己編）；
                          清單為空 → CONNECT_FAILED（NO_SAVED_CONNECTION），如實回報「SQLcl 沒有已儲存連線」
2. connect（帶連線名）   → 緊接著做，不判斷本題會不會用到 DB；連線名＝profile oracle.connectionName（有填且在清單裡）
                          或清單第一個；回「已連線」也視為成功；失敗再 list → connect 一次；>30 秒無回應 → CONNECT_TIMEOUT
3. 之後本題／本批的委派都不必再 connect。subagent 回 BLOCKED(NOT_CONNECTED) → 再 connect 一次、
   重派一次；第二次仍 NOT_CONNECTED → 對使用者／收據如實寫「DB 連線建立失敗（<connect 的錯誤>）」，
   不得說成「DB 通道忙碌」
4. 主 agent 永遠不自己 run_sql、不 disconnect
```

**subagent（ps-ui-flow／ps-metadata-flow／ps-ae-flow／ps-auditor）——每次委派**：

```text
1. 直接發本次任務的第一個 SELECT（連線已由主 agent 建好）
2. 回「未連線／not connected／no connection」類錯誤 → 立即回報 status=BLOCKED、blockedReason=NOT_CONNECTED，
   結束本委派。不 list_connections、不 connect（工具已關）、不重試
3. 設 schema            → read customization-profile.yaml 取 oracle.currentSchema，執行一次
                          ALTER SESSION SET CURRENT_SCHEMA=<該值>（唯一准許的非 SELECT 語句；
                          重複執行無害；值為 FILL_ME → 跳過）→ 重發第 1 步那個查詢一次。
                          view/table not found 且值為 FILL_ME → blockedReason=SCHEMA_UNRESOLVED，不是 NOT_CONNECTED
4. 查詢                 → 本次任務的查詢全部做完（裸表名即可，schema 已由第 3 步解決）
5. 不得 disconnect      → 工具已關；逾時、BLOCKED 回報前也一樣不斷線
```

逾時與平行規則：

```text
- connect 或任何查詢超過約 30 秒沒返回 → 停手：主 agent 記 CONNECT_TIMEOUT；subagent 回
  status: BLOCKED、blockedReason=QUERY_TIMEOUT，gaps 註明「oracleMCP 無回應」。
- 不准重試迴圈：卡住的呼叫重發只會排在後面繼續卡，還會佔住 server 禍及其他 agent。
- 不要假設可以同時有第二條連線——「目前連線」是行程級全域狀態，交錯使用會把查詢跑在錯的連線上。
- 會查 oracleMCP 的委派同時 ≤ 3（單一連線內 SQL 仍是排隊執行，再多只會撞 30 秒逾時）；
  連線由主 agent 先建好，第一個 DB 委派不必等前一個回報，可與其餘同時派出。純 ES＋Source 的委派不受此限。
- 任何情況都不呼叫 disconnect——斷線會把 main 與其他 subagent 一起拆掉。
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
-- Component 掛在哪些 Menu（**technicalMenuLocation**：App Designer 技術選單 metadata，
-- 8.4 之後 BARNAME（USE／PROCESS／INQUIRE…）在 PIA 沒有對應層級——**不得串成使用者導覽路徑**；
-- 使用者看得到的入口走 §2k Portal Registry。本段亦是 §2k-2 的 seed（menu＋component＋market）
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

**2k. Navigation Entry Discovery（Portal Registry；協定角色：ps_get_navigation_entries）**

用途：回答「使用者從哪裡點得到這個 Component」。輸出**複數** `navigationEntries[]`，
每筆帶 `portalName / entryType / crefObjectName / labels[] / visibility`，
與 §2e 的 `technicalMenuLocations[]`（PSMENUITEM 三欄）**分開回報，永不合併**。
本節的表名／欄位／代碼值域以 `customization-profile.yaml` 的 `navigation:` 區塊為準：`verified: true` ＝ 已在本環境
驗證回填，**直接跑 §2k-C**；`verified: false` ＝ 先跑 2k-0（`all_tables` 驗表名、`all_tab_columns` 驗欄位名、值域分布），
回填 profile 後再跑 §2k-C；查不到記 gaps，不硬湊、不自行加減 `PS_` 前綴。未驗證前本節結論最高只能標 **INFERRED**。
`REGISTRY_DEFINED／AUTHORIZED_FOR_CONTEXT／UNKNOWN_VISIBILITY` 是**可見性**維度，與 confidence 正交，
不得寫進 confidence 欄（subagent-report-contract 硬規則 3a）。

**2k-0. 前置欄位驗證（必跑，其餘 2k-* 的前提）**

```sql
-- (1) 表名（規則 8a：樣板沒有的表先確認實際表名，禁止自行加減 PS_）
SELECT TABLE_NAME FROM ALL_TABLES
 WHERE TABLE_NAME IN ('PSPRSMDEFN','PSPRSMDEFNLANG','PSPRSMPERM','PSPRSMSYSATTRVL',
                      'PSPRSMATTRVAL','PSPRSMNAVINFO','PSPRDMDEFN','PSMENUITEM','PSOPTIONS')
FETCH FIRST 20 ROWS ONLY;
-- (2) 欄位名／型別（規則 8：禁止憑記憶寫欄位名）
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, DATA_LENGTH, COLUMN_ID
  FROM ALL_TAB_COLUMNS
 WHERE TABLE_NAME IN ('PSPRSMDEFN','PSPRSMDEFNLANG','PSPRSMSYSATTRVL','PSPRDMDEFN','PSMENUITEM','PSOPTIONS')
 ORDER BY TABLE_NAME, COLUMN_ID
FETCH FIRST 200 ROWS ONLY;
-- (2b) base language（決定 2k-4 的 fallbackLanguageCode；不得憑 delivered convention 填 ENG）——表名／欄位同樣先看 (1)(2) 有沒有列出
SELECT LANGUAGE_CD FROM PSOPTIONS FETCH FIRST 1 ROWS ONLY;
-- (3) 代碼值域（不得憑記憶填，觀察後回填本節）
-- (3) 必須在讀完 (1)(2) 回傳之後才發：(1) 未列出的表、(2) 未列出的欄位，其對應的 (3) 查詢直接跳過並記 gap
SELECT PORTAL_REFTYPE, COUNT(*) FROM PSPRSMDEFN GROUP BY PORTAL_REFTYPE FETCH FIRST 20 ROWS ONLY;
SELECT PORTAL_CREF_USGT, COUNT(*) FROM PSPRSMDEFN WHERE PORTAL_REFTYPE = 'C'
 GROUP BY PORTAL_CREF_USGT ORDER BY 2 DESC FETCH FIRST 20 ROWS ONLY;
SELECT DISTINCT PORTAL_ATTR_NAM FROM PSPRSMSYSATTRVL ORDER BY 1 FETCH FIRST 100 ROWS ONLY;
SELECT PORTAL_NAME FROM PSPRDMDEFN ORDER BY 1 FETCH FIRST 50 ROWS ONLY;
```

> **未驗前的降級規則**：(1)(2) 任一表／欄位查無 → 該筆記 gaps，**該 2k 步驟停止**（含本步驟的 (3)），
> 文件寫「Portal Registry 導覽入口：未確認（navigation metadata 尚未查證）」，
> **不得**退回用 PSMENUITEM 補位。`portalName` 一律由 `PSPRDMDEFN` 列舉取得，
> **禁止硬編** `EMPLOYEE／CUSTOMER／SUPPLIER／PARTNER`（後三者非普遍交付）。
> `PORTAL_CREF_USGT` 代碼→entryType 的對照（待驗）：`TARG`→PORTAL_REGISTRY、`LINK`→CREF_LINK；
> `GRPT`／`HPGT`／`HPGC`→Fluid／首頁類**本版不解析**，一律回 gap；`FRMT`／`HTMT`／`IFRM`＝模板管線，排除。
> **本環境是否只有 C／F 兩種 PORTAL_REFTYPE 亦待驗**；出現第三值＝環境意外，記 gaps 不得靜默假設。

**2k-C. Classic 導覽 canonical query（主流程；`navigation.verified: true` 時直接跑）**

輸入只有 `:componentName`；`:portalName`＝profile `navigation.portal`、`:languageCd`＝`navigation.labelLanguage`。
**原樣執行、原樣回傳**：不改字、不補段、不加 BARNAME／ITEMNAME；`MENU_PATH` 的每一段只來自 PSPRSMDEFN 的 label。

```sql
WITH NAV_TREE AS (
    SELECT CONNECT_BY_ROOT D.PORTAL_NAME      AS TARGET_PORTAL,
           CONNECT_BY_ROOT D.PORTAL_OBJNAME   AS TARGET_CREF,
           CONNECT_BY_ROOT D.PORTAL_CREF_USGT AS TARGET_USGT,
           LEVEL                              AS LVL,
           D.PORTAL_OBJNAME, D.PORTAL_PRNTOBJNAME,
           TRIM(D.PORTAL_LABEL)               AS BASE_LABEL,
           (SELECT TRIM(L.PORTAL_LABEL) FROM PSPRSMDEFNLANG L
             WHERE L.PORTAL_NAME = D.PORTAL_NAME AND L.PORTAL_REFTYPE = D.PORTAL_REFTYPE
               AND L.PORTAL_OBJNAME = D.PORTAL_OBJNAME AND L.LANGUAGE_CD = :languageCd) AS LANG_LABEL,
           CASE WHEN EXISTS (SELECT 1 FROM PSPRSMSYSATTRVL A
                              WHERE A.PORTAL_NAME = D.PORTAL_NAME AND A.PORTAL_REFTYPE = D.PORTAL_REFTYPE
                                AND A.PORTAL_OBJNAME = D.PORTAL_OBJNAME AND A.PORTAL_ATTR_NAM = 'PORTAL_HIDE_FROM_NAV'
                                AND UPPER(TRIM(DBMS_LOB.SUBSTR(A.PORTAL_ATTR_VAL, 100, 1))) IN ('TRUE','Y','1'))
                THEN 1 ELSE 0 END AS IS_HIDDEN,
           CASE WHEN D.PORTAL_EXPIRE_DT IS NOT NULL AND D.PORTAL_EXPIRE_DT < SYSDATE THEN 1 ELSE 0 END AS IS_EXPIRED,
           CASE WHEN D.PORTAL_OBJNAME = 'PORTAL_ROOT_OBJECT' OR TRIM(D.PORTAL_PRNTOBJNAME) IS NULL THEN 1 ELSE 0 END AS IS_ROOT,
           CONNECT_BY_ISCYCLE                 AS IS_CYCLE
      FROM PSPRSMDEFN D
     START WITH D.PORTAL_REFTYPE = 'C'
            AND D.PORTAL_CREF_USGT IN ('TARG','LINK')
            AND D.PORTAL_NAME = :portalName
            AND UPPER(TRIM(D.PORTAL_URI_SEG2)) = UPPER(:componentName)
            AND EXISTS (SELECT 1 FROM PSMENUITEM M
                         WHERE UPPER(TRIM(M.PNLGRPNAME)) = UPPER(:componentName)
                           AND UPPER(TRIM(M.MENUNAME)) = UPPER(TRIM(D.PORTAL_URI_SEG1)))
   CONNECT BY NOCYCLE PRIOR D.PORTAL_PRNTOBJNAME = D.PORTAL_OBJNAME
          AND PRIOR D.PORTAL_NAME = D.PORTAL_NAME
          AND D.PORTAL_REFTYPE = 'F'
          AND LEVEL <= 20
),
NAV_ROWS AS (
    SELECT T.*,
           COALESCE(NULLIF(LANG_LABEL, ''), BASE_LABEL) AS DISPLAY_LABEL,
           CASE WHEN NULLIF(LANG_LABEL, '') IS NULL THEN 'BASE' ELSE 'LANG' END AS LABEL_SOURCE
      FROM NAV_TREE T
),
NAV_PATHS AS (
    SELECT TARGET_PORTAL AS PORTAL_NAME, TARGET_CREF AS CREF_OBJECT, TARGET_USGT AS CREF_USGT,
           LISTAGG(CASE WHEN IS_ROOT = 0 THEN DISPLAY_LABEL END, ' > ') WITHIN GROUP (ORDER BY LVL DESC) AS MENU_PATH,
           MAX(IS_HIDDEN) AS PATH_HIDDEN, MAX(IS_EXPIRED) AS PATH_EXPIRED,
           MAX(IS_ROOT) AS ROOT_REACHED, MAX(IS_CYCLE) AS HAS_CYCLE,
           SUM(CASE WHEN IS_ROOT = 0 AND DISPLAY_LABEL IS NULL THEN 1 ELSE 0 END) AS BLANK_SEGMENTS,
           CASE WHEN MAX(IS_HIDDEN) = 0 AND MAX(IS_EXPIRED) = 0 AND MAX(IS_ROOT) = 1 AND MAX(IS_CYCLE) = 0
                 AND SUM(CASE WHEN IS_ROOT = 0 AND DISPLAY_LABEL IS NULL THEN 1 ELSE 0 END) = 0
                THEN 1 ELSE 0 END AS CLASSIC_VISIBLE
      FROM NAV_ROWS
     GROUP BY TARGET_PORTAL, TARGET_CREF, TARGET_USGT
)
SELECT PORTAL_NAME, CREF_OBJECT, CREF_USGT, MENU_PATH
  FROM NAV_PATHS
 WHERE CLASSIC_VISIBLE = 1
 ORDER BY PORTAL_NAME, MENU_PATH
FETCH FIRST 200 ROWS ONLY
```

> **結果映射（canonical 一列＝一個 Classic 選單看得到的入口）**：每列 → `navigationEntries[]` 一筆，`entryType` 依
> `CREF_USGT`（TARG→`PORTAL_REGISTRY`、LINK→`CREF_LINK`）、`visibility = CLASSIC_NAV_VISIBLE`、`labels[]` 由逐段列填。
> **逐段列**（供 `labels[].displayText／displayTextSource`）：同一組 CTE，最後的 SELECT 換成
> `SELECT TARGET_CREF, LVL, PORTAL_OBJNAME, DISPLAY_LABEL, LABEL_SOURCE FROM NAV_ROWS ORDER BY TARGET_CREF, LVL DESC FETCH FIRST 200 ROWS ONLY`。
> **診斷形（只在 canonical 回 0 列時跑）**：最後的 SELECT 換成
> `SELECT * FROM NAV_PATHS ORDER BY CLASSIC_VISIBLE DESC, PORTAL_NAME, MENU_PATH FETCH FIRST 200 ROWS ONLY`——
> 有列但 `CLASSIC_VISIBLE = 0` → 文件寫「Classic 選單無可見入口（Registry 有 N 筆）」，gaps 每筆記一行原因
> （`PATH_HIDDEN`＝hide-from-nav／`PATH_EXPIRED`＝過期／`ROOT_REACHED=0`＝未達根／`HAS_CYCLE`＝循環／`BLANK_SEGMENTS`＝空 label）；
> 診斷形也 0 列 → 分三種，不得猜：(a) `:componentName` 打錯或 PSMENUITEM 無此 Component（跑 2k-1 確認）；
> (b) Registry 真的沒有 CREF（跑 2k-2 診斷查詢，去掉 EXISTS 再跑一次）；(c) 全部 CREF 都在其他 portal（把 `:portalName` 條件拿掉重跑）。
> 三者都空＝「Portal Registry 導覽入口：查無」＋gaps 記查法收據。
> `PSMENUITEM` 在本 query 只做 identity seed（PNLGRPNAME→Component、MENUNAME→SEG1）；BARNAME／ITEMNAME 永遠不參與路徑。
> `navigation.identity: MENU_COMPONENT_MARKET` 的環境才在 START WITH 加 `AND UPPER(TRIM(D.PORTAL_URI_SEG3)) = UPPER(:market)`。

**2k-1. Technical Menu seed（只叫 technicalMenuLocation）**

```sql
SELECT MENUNAME, BARNAME, ITEMNAME, PNLGRPNAME, MARKET
  FROM PSMENUITEM WHERE PNLGRPNAME = :componentName
FETCH FIRST 200 ROWS ONLY
```

> 本段的**唯一合法用途**是識別 seed（menu＋component；`navigation.identity: MENU_COMPONENT_MARKET` 的環境才加 market）
> 與報告的 `technicalMenuLocations[]`。`MARKET` 欄只在 identity 含 MARKET 時才查；欄位由 2k-0 (2) 驗證，未列出就不查——**不得**先查再等 ORA-00904。
> 輸出欄位名一律 `technicalMenuLocations[]`，**永遠不得**輸出成 `menuPath`／選單路徑／導覽入口。

**2k-2. Portal CREF 識別（診斷用：§2k-C 回 0 列時排查；identity 含 MARKET 時才比 SEG3）**

```sql
-- 首選：structured URI 欄位（三欄同時比對，且限定 content reference）
SELECT PORTAL_NAME, PORTAL_OBJNAME, PORTAL_CREF_USGT, PORTAL_LABEL, PORTAL_PRNTOBJNAME,
       PORTAL_URI_SEG1, PORTAL_URI_SEG2, PORTAL_URI_SEG3, PORTAL_URLTEXT, PORTAL_EXPIRE_DT
  FROM PSPRSMDEFN
 WHERE PORTAL_REFTYPE = 'C'
   AND UPPER(TRIM(PORTAL_URI_SEG1)) = UPPER(:menuName)
   AND UPPER(TRIM(PORTAL_URI_SEG2)) = UPPER(:componentName)
   AND UPPER(TRIM(PORTAL_URI_SEG3)) = UPPER(:market)   -- identity=MENU_COMPONENT_MARKET 時才保留本行
FETCH FIRST 200 ROWS ONLY;
-- 次選（structured 欄位空白時）：對 PORTAL_URLTEXT 做**整段錨定**比對，不是子字串比對
SELECT PORTAL_NAME, PORTAL_OBJNAME, PORTAL_CREF_USGT, PORTAL_LABEL, PORTAL_PRNTOBJNAME, PORTAL_URLTEXT, PORTAL_EXPIRE_DT
  FROM PSPRSMDEFN
 WHERE PORTAL_REFTYPE = 'C'
   AND UPPER(PORTAL_URLTEXT) LIKE '%/C/' || UPPER(:menuName) || '.' || UPPER(:componentName) || '.' || UPPER(:market) || '%'
   -- 或（避免 `_` 被 LIKE 當單字元萬用字元）：AND INSTR(UPPER(PORTAL_URLTEXT), '/C/' || UPPER(:menuName) || '.' || UPPER(:componentName) || '.' || UPPER(:market)) > 0
FETCH FIRST 200 ROWS ONLY;
-- 診斷（前兩條皆 0 列時才跑）：menu＋component 命中但 market 不符／空白 ⇒ PARTIAL_IDENTITY_MATCH（永不 CONFIRMED）
SELECT PORTAL_NAME, PORTAL_OBJNAME, PORTAL_CREF_USGT, PORTAL_LABEL, PORTAL_PRNTOBJNAME,
       PORTAL_URI_SEG1, PORTAL_URI_SEG2, PORTAL_URI_SEG3, PORTAL_URLTEXT, PORTAL_EXPIRE_DT
  FROM PSPRSMDEFN
 WHERE PORTAL_REFTYPE = 'C'
   AND UPPER(TRIM(PORTAL_URI_SEG1)) = UPPER(:menuName)
   AND UPPER(TRIM(PORTAL_URI_SEG2)) = UPPER(:componentName)
FETCH FIRST 200 ROWS ONLY
```

> **硬性禁止**：`LIKE '%' || :componentName || '%'`、只比 `PORTAL_URI_SEG2` 而不綁 MENUNAME（§2k-C 的 SEG2＋PSMENUITEM EXISTS 是二鍵識別，合法）、憑欄位位置猜 SEG 語意。
> SEG 只在 **component 型 CREF**（URL 文法 `/c/<MENU>.<COMPONENT>.<MARKET>`）才是 menu／component／market；
> `q/`（Query）、`s/`（iScript）、`w/`（Worklist）與外部 URL CREF 的 SEG 語意不同——判不出即 `entryType=UNKNOWN`。
> 次選路徑的每一筆結論標記 `confidence=INFERRED`（來源＝URLTEXT 文法解析），**不得標 CONFIRMED**。
> 命中的鍵數少於 profile `navigation.identity` 要求的鍵數（MENU_COMPONENT＝2、MENU_COMPONENT_MARKET＝3）只能回 `PARTIAL_IDENTITY_MATCH` 並記 gaps。
> `PORTAL_EXPIRE_DT < SYSDATE` 的 CREF：入口仍列出，但 `visibility` 降為 `UNKNOWN_VISIBILITY` 並記 gap
> （「valid-from」對應欄位名未證實，**不得**憑記憶寫 `PORTAL_EFFDT`）。
> 首選／次選／診斷三條都必須帶回 `PORTAL_EXPIRE_DT`；沒取到＝視為未檢查，該筆一律 `visibility=UNKNOWN_VISIBILITY`＋gap。
> 次選命中後必須把 URLTEXT 依 `/c/<MENU>.<COMPONENT>.<MARKET>` 文法切段、逐段等值比對確認（`_` 在 LIKE 是萬用字元），比對不過即丟棄該筆並記 gap。
> 回傳列先依 `PORTAL_CREF_USGT` 分流（對照見 2k-0）：`TARG`／`LINK` 才進 2k-3；`FRMT`／`HTMT`／`IFRM` 排除、不列入 navigationEntries；
> `GRPT`／`HPGT`／`HPGC` 不走 2k-3，記 `entryType=FLUID_TILE／UNKNOWN`＋`visibility=UNKNOWN_VISIBILITY`＋gap；對照表以外的值＝環境意外，記 gaps。

**2k-3. 沿 parent 往上組路徑（診斷用；§2k-C 已內含本步：visited／depth cap／不跨 Portal／只走 Folder）**

```sql
SELECT LEVEL AS LVL, PORTAL_NAME, PORTAL_REFTYPE, PORTAL_OBJNAME,
       PORTAL_PRNTOBJNAME, PORTAL_LABEL, PORTAL_SEQ_NUM, PORTAL_EXPIRE_DT
  FROM PSPRSMDEFN
 START WITH PORTAL_NAME = :portalName
        AND PORTAL_REFTYPE = 'C'
        AND PORTAL_OBJNAME = :crefObjName
CONNECT BY NOCYCLE PRIOR PORTAL_PRNTOBJNAME = PORTAL_OBJNAME
        AND PRIOR PORTAL_NAME = PORTAL_NAME
        AND PORTAL_REFTYPE = 'F'
        AND LEVEL <= 20
 ORDER BY LVL DESC
FETCH FIRST 200 ROWS ONLY
```

> `NOCYCLE` ＋ `LEVEL <= 20` ＝ visited／深度上限（**cycle 不得 doom-loop**）；
> `AND PRIOR PORTAL_NAME = PORTAL_NAME` 寫在 `CONNECT BY` 內才擋得住跨 Portal（寫在外層 WHERE 只過濾輸出、擋不住走訪）。
> **終止判定**：最後一列 `PORTAL_OBJNAME = 'PORTAL_ROOT_OBJECT'`（或其 parent 為空）＝走到根，路徑完整；
> 撞到 LEVEL 20、或某段 parent 指向不存在的列（鏈提早斷）→ 該入口 `visibility=UNKNOWN_VISIBILITY`、
> 路徑標 `UNRESOLVED` 並記 gap；**絕不得**用物件名、delivered 慣例或印象補上缺掉的段。
> 祖先一律是 Folder：`CONNECT BY` 必須加 `PORTAL_REFTYPE = 'F'`，否則同名的 Folder 與 CREF 會讓走訪分叉。
> 隱藏旗標是 attribute 列（不是 PSPRSMDEFN 的欄位），鍵含 `PORTAL_REFTYPE`，值欄 `PORTAL_ATTR_VAL` 是 **CLOB**（直接比對＝ORA-00932）：
> `SELECT PORTAL_OBJNAME FROM PSPRSMSYSATTRVL WHERE PORTAL_NAME = :portalName AND PORTAL_REFTYPE = 'F' AND PORTAL_ATTR_NAM = 'PORTAL_HIDE_FROM_NAV' AND UPPER(TRIM(DBMS_LOB.SUBSTR(PORTAL_ATTR_VAL, 100, 1))) IN ('TRUE','Y','1') AND PORTAL_OBJNAME IN (<ancestor list>) FETCH FIRST 100 ROWS ONLY;`
> ——target CREF 或**任一祖先**命中 ＝ 整條路徑在 Classic 選單看不到 → canonical 不回該列（診斷形 `PATH_HIDDEN=1`），gaps 記一行。
> 同理，target 或**任一祖先** `PORTAL_EXPIRE_DT < SYSDATE` → canonical 不回該列（診斷形 `PATH_EXPIRED=1`），gaps 記一行。
> 平台可攜性：非 Oracle 環境改用遞迴 CTE＋顯式 depth 計數＋visited 反連接，行為必須完全一致（待驗）。

**2k-4. 語系 label（§2k-C 已內含：`:languageCd`＝profile `navigation.labelLanguage`；本段為逐段來源說明）**

```sql
SELECT D.PORTAL_OBJNAME,
       D.PORTAL_LABEL AS BASE_LABEL,
       L.PORTAL_LABEL AS LANG_LABEL,
       COALESCE(NULLIF(TRIM(L.PORTAL_LABEL), ''), D.PORTAL_LABEL) AS DISPLAY_TEXT
  FROM PSPRSMDEFN D
  LEFT JOIN PSPRSMDEFNLANG L
    ON L.PORTAL_NAME = D.PORTAL_NAME
   AND L.PORTAL_REFTYPE = D.PORTAL_REFTYPE
   AND L.PORTAL_OBJNAME = D.PORTAL_OBJNAME
   AND L.LANGUAGE_CD = :languageCd
 WHERE D.PORTAL_NAME = :portalName
   AND D.PORTAL_OBJNAME IN (<2k-3 的祖先清單>)
FETCH FIRST 200 ROWS ONLY
```

> **必須 LEFT JOIN**：INNER JOIN 會靜默丟掉沒有翻譯的段，產出「比較短的錯路徑」。
> 每一段都要保留 `displayText / languageCode / displayTextSource（LANG｜BASE）/ fallbackLanguageCode`
> ——ps-ui-flow SKILL 既有的語系義務（`languageCode` / `displayText` / `fallbackLanguageCode`）套用到導覽段。
> PeopleSoft 字元欄以空白而非 NULL 儲存，故用 `NULLIF(TRIM(...),'')` 而非裸 `COALESCE`。
> **PSPRSMDEFNLANG 的鍵清單與是否含 PORTAL_LABEL 待 2k-0 驗證**；查無該表／該欄 → 只回 base label，
> `displayTextSource=BASE`＋gap，不得宣稱已做語系 fallback。
> `fallbackLanguageCode`＝實際回退到的語系：LANG 命中＝`NOT_APPLICABLE`（未回退）；回退到 base＝2k-0 (2b) 查到的 base language；
> (2b) 未驗到＝`UNRESOLVED`＋gap，**不得**預設寫 ENG。

**2k-5. CREF Link 與其他入口 surface（複數入口；`navigation.surfaces: CLASSIC_ONLY` 時其他 surface 為 NOT_APPLICABLE）**

```sql
-- (1) LINK 的指向機制**未證實**，先探測：LINK 列是否也帶 URI 三段？
SELECT PORTAL_NAME, PORTAL_OBJNAME, PORTAL_CREF_USGT,
       PORTAL_URI_SEG1, PORTAL_URI_SEG2, PORTAL_URI_SEG3, PORTAL_URLTEXT, PORTAL_PRNTOBJNAME
  FROM PSPRSMDEFN
 WHERE PORTAL_REFTYPE = 'C' AND PORTAL_CREF_USGT = 'LINK'
FETCH FIRST 20 ROWS ONLY;
-- (2) 其他 surface 是否存在（存在與否都要回 gap，見下）
SELECT PORTAL_CREF_USGT, COUNT(*) FROM PSPRSMDEFN
 WHERE PORTAL_REFTYPE = 'C' AND PORTAL_CREF_USGT IN ('GRPT','HPGT','HPGC')
 GROUP BY PORTAL_CREF_USGT FETCH FIRST 20 ROWS ONLY;
SELECT PORTAL_OBJNAME, PORTAL_LABEL FROM PSPRSMDEFN
 WHERE PORTAL_REFTYPE = 'F'
   AND (UPPER(PORTAL_LABEL) LIKE '%FLUID%' OR UPPER(PORTAL_LABEL) LIKE '%NAVIGATION COLLECTION%')
FETCH FIRST 50 ROWS ONLY
```

> **每個 CREF 列只有一個 parent**（`PORTAL_PRNTOBJNAME` 單值）⇒ 一列＝一條路徑。
> 複數入口來自**多個 CREF 列**（1 個 TARG ＋ N 個 LINK），因此模型是「N 個錨點 × 各走一次 2k-3」，
> **不是**「一個錨點走出多條路徑」。每個 location 分開回傳、各自帶自己的 labels 與 visibility；
> 壓成單一路徑＝`SINGLE_PATH_COLLAPSE`。
> §2k-C 的 seed 已含 `LINK`：探測 (1) 若 LINK 列帶 URI 段 ⇒ canonical 已同時撈到 TARG 與 LINK，無需第二跳；
> 若不帶 ⇒ 需要一次「LINK → 目標 CREF」解析跳，該跳同樣要 visited set ＋ depth cap（link→link→link 不得成環），
> **在探測回填前，多入口宣稱一律附 gap「alternate entries not fully resolved」**。
> 破損 link（指向不存在的 CREF）＝該筆 `UNRESOLVED`＋gap，不猜目標。
> **Fluid Tile／NavBar／Navigation Collection**：`navigation.surfaces: CLASSIC_ONLY` → 一律 `NOT_APPLICABLE`，不跑 (2)、不記 gap，
> 入口數以 §2k-C 的可見列為準。`CLASSIC_AND_FLUID` 才適用以下：本版不解析，(2) 有命中＝`entryType=FLUID_TILE／UNKNOWN`
> ＋`visibility=UNKNOWN_VISIBILITY`＋gap；(2) 零命中也必須回 gap「alternate navigation surfaces not fully inspected」，
> 不得宣稱「唯一入口」。
> `PSPRSMNAVINFO`（若 2k-0 驗到存在）只能當**交叉檢查**：它由 App Engine 於索引建置時物化（會過期、可能為空）、
> 只涵蓋 TARG、且 `PORTAL_NAVPATH` 是預先組好的 CLOB（無法逐段做語系 fallback）——
> 與 2k-3 走出的路徑不一致時**記 gap，不得選邊**。
> `AUTHORIZED_FOR_CONTEXT` 本版**不實作**：`PSPRSMPERM`（含 `PORTAL_ISCASCADE`）只給到 permission list 層級，
> 角色／使用者／runtime portal context 皆未建模，此類問題一律回 gap。

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
-- 本節回傳的 MENUNAME 是 **technical authorization metadata**，不是導覽路徑；
-- 「某角色實際看得到哪個入口」需另外接 §2k 的 Portal Registry 入口與 CREF 權限，本節不足以回答
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

---

## 7. Schema Verification（協定角色：Legacy Contract G16）

用途：把 contract 裡的 logical Record／physical object／欄位／鍵，用**唯讀** SELECT 對照 Oracle 實況，
結果寫成 `contract-parts/verify-<RECNAME>.md` 收據（格式見 `legacy-contract-fragments.md`）。
本節樣板中 **PeopleTools 系統表以外的欄位語意（RECTYPE 代碼、USEEDIT 位元）與 Oracle 字典視圖
皆待公司機驗證**（規則 6／8）：第一次使用前先跑 `all_tab_columns` 驗欄位名，查不到記 gaps，不硬湊。

**7a. 實體物件存在與型別（OBJECT_EXISTS／OBJECT_TYPE）**

```sql
SELECT OBJECT_NAME, OBJECT_TYPE
  FROM ALL_OBJECTS
 WHERE OBJECT_NAME = :physicalObject
   AND OBJECT_TYPE IN ('TABLE', 'VIEW')
FETCH FIRST 10 ROWS ONLY
```

> 查無＝結果 `NOT_FOUND`（先確認 CURRENT_SCHEMA 步驟做了、且 `:physicalObject` 是 PSRECDEFN.SQLTABLENAME
> 或 `PS_<RECNAME>`，不要自行加減 PS_）。VIEW 對到 contract storageKind 應為 SQL_VIEW／DYNAMIC_VIEW／QUERY_VIEW。

**7b. 欄位存在與型別長度（COLUMN_EXISTS／COLUMN_TYPE）**

```sql
SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH, DATA_PRECISION, DATA_SCALE, NULLABLE
  FROM ALL_TAB_COLUMNS
 WHERE TABLE_NAME = :physicalObject
 ORDER BY COLUMN_ID
FETCH FIRST 200 ROWS ONLY
```

> 一次取整表欄位清單，逐欄對照 contract「欄位」表：缺欄＝該欄 `NOT_FOUND`；型別對映（待驗）：
> VARCHAR2→CHAR/VARCHAR、NUMBER→NUMBER/SIGNED_NUMBER、DATE→DATE、TIMESTAMP→DATETIME、CLOB→LONG_CHAR、BLOB→IMAGE。

**7c. Record 型別與實體表名（storageKind 對照，RECTYPE 值域待驗）**

```sql
SELECT RECNAME, RECTYPE, SQLTABLENAME, PARENTRECNAME
  FROM PSRECDEFN
 WHERE RECNAME = :recName
```

> RECTYPE 代碼 → storageKind 的對照表**不得憑記憶填**：第一次使用時對三個已知物件（一張 SQL Table、
> 一個 View、一個 Derived/Work）各查一次，把觀察到的代碼回填本節；回填前 storageKind 只能由 NN／程式碼證據推得。

**7d. Record 鍵（KEY_METADATA，PeopleSoft 側；USEEDIT 位元語意待驗）**

```sql
SELECT RECNAME, FIELDNAME, FIELDNUM, USEEDIT
  FROM PSRECFIELDDB
 WHERE RECNAME = :recName
 ORDER BY FIELDNUM
FETCH FIRST 200 ROWS ONLY
```

> USEEDIT 是位元遮罩；哪一位代表 Key／Alternate Search／Duplicate Order **待公司機以已知物件驗證後回填**。
> 驗證前 KEY_METADATA 收據只准寫 `keyRows` 原始值，結果欄寫 `PASS` 僅限「contract psKeys 與 FIELDNUM 順序前段一致」
> 這種弱判定；判不出寫 `BLOCKED` 不寫 PASS。

**7e. 實體唯一索引（KEY_METADATA，Oracle 側）**

```sql
SELECT I.INDEX_NAME, I.UNIQUENESS, C.COLUMN_NAME, C.COLUMN_POSITION
  FROM ALL_INDEXES I
  JOIN ALL_IND_COLUMNS C
    ON C.INDEX_OWNER = I.OWNER AND C.INDEX_NAME = I.INDEX_NAME
 WHERE I.TABLE_NAME = :physicalObject
   AND I.UNIQUENESS = 'UNIQUE'
 ORDER BY I.INDEX_NAME, C.COLUMN_POSITION
FETCH FIRST 200 ROWS ONLY
```

> PeopleSoft 通常以唯一索引 `PS_<RECNAME>` 表達鍵，不一定有 PK constraint；有 constraint 時另查
> `ALL_CONSTRAINTS`（CONSTRAINT_TYPE IN ('P','U')）＋`ALL_CONS_COLUMNS`。

**7f. 生效日查詢形狀（EFFDT_SHAPE）——只驗「查得動」，不撈資料**

```sql
SELECT COUNT(*) AS CNT
  FROM <physicalObject> A
 WHERE A.EFFDT = (SELECT MAX(B.EFFDT) FROM <physicalObject> B
                   WHERE B.<鍵1> = A.<鍵1> AND B.EFFDT <= SYSDATE)
   AND ROWNUM <= 1
```

> 有 EFFSEQ 的表再加 `AND A.EFFSEQ = (SELECT MAX(C.EFFSEQ) FROM <physicalObject> C WHERE C.<鍵1> = A.<鍵1> AND C.EFFDT = A.EFFDT)`；
> 有 EFF_STATUS 的加 `AND A.EFF_STATUS = 'A'`。只回 COUNT，不回明細（遮罩原則）。

**7g. 參考查詢可執行（REFERENCE_QUERY）**

照 contract「參考查詢」表的 SQL 原樣執行（必含 FETCH FIRST／ROWNUM 上限）；成功＝`PASS`＋關鍵列摘要（不含具名個資），
ORA- 錯誤＝`FAIL`＋錯誤碼，逾時＝`BLOCKED`。
