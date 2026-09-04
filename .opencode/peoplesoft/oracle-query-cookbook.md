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

## 連線生命週期（每次任務照此順序，硬性；2026-09-03 依實驗改版，L109）

SQLcl MCP 是**單工、有狀態**的：一個行程只有一條「目前連線」，指令依序執行。
**實驗定案（2026-09-03）**：這條連線是 MCP server 全域單例——main 與所有 subagent
共用同一個開關，任何一方 `disconnect` 就把其他人一起斷線。
因此：**連線是共用資源，誰都不准 disconnect；connect 要冪等。**

```text
1. 先直接查            → 本次任務的第一個 SELECT 直接發（連線多半已被前一個
                          委派開好）；成功＝已連線，跳到第 4 步
2. 只在回「未連線」類錯誤時
   list-connections     → 取得可用的已儲存連線名（不要自己編連線名）
   connect（帶連線名）   → 只做一次；回「已連線」也視為成功
3. 設 schema            → read customization-profile.yaml 取
                          oracle.currentSchema，執行一次
                          ALTER SESSION SET CURRENT_SCHEMA=<該值>
                          （**唯一准許的非 SELECT 語句**；重複執行無害；
                          值為 FILL_ME → 跳過此步）→ 重發第 1 步那個查詢一次
4. 查詢                 → 本次任務的查詢全部做完（裸表名即可，
                          schema 已由第 3 步解決——PeopleTools 表
                          不屬於登入帳號的 schema，漏這步會
                          view/table not found）
5. 不得 disconnect      → 連線留給下一個委派；headless 的 opencode run
                          結束時 MCP server 隨行程結束，連線自然關閉。
                          逾時、BLOCKED 回報前也一樣不斷線
```

逾時與平行規則：

```text
- connect 或任何查詢超過約 30 秒沒返回 → 停手，回報 status: BLOCKED，
  gaps 註明「oracleMCP 無回應」。
- 不准重試迴圈：卡住的呼叫重發只會排在後面繼續卡，還會佔住 server
  禍及其他 agent。
- 不要假設可以同時有第二條連線——「目前連線」是行程級全域狀態，
  交錯使用會把查詢跑在錯的連線上。
- 會查 oracleMCP 的委派同時 ≤ 3（disconnect 已對 subagent 硬性關閉後恢復；
  單一連線內 SQL 仍是排隊執行，再多只會撞 30 秒逾時）；**本批第一個 oracleMCP
  委派先單獨派**，等它回報（連線已建立）再讓其餘並行，避免同時 connect。
  純 ES＋Source 的委派不受此限。
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

**2k. Navigation Entry Discovery（Portal Registry；協定角色：ps_get_navigation_entries——issue #24）**

用途：回答「使用者從哪裡點得到這個 Component」。輸出**複數** `navigationEntries[]`，
每筆帶 `portalName / entryType / crefObjectName / labels[] / visibility`，
與 §2e 的 `technicalMenuLocations[]`（PSMENUITEM 三欄）**分開回報，永不合併**。
本節**所有表名、欄位名、代碼值域皆待公司機驗證**（規則 6／8／8a）：
PSPRSMDEFN 系列對本 cookbook 是全新表名，**第一次使用前必須先跑 2k-0**（先 `all_tables` 驗表名、
再 `all_tab_columns` 驗欄位名），查不到記 gaps，不硬湊、不自行加減 `PS_` 前綴。
驗證回填前，本節任何結論最高只能標 **INFERRED**。
`REGISTRY_DEFINED／AUTHORIZED_FOR_CONTEXT／UNKNOWN_VISIBILITY` 是**可見性**維度，與 confidence 正交，
不得寫進 confidence 欄（subagent-report-contract 硬規則 3a）。

**2k-0. 前置欄位驗證（必跑，其餘 2k-* 的前提）**

```sql
-- (1) 表名（規則 8a：樣板沒有的表先確認實際表名，禁止自行加減 PS_）
SELECT TABLE_NAME FROM ALL_TABLES
 WHERE TABLE_NAME IN ('PSPRSMDEFN','PSPRSMDEFNLANG','PSPRSMPERM','PSPRSMSYSATTRVL',
                      'PSPRSMATTRVAL','PSPRSMNAVINFO','PSPRDMDEFN','PSMENUITEM')
FETCH FIRST 20 ROWS ONLY;
-- (2) 欄位名／型別（規則 8：禁止憑記憶寫欄位名）
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, DATA_LENGTH, COLUMN_ID
  FROM ALL_TAB_COLUMNS
 WHERE TABLE_NAME IN ('PSPRSMDEFN','PSPRSMDEFNLANG','PSPRSMSYSATTRVL','PSPRDMDEFN')
 ORDER BY TABLE_NAME, COLUMN_ID
FETCH FIRST 200 ROWS ONLY;
-- (3) 代碼值域（不得憑記憶填，觀察後回填本節）
SELECT PORTAL_REFTYPE, COUNT(*) FROM PSPRSMDEFN GROUP BY PORTAL_REFTYPE;
SELECT PORTAL_CREF_USGT, COUNT(*) FROM PSPRSMDEFN WHERE PORTAL_REFTYPE = 'C'
 GROUP BY PORTAL_CREF_USGT ORDER BY 2 DESC FETCH FIRST 20 ROWS ONLY;
SELECT DISTINCT PORTAL_ATTR_NAM FROM PSPRSMSYSATTRVL ORDER BY 1 FETCH FIRST 100 ROWS ONLY;
SELECT PORTAL_NAME FROM PSPRDMDEFN ORDER BY 1 FETCH FIRST 50 ROWS ONLY;
```

> **未驗前的降級規則**：(1)(2) 任一表／欄位查無 → 該筆記 gaps，**該 2k 步驟停止**，
> 文件寫「Portal Registry 導覽入口：未確認（navigation metadata 尚未查證）」，
> **不得**退回用 PSMENUITEM 補位。`portalName` 一律由 `PSPRDMDEFN` 列舉取得，
> **禁止硬編** `EMPLOYEE／CUSTOMER／SUPPLIER／PARTNER`（後三者非普遍交付）。
> `PORTAL_CREF_USGT` 代碼→entryType 的對照（待驗）：`TARG`→PORTAL_REGISTRY、`LINK`→CREF_LINK；
> `GRPT`／`HPGT`／`HPGC`→Fluid／首頁類**本版不解析**，一律回 gap；`FRMT`／`HTMT`／`IFRM`＝模板管線，排除。
> **本環境是否只有 C／F 兩種 PORTAL_REFTYPE 亦待驗**；出現第三值＝環境意外，記 gaps 不得靜默假設。

**2k-1. Technical Menu seed（只叫 technicalMenuLocation）**

```sql
SELECT MENUNAME, BARNAME, ITEMNAME, PNLGRPNAME, MARKET
  FROM PSMENUITEM WHERE PNLGRPNAME = :componentName
FETCH FIRST 200 ROWS ONLY
```

> 本段的**唯一合法用途**是餵 2k-2 的識別三元組（menu＋component＋market）。
> `MARKET` 欄存在與否待 2k-0 驗證；查無該欄就退回 `:market='GBL'` 並記 gaps。
> 輸出欄位名一律 `technicalMenuLocations[]`，**永遠不得**輸出成 `menuPath`／選單路徑／導覽入口。

**2k-2. Portal CREF 識別（menu＋component＋market；禁止 SEG2 單欄比對）**

```sql
-- 首選：structured URI 欄位（三欄同時比對，且限定 content reference）
SELECT PORTAL_NAME, PORTAL_OBJNAME, PORTAL_CREF_USGT, PORTAL_LABEL, PORTAL_PRNTOBJNAME,
       PORTAL_URI_SEG1, PORTAL_URI_SEG2, PORTAL_URI_SEG3, PORTAL_URLTEXT, PORTAL_EXPIRE_DT
  FROM PSPRSMDEFN
 WHERE PORTAL_REFTYPE = 'C'
   AND UPPER(TRIM(PORTAL_URI_SEG1)) = UPPER(:menuName)
   AND UPPER(TRIM(PORTAL_URI_SEG2)) = UPPER(:componentName)
   AND UPPER(TRIM(PORTAL_URI_SEG3)) = UPPER(:market)
FETCH FIRST 200 ROWS ONLY;
-- 次選（structured 欄位空白時）：對 PORTAL_URLTEXT 做**整段錨定**比對，不是子字串比對
SELECT PORTAL_NAME, PORTAL_OBJNAME, PORTAL_CREF_USGT, PORTAL_LABEL, PORTAL_PRNTOBJNAME, PORTAL_URLTEXT
  FROM PSPRSMDEFN
 WHERE PORTAL_REFTYPE = 'C'
   AND UPPER(PORTAL_URLTEXT) LIKE '%/C/' || UPPER(:menuName) || '.' || UPPER(:componentName) || '.' || UPPER(:market) || '%'
FETCH FIRST 200 ROWS ONLY
```

> **硬性禁止**：`LIKE '%' || :componentName || '%'`、只比 `PORTAL_URI_SEG2`、憑欄位位置猜 SEG 語意。
> 理由：同一 Component 會登在多個 menu、多個 market、多個 portal；SEG 只在
> **component 型 CREF**（URL 文法 `/c/<MENU>.<COMPONENT>.<MARKET>`）才是 menu／component／market，
> `q/`（Query）、`s/`（iScript）、`w/`（Worklist）與外部 URL CREF 的 SEG 語意不同——判不出即 `entryType=UNKNOWN`。
> 次選路徑的每一筆結論標記 `confidence=INFERRED`（來源＝URLTEXT 文法解析），**不得標 CONFIRMED**。
> 少於三欄命中的匹配只能回 `PARTIAL_IDENTITY_MATCH` 並記 gaps。
> `PORTAL_EXPIRE_DT < SYSDATE` 的 CREF：入口仍列出，但 `visibility` 降為 `UNKNOWN_VISIBILITY` 並記 gap
> （「valid-from」對應欄位名未證實，**不得**憑記憶寫 `PORTAL_EFFDT`）。

**2k-3. 沿 parent 往上組路徑（visited／depth cap／不跨 Portal）**

```sql
SELECT LEVEL AS LVL, PORTAL_NAME, PORTAL_REFTYPE, PORTAL_OBJNAME,
       PORTAL_PRNTOBJNAME, PORTAL_LABEL, PORTAL_SEQ_NUM
  FROM PSPRSMDEFN
 START WITH PORTAL_NAME = :portalName
        AND PORTAL_REFTYPE = 'C'
        AND PORTAL_OBJNAME = :crefObjName
CONNECT BY NOCYCLE PRIOR PORTAL_PRNTOBJNAME = PORTAL_OBJNAME
        AND PRIOR PORTAL_NAME = PORTAL_NAME
        AND LEVEL <= 20
 ORDER BY LVL DESC
FETCH FIRST 200 ROWS ONLY
```

> `NOCYCLE` ＋ `LEVEL <= 20` ＝ visited／深度上限（**cycle 不得 doom-loop**）；
> `AND PRIOR PORTAL_NAME = PORTAL_NAME` 寫在 `CONNECT BY` 內才擋得住跨 Portal（寫在外層 WHERE 只過濾輸出、擋不住走訪）。
> **終止判定**：最後一列 `PORTAL_OBJNAME = 'PORTAL_ROOT_OBJECT'`（或其 parent 為空）＝走到根，路徑完整；
> 撞到 LEVEL 20、或某段 parent 指向不存在的列（鏈提早斷）→ 該入口 `visibility=UNKNOWN_VISIBILITY`、
> 路徑標 `UNRESOLVED` 並記 gap；**絕不得**用物件名、delivered 慣例或印象補上缺掉的段。
> 每段另查一次隱藏旗標（欄位不存在＝attribute 列，不是 PSPRSMDEFN 的欄位）：
> `SELECT PORTAL_OBJNAME, PORTAL_ATTR_VAL FROM PSPRSMSYSATTRVL WHERE PORTAL_NAME = :portalName AND PORTAL_ATTR_NAM = 'PORTAL_HIDE_FROM_NAV' AND PORTAL_OBJNAME IN (<ancestor list>) FETCH FIRST 100 ROWS ONLY;`
> ——**任一祖先** `= 'Y'` ＝整條分支在左側導覽看不到 → `visibility=UNKNOWN_VISIBILITY`＋gap。
> 平台可攜性：非 Oracle 環境改用遞迴 CTE＋顯式 depth 計數＋visited 反連接，行為必須完全一致（待驗）。

**2k-4. 語系 label（base＋override＋fallback，逐段記來源）**

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

**2k-5. CREF Link 與其他入口 surface（複數入口；未支援者一律回 gap）**

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
 GROUP BY PORTAL_CREF_USGT;
SELECT PORTAL_OBJNAME, PORTAL_LABEL FROM PSPRSMDEFN
 WHERE PORTAL_REFTYPE = 'F'
   AND (UPPER(PORTAL_LABEL) LIKE '%FLUID%' OR UPPER(PORTAL_LABEL) LIKE '%NAVIGATION COLLECTION%')
FETCH FIRST 50 ROWS ONLY
```

> **每個 CREF 列只有一個 parent**（`PORTAL_PRNTOBJNAME` 單值）⇒ 一列＝一條路徑。
> 複數入口來自**多個 CREF 列**（1 個 TARG ＋ N 個 LINK），因此模型是「N 個錨點 × 各走一次 2k-3」，
> **不是**「一個錨點走出多條路徑」。每個 location 分開回傳、各自帶自己的 labels 與 visibility；
> 壓成單一路徑＝`SINGLE_PATH_COLLAPSE`。
> 探測 (1) 若 LINK 列帶 URI 三段 ⇒ 2k-2 的識別查詢已同時撈到 TARG 與 LINK，無需第二跳；
> 若不帶 ⇒ 需要一次「LINK → 目標 CREF」解析跳，該跳同樣要 visited set ＋ depth cap（link→link→link 不得成環），
> **在探測回填前，多入口宣稱一律附 gap「alternate entries not fully resolved」**。
> 破損 link（指向不存在的 CREF）＝該筆 `UNRESOLVED`＋gap，不猜目標。
> **Fluid Tile／NavBar／Navigation Collection 本版一律不解析**：
> (2) 有命中＝`entryType=FLUID_TILE／UNKNOWN`＋`visibility=UNKNOWN_VISIBILITY`＋gap；
> **(2) 零命中也必須回 gap**「alternate navigation surfaces not fully inspected」
> ——沒有 Fluid CREF 列不證明沒有 Fluid 入口，**永遠不得宣稱「唯一入口」**。
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

## 7. Schema Verification（協定角色：Legacy Contract G16——issue #17 Phase 1）

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
