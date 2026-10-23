# Oracle Query Cookbook（oracleMCP 查詢樣板）

`oracleMCP` 是唯讀的 Oracle 查詢 MCP（@vdeserto/oracle-mcp-server），連 PeopleSoft 資料庫。
本手冊提供各**協定角色**對應的 PeopleTools metadata 查詢樣板——
需要查 metadata 時**照抄樣板帶入參數**，不要自己發明 SQL。

## 使用規則（硬性）

```text
1. 只允許 SELECT。禁止 INSERT / UPDATE / DELETE / MERGE / DDL / PL/SQL 匿名區塊。
1a. **表名一律帶擁有者前綴**（唯讀帳號只查得到 `擁有者.表名`）：`<schema>`＝customization-profile.yaml 的
   oracle.currentSchema（原樣照抄、不加引號）。本手冊樣板已寫成 `<schema>.表名`，照抄時把 `<schema>` 換成該值；
   自己組的查詢（實體表 PS_<RECNAME>、Prompt 表、規則 8 驗過欄位後的查詢）每個 FROM／JOIN／子查詢的 PeopleSoft 表與 view 也一樣帶。
   DUAL 與 ALL_ 開頭的資料字典（ALL_TABLES／ALL_TAB_COLUMNS／ALL_OBJECTS）不加前綴；查資料字典改加 OWNER = UPPER('<schema>') 條件。
   值為 FILL_ME → 拿掉 `<schema>.` 與 OWNER 條件，用裸表名。不執行 ALTER SESSION（唯讀帳號不准，表名帶前綴就不需要）。
2. 每個查詢都要有列數上限：加 FETCH FIRST 200 ROWS ONLY（或 ROWNUM <= 200），呼叫時 `limit` 帶同一個數
   （沒帶 limit 工具只回 50 列；limit 最大 500）。
3. 可能高基數的查詢（值清單、使用者清單）先跑 COUNT(*)，超過 200 只回彙總。
4. 使用者層級資料只回彙總（COUNT / 角色名），不列具名清單（遮罩原則）。
5. 查詢結果屬 metadata evidence：報告引用時附上「用的 SQL + 關鍵列」。
6. 下列表名 / 欄位為 PeopleTools 8.5x 常見結構；實際環境第一次使用前
   先驗證（查不到表 / 欄位時記入 gaps，不要瞎改表名硬湊）。
7. 查詢工具是 `oracleMCP_oracle_execute_query`（參數 `sql`、`limit`、`response_format`；只收 SELECT）。
   同一個 MCP 的 oracle_list_schemas／oracle_list_tables／oracle_describe_table／oracle_get_table_data 已關閉、不用；
   沒有 connect／disconnect——連哪個資料庫、用哪個帳號由 oracleMCP 的設定決定，查詢直接送。
7a. **通道前置檢查（L103）**：可用工具清單裡**一個 `oracleMCP_` 前綴
   工具都沒有**＝oracleMCP 掛載故障（OpenCode 到 MCP server 的 client／transport／工具目錄失效；
   管理者在該視窗 `/mcps` 對 oracleMCP disconnect→connect 可恢復，SOP-21）。**不是工具名記錯**：
   不猜名、不換拼法重試（實案：模型自創 `oracle_sql_run` 反覆撞牆到被 doom_loop 攔截）。
   處置：**立即回報 FAIL(ORACLE_MCP_DOWN) 並結束本委派**；恢復後先送 SELECT 1 AS OK FROM DUAL 驗證，不沿用舊 DOWN 結論。
   **換路查可以、冒充不行**：ES／Source／metadata MCP 有等價線索
   （程式碼、註解、metadata 定位）照常可查——但產物**只能以
   INFERRED＋CHUNK 證據**入報告，並記「DB 實際狀態待通道恢復驗證」；
   **不得**寫成 SQL 型證據（DB 狀態事實只有可重跑的 SELECT 驗得動，
   chunk 只能證明程式碼怎麼寫）、不得憑它宣稱查無、
   原 SQL 型待辦不因此視為完成。
7b. **送出前的 SQL 形狀**（oracleMCP 在執行前檢查，不符就回 `Error:` 開頭的拒絕訊息、不執行）：
   - 一次只送一句：整段不得出現分號 `;`（字串裡也不行、結尾不加）。本手冊一個 sql 區塊＝一句。
   - 不得有註解：`--` 與 `/*` 在任何位置都不行（字串裡也不行）。說明寫在 SQL 外面。
   - 開頭必須是 SELECT 或 WITH；SELECT 後面不得出現 INTO 這個字；不得有 FOR UPDATE。
   - 整段文字（含字串常值、別名）不得出現這些字（整個字比對、大小寫不分）：INSERT、UPDATE、DELETE、MERGE、UPSERT、
     DROP、CREATE、ALTER、TRUNCATE、RENAME、COMMENT、GRANT、REVOKE、EXECUTE、EXEC、CALL、ANYDATA、XMLTYPE；
     也不得含 DBMS_、UTL_、OWA_、XMLDB、XDB_、CTXSYS、HTTPURITYPE、URIFACTORY（子字串比對）。
     例：字串 `'Drop-Down'`、`'Update/Display'` 會被擋；`AUTO_UPDATE`、`LASTUPDDTTM`、`UPDATE_DISPLAY` 不會。
     CLOB 取片段用 `TO_CHAR(SUBSTR(欄, 1, n))`（不用 DBMS_LOB）。
     要找原始碼裡的 DML 字（例：誰 UPDATE 某表）→ 走 ES＋Source，不在 oracleMCP 的 SQL 裡寫這些字；
     表名或欄位名本身就是上列的字 → 這句送不出去，記 gaps。
   - 輸出欄名不得重複：工具把整句包成 `SELECT * FROM (<SQL>) FETCH FIRST <limit> ROWS ONLY` 再執行，
     兩欄同名（例：A.FIELDNAME 與 B.FIELDNAME）就失敗——同名欄一律加 AS 別名，運算式欄也加別名。
   - 樣板的 `:參數` 一律換成實際值（字串加單引號、數字直接寫）再送，送出的 SQL 不留 `:參數`，不用 binds。
   - 重跑文件裡的 SQL 證據：去掉結尾分號與註解、多句拆開逐句送，其他部分照原樣。
7c. **回覆怎麼讀**：
   - 成功＝markdown 表格，第一行 `**N linha(s) retornada(s)**`（N＝回傳列數）；0 列＝`Nenhum resultado encontrado.`。
   - 回傳列數＝`limit` → 可能還有：照該節的續查規則分批或加條件縮小，不得當成全部。
   - 結尾有 `[truncado` → 輸出超過約 25,000 字被截斷：減少欄位或分批再查，不得引用被截掉的部分。
   - 查 CLOB／長文字欄（內容可能換行）時 `response_format` 用 `json`：markdown 表格遇到換行會斷列。
   - 錯誤一律是一行 `Error: …`（不含原始 ORA 訊息），處置見下方「連線與錯誤處理」。
8. **查詢前欄位驗證**：要用「樣板裡沒有的
   欄位名」或不確定欄位存不存在時，先跑
   SELECT column_name FROM all_tab_columns WHERE owner = UPPER('<schema>') AND table_name='<大寫表名>'
   確認後再查——**禁止憑記憶寫欄位名**；驗證後仍無該欄位 →
   記 gaps，不要換個猜法再試。
8a. **表名同理，且禁止自行加減 `PS_` 前綴**：PeopleTools 系統表
   **不一定**有 PS_ 前綴——本 cookbook 樣板即並存兩型
   （`PSPRCSRQST` 無前綴、`PS_PRCSRECUR` 有前綴）。**樣板怎麼寫就怎麼查**；
   樣板沒有的表先跑
   SELECT table_name FROM all_tables WHERE owner = UPPER('<schema>') AND table_name LIKE '%<關鍵字>%'
   確認實際表名。**「加了 `PS_` 前綴查不到」不是資料不存在，是表名寫錯。**
9. **metadata MCP 不得作 evidence**：
   PeoplecodeMetadata 的工具（find_field_usage／search_component_metadata／
   get_ae_sql_metadata／**get_process_schedule_list**）回傳一律只作
   **定位線索**——證據契約只認 CHUNK 與 SQL 兩種。排程／metadata 類事實
   要當證據，就得用本 cookbook 的 SELECT 取得並附「SQL＋關鍵列」。
```

## 連線與錯誤處理（硬性）

oracleMCP 連的資料庫與帳號由 MCP 的設定（環境變數）決定，沒有 connect／disconnect 可呼叫；每次查詢自己取連線、查完歸還，
沒有「目前連線」要維護，也不會有人把別人斷線。

**主 agent（ps-orchestrator／ps-deep-research／ps-audit-orchestrator）——不查 DB（oracleMCP 工具全關），沒有開線步驟**：

```text
1. 會查 DB 的工作一律委派查詢 subagent（ps-ui-flow／ps-metadata-flow／ps-ae-flow／ps-auditor），派之前不必做任何連線動作
2. subagent 回 BLOCKED(NOT_CONNECTED) → 收齊本批受影響的委派後重派一次（只一次）；第二次仍 NOT_CONNECTED →
   對使用者／收據如實寫「DB 連線失敗（<報告裡 oracleMCP 回的 Error 原文>）——請管理者依 SOP-21 檢查 oracleMCP 的連線設定」，
   本題／本批不再派會查 DB 的委派，不得說成「DB 通道忙碌」
3. subagent 回 ORACLE_MCP_DOWN ≠ NOT_CONNECTED：不重派會查 DB 的委派，如實回報並交管理者依 SOP-21 重掛（規則 7a）
4. 執行期 guard（ps-runtime-guard）只擋一件事：task 的 subagent_type 是 skill 名（PS_TASK_TARGET_INVALID）。派工順序不靠它
```

**subagent（ps-ui-flow／ps-metadata-flow／ps-ae-flow／ps-auditor）——每次委派**：

```text
0. 工具清單裡沒有 oracleMCP_oracle_execute_query → status=BLOCKED、blockedReason=ORACLE_MCP_DOWN（規則 7a），結束本委派
1. 取前綴              → read customization-profile.yaml 取 oracle.currentSchema；本次每個查詢的 `<schema>` 都換成這個值
                          （規則 1a）。值為 FILL_ME → 拿掉 `<schema>.` 前綴與 OWNER 條件，用裸表名
2. 直接送本次任務的第一個 SELECT（規則 7b 的形狀、帶 limit；表名已帶前綴）
3. 依回覆處理（每種錯誤只修一次、重送一次；同一句修過仍錯 → 記 gaps 寫 SQL 與錯誤原文，不換表名、欄位名硬湊）：
   Error: Table or view does not exist.
                        → 逐一檢查 FROM／JOIN／子查詢的 PeopleSoft 表都寫成 `<schema>.表名`、`<schema>` 已換成 profile 值
                          （規則 1a），補齊後重送；補齊仍查不到 → 表名不對或唯讀帳號沒有這張表的權限，記 gaps（寫表名）。
                          值為 FILL_ME 而查不到表 → blockedReason=SCHEMA_UNRESOLVED，不是 NOT_CONNECTED
   Error: Invalid column name.        → 規則 8 驗欄位後重送
   Error: Insufficient privileges.    → 唯讀帳號沒有這張表的權限：記 gaps（寫表名），不重送
   Error: SQL command not properly ended.／Error: Missing expression in SQL.
                                      → SQL 語法錯：改好重送
   其他葡萄牙文的拒絕訊息（Múltiplos statements／Comentários SQL／Somente SELECT／Operação proibida／FOR UPDATE／SELECT INTO）
                                      → SQL 形狀不符規則 7b：照規則改好重送
   Error: Query timed out. …          → status: BLOCKED、blockedReason=QUERY_TIMEOUT（該節另有逾時規則的照該節）
   Error: Authentication failed.／Error: Cannot reach database …／Error: Cannot resolve Oracle connection identifier.
                                      → DB 連不上：blockedReason=NOT_CONNECTED，gaps 寫錯誤原文，結束本委派
   Error: Database query failed.（不說原因）
                                      → 先送 SELECT 1 AS OK FROM DUAL（limit 1）：也失敗＝DB 連不上 → blockedReason=NOT_CONNECTED，
                                        結束本委派；成功＝這句 SQL 本身的問題（多半是輸出欄名重複、型別不合、括號）→ 照規則 7b 檢查、修一次重送
4. 查詢                 → 本次任務的查詢全部做完（PeopleSoft 表名都帶 `<schema>.` 前綴）
5. 不執行 ALTER SESSION（會被擋，表名帶前綴就不需要）
```

逾時與平行規則：

```text
- 單一查詢上限 30 秒（server 端），逾時回 Error: Query timed out.；同一句不准原樣重送迴圈。
- 每個委派一次只送一句、等回覆再送下一句（不並行呼叫 oracleMCP）。
- 會查 oracleMCP 的委派同時 ≤ 3（server 最多 5 條連線、排隊等 10 秒就放棄）；純 ES＋Source 的委派不受此限。
```

## Effective Date 標準樣式（有 EFFDT 的表都要套；以下是接在 WHERE 後面的片段，不單獨送）

```text
AND A.EFF_STATUS = 'A'
AND A.EFFDT = (SELECT MAX(B.EFFDT) FROM <schema>.<同表> B
                WHERE B.<同鍵> = A.<同鍵> AND B.EFFDT <= SYSDATE)
```

---

## 1. Object Origin（協定角色：ps_get_object_origin）

Prefix 判斷不用 SQL（比對 customization-profile 的 customPrefixes）。SQL 補兩件事：

**1a. 客製登錄（CUSTOM_REGISTRY）— 物件是否在客製 Project 內**

```sql
SELECT PROJECTNAME, OBJECTTYPE, OBJECTVALUE1
  FROM <schema>.PSPROJECTITEM
 WHERE OBJECTVALUE1 = :objectName
FETCH FIRST 50 ROWS ONLY
```

> 客製 Project 清單 / 自訂登錄表依環境而定（customization-profile 的
> customObjectRegistry），有專屬登錄表時改查該表。

**1b. MODIFIED_DELIVERED 啟發式 — 原生名稱但被改過**

```sql
SELECT RECNAME, LASTUPDOPRID, LASTUPDDTTM
  FROM <schema>.PSRECDEFN
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
  FROM <schema>.PSXLATITEM A
  LEFT JOIN <schema>.PSXLATITEMLANG L
    ON L.FIELDNAME = A.FIELDNAME AND L.FIELDVALUE = A.FIELDVALUE
   AND L.EFFDT = A.EFFDT AND L.LANGUAGE_CD = 'ZHT'
 WHERE A.FIELDNAME = :fieldName
   AND A.EFF_STATUS = 'A'
   AND A.EFFDT = (SELECT MAX(B.EFFDT) FROM <schema>.PSXLATITEM B
                   WHERE B.FIELDNAME = A.FIELDNAME
                     AND B.FIELDVALUE = A.FIELDVALUE AND B.EFFDT <= SYSDATE)
FETCH FIRST 100 ROWS ONLY
```

**2b. 由選項文字反查欄位（「免役是哪個欄位的值？」）**

```sql
SELECT L.FIELDNAME, L.FIELDVALUE, L.XLATLONGNAME
  FROM <schema>.PSXLATITEMLANG L
 WHERE L.LANGUAGE_CD = 'ZHT' AND L.XLATLONGNAME LIKE '%' || :displayText || '%'
FETCH FIRST 50 ROWS ONLY
```

**2c. 欄位 Label（含中文）**

```sql
SELECT A.FIELDNAME, A.LABEL_ID, A.LONGNAME, A.DEFAULT_LABEL, L.LONGNAME AS ZHT
  FROM <schema>.PSDBFLDLABL A
  LEFT JOIN <schema>.PSDBFLDLABLLANG L
    ON L.FIELDNAME = A.FIELDNAME AND L.LABEL_ID = A.LABEL_ID
   AND L.LANGUAGE_CD = 'ZHT'
 WHERE A.FIELDNAME = :fieldName
```

反查：`WHERE L.LANGUAGE_CD='ZHT' AND L.LONGNAME LIKE '%'||:text||'%'`。

**2d. Page 上有哪些欄位（Page → Record.Field）**

```sql
SELECT PNLNAME, FIELDNUM, RECNAME, FIELDNAME, FIELDTYPE, LBLTYPE, LABEL_ID
  FROM <schema>.PSPNLFIELD
 WHERE PNLNAME = :pageName
FETCH FIRST 200 ROWS ONLY
```

反查欄位在哪些 Page：`WHERE RECNAME = :rec AND FIELDNAME = :fld`。

**2e. Component ↔ Page ↔ Menu**

Component 含哪些 Page：

```sql
SELECT PNLGRPNAME, PNLNAME, ITEMLABEL FROM <schema>.PSPNLGROUP WHERE PNLGRPNAME = :componentName
```

Page 屬於哪些 Component：

```sql
SELECT PNLGRPNAME FROM <schema>.PSPNLGROUP WHERE PNLNAME = :pageName
```

Component 掛在哪些 Menu（**technicalMenuLocation**：App Designer 技術選單 metadata，
8.4 之後 BARNAME（USE／PROCESS／INQUIRE…）在 PIA 沒有對應層級——**不得串成使用者導覽路徑**；
使用者看得到的入口走 §2k Portal Registry。本段亦是 §2k-2 的 seed（menu＋component＋market）：

```sql
SELECT MENUNAME, BARNAME, ITEMNAME FROM <schema>.PSMENUITEM WHERE PNLGRPNAME = :componentName
```

**2f. Prompt Table 與基數**

```sql
SELECT RECNAME, FIELDNAME, EDITTABLE
  FROM <schema>.PSRECFIELDDB
 WHERE RECNAME = :recName AND FIELDNAME = :fieldName
```

先估基數再決定要不要列值（實體表名：SQLTABLENAME 空白時為 PS_<RECNAME>）：

```sql
SELECT COUNT(*) AS CNT FROM <schema>.PS_<EDITTABLE>
```

**2g. 選項使用實況（「哪些選項還在用？」）**

各值的實際資料分布（只回彙總，不撈明細；實體表名規則見 §6）：

```sql
SELECT <FIELDNAME>, COUNT(*) AS CNT
  FROM <schema>.PS_<RECNAME>
 GROUP BY <FIELDNAME>
 ORDER BY CNT DESC
FETCH FIRST 50 ROWS ONLY
```

含停用的完整選項清單（判斷廢棄選項時不要過濾 EFF_STATUS）：

```sql
SELECT A.FIELDVALUE, A.EFF_STATUS, A.EFFDT, A.XLATLONGNAME
  FROM <schema>.PSXLATITEM A
 WHERE A.FIELDNAME = :fieldName
   AND A.EFFDT = (SELECT MAX(B.EFFDT) FROM <schema>.PSXLATITEM B
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
  FROM <schema>.PSPNLFIELD
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
  FROM <schema>.PSPNLFIELD
 WHERE PNLNAME = :pageName
   AND PNLFLDID <> :groupBoxId
   AND FIELDLEFT >= :groupLeft AND FIELDRIGHT <= :groupRight
   AND FIELDTOP >= :groupTop AND FIELDBOTTOM <= :groupBottom
 ORDER BY FIELDNUM
FETCH FIRST 200 ROWS ONLY
```

**2j. Subpage 展開與向上解析**

展開：Subpage 內有哪些控制項（結果中 FIELDTYPE=11 者以其 SUBPNLNAME 遞迴展開）：

```sql
SELECT PNLNAME, PNLFLDID, FIELDNUM, FIELDTYPE, PNLFIELDNAME,
       RECNAME, FIELDNAME, SUBPNLNAME, LBLTEXT, OCCURSLEVEL
  FROM <schema>.PSPNLFIELD
 WHERE PNLNAME = :subpageName
 ORDER BY FIELDNUM
FETCH FIRST 200 ROWS ONLY
```

向上：這個 Subpage 被哪些 Page 掛載。PSPNLGROUP 只登記真正的 Page——
變異目標長在 Subpage 上時，先向上找到掛載 Page（必要時遞迴），才能用 §2e 對映 Component：

```sql
SELECT PNLNAME FROM <schema>.PSPNLFIELD
 WHERE SUBPNLNAME = :subpageName AND FIELDTYPE = 11
FETCH FIRST 50 ROWS ONLY
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

(1) 表名（規則 8a：樣板沒有的表先確認實際表名，禁止自行加減 PS_）：

```sql
SELECT TABLE_NAME FROM ALL_TABLES
 WHERE TABLE_NAME IN ('PSPRSMDEFN','PSPRSMDEFNLANG','PSPRSMPERM','PSPRSMSYSATTRVL',
                      'PSPRSMATTRVAL','PSPRSMNAVINFO','PSPRDMDEFN','PSMENUITEM','PSOPTIONS')
   AND OWNER = UPPER('<schema>')
FETCH FIRST 20 ROWS ONLY
```

(2) 欄位名／型別（規則 8：禁止憑記憶寫欄位名）：

```sql
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, DATA_LENGTH, COLUMN_ID
  FROM ALL_TAB_COLUMNS
 WHERE TABLE_NAME IN ('PSPRSMDEFN','PSPRSMDEFNLANG','PSPRSMSYSATTRVL','PSPRDMDEFN','PSMENUITEM','PSOPTIONS')
   AND OWNER = UPPER('<schema>')
 ORDER BY TABLE_NAME, COLUMN_ID
FETCH FIRST 200 ROWS ONLY
```

(2b) base language（決定 2k-4 的 fallbackLanguageCode；不得憑 delivered convention 填 ENG）——表名／欄位同樣先看 (1)(2) 有沒有列出：

```sql
SELECT LANGUAGE_CD FROM <schema>.PSOPTIONS FETCH FIRST 1 ROWS ONLY
```

(3) 代碼值域（不得憑記憶填，觀察後回填本節）。必須在讀完 (1)(2) 回傳之後才發：(1) 未列出的表、(2) 未列出的欄位，
其對應的 (3) 查詢直接跳過並記 gap。以下四句逐句送：

```sql
SELECT PORTAL_REFTYPE, COUNT(*) AS CNT FROM <schema>.PSPRSMDEFN GROUP BY PORTAL_REFTYPE FETCH FIRST 20 ROWS ONLY
```

```sql
SELECT PORTAL_CREF_USGT, COUNT(*) AS CNT FROM <schema>.PSPRSMDEFN WHERE PORTAL_REFTYPE = 'C'
 GROUP BY PORTAL_CREF_USGT ORDER BY 2 DESC FETCH FIRST 20 ROWS ONLY
```

```sql
SELECT DISTINCT PORTAL_ATTR_NAM FROM <schema>.PSPRSMSYSATTRVL ORDER BY 1 FETCH FIRST 100 ROWS ONLY
```

```sql
SELECT PORTAL_NAME FROM <schema>.PSPRDMDEFN ORDER BY 1 FETCH FIRST 50 ROWS ONLY
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
           (SELECT TRIM(L.PORTAL_LABEL) FROM <schema>.PSPRSMDEFNLANG L
             WHERE L.PORTAL_NAME = D.PORTAL_NAME AND L.PORTAL_REFTYPE = D.PORTAL_REFTYPE
               AND L.PORTAL_OBJNAME = D.PORTAL_OBJNAME AND L.LANGUAGE_CD = :languageCd) AS LANG_LABEL,
           CASE WHEN EXISTS (SELECT 1 FROM <schema>.PSPRSMSYSATTRVL A
                              WHERE A.PORTAL_NAME = D.PORTAL_NAME AND A.PORTAL_REFTYPE = D.PORTAL_REFTYPE
                                AND A.PORTAL_OBJNAME = D.PORTAL_OBJNAME AND A.PORTAL_ATTR_NAM = 'PORTAL_HIDE_FROM_NAV'
                                AND UPPER(TRIM(TO_CHAR(SUBSTR(A.PORTAL_ATTR_VAL, 1, 100)))) IN ('TRUE','Y','1'))
                THEN 1 ELSE 0 END AS IS_HIDDEN,
           CASE WHEN D.PORTAL_EXPIRE_DT IS NOT NULL AND D.PORTAL_EXPIRE_DT < SYSDATE THEN 1 ELSE 0 END AS IS_EXPIRED,
           CASE WHEN D.PORTAL_OBJNAME = 'PORTAL_ROOT_OBJECT' OR TRIM(D.PORTAL_PRNTOBJNAME) IS NULL THEN 1 ELSE 0 END AS IS_ROOT,
           CONNECT_BY_ISCYCLE                 AS IS_CYCLE
      FROM <schema>.PSPRSMDEFN D
     START WITH D.PORTAL_REFTYPE = 'C'
            AND D.PORTAL_CREF_USGT IN ('TARG','LINK')
            AND D.PORTAL_NAME = :portalName
            AND UPPER(TRIM(D.PORTAL_URI_SEG2)) = UPPER(:componentName)
            AND EXISTS (SELECT 1 FROM <schema>.PSMENUITEM M
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
  FROM <schema>.PSMENUITEM WHERE PNLGRPNAME = :componentName
FETCH FIRST 200 ROWS ONLY
```

> 本段的**唯一合法用途**是識別 seed（menu＋component；`navigation.identity: MENU_COMPONENT_MARKET` 的環境才加 market）
> 與報告的 `technicalMenuLocations[]`。`MARKET` 欄只在 identity 含 MARKET 時才查；欄位由 2k-0 (2) 驗證，未列出就不查——**不得**先查再等 ORA-00904。
> 輸出欄位名一律 `technicalMenuLocations[]`，**永遠不得**輸出成 `menuPath`／選單路徑／導覽入口。

**2k-2. Portal CREF 識別（診斷用：§2k-C 回 0 列時排查；identity 含 MARKET 時才比 SEG3）**

首選：structured URI 欄位（三欄同時比對，且限定 content reference）。最後一行 SEG3 條件只在
identity=MENU_COMPONENT_MARKET 時保留：

```sql
SELECT PORTAL_NAME, PORTAL_OBJNAME, PORTAL_CREF_USGT, PORTAL_LABEL, PORTAL_PRNTOBJNAME,
       PORTAL_URI_SEG1, PORTAL_URI_SEG2, PORTAL_URI_SEG3, PORTAL_URLTEXT, PORTAL_EXPIRE_DT
  FROM <schema>.PSPRSMDEFN
 WHERE PORTAL_REFTYPE = 'C'
   AND UPPER(TRIM(PORTAL_URI_SEG1)) = UPPER(:menuName)
   AND UPPER(TRIM(PORTAL_URI_SEG2)) = UPPER(:componentName)
   AND UPPER(TRIM(PORTAL_URI_SEG3)) = UPPER(:market)
FETCH FIRST 200 ROWS ONLY
```

次選（structured 欄位空白時）：對 PORTAL_URLTEXT 做**整段錨定**比對，不是子字串比對：

```sql
SELECT PORTAL_NAME, PORTAL_OBJNAME, PORTAL_CREF_USGT, PORTAL_LABEL, PORTAL_PRNTOBJNAME, PORTAL_URLTEXT, PORTAL_EXPIRE_DT
  FROM <schema>.PSPRSMDEFN
 WHERE PORTAL_REFTYPE = 'C'
   AND UPPER(PORTAL_URLTEXT) LIKE '%/C/' || UPPER(:menuName) || '.' || UPPER(:componentName) || '.' || UPPER(:market) || '%'
FETCH FIRST 200 ROWS ONLY
```

（避免 `_` 被 LIKE 當單字元萬用字元時，LIKE 那行改成
`AND INSTR(UPPER(PORTAL_URLTEXT), '/C/' || UPPER(:menuName) || '.' || UPPER(:componentName) || '.' || UPPER(:market)) > 0`。）

診斷（前兩條皆 0 列時才跑）：menu＋component 命中但 market 不符／空白 ⇒ PARTIAL_IDENTITY_MATCH（永不 CONFIRMED）：

```sql
SELECT PORTAL_NAME, PORTAL_OBJNAME, PORTAL_CREF_USGT, PORTAL_LABEL, PORTAL_PRNTOBJNAME,
       PORTAL_URI_SEG1, PORTAL_URI_SEG2, PORTAL_URI_SEG3, PORTAL_URLTEXT, PORTAL_EXPIRE_DT
  FROM <schema>.PSPRSMDEFN
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
  FROM <schema>.PSPRSMDEFN
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
> `SELECT PORTAL_OBJNAME FROM <schema>.PSPRSMSYSATTRVL WHERE PORTAL_NAME = :portalName AND PORTAL_REFTYPE = 'F' AND PORTAL_ATTR_NAM = 'PORTAL_HIDE_FROM_NAV' AND UPPER(TRIM(TO_CHAR(SUBSTR(PORTAL_ATTR_VAL, 1, 100)))) IN ('TRUE','Y','1') AND PORTAL_OBJNAME IN (<ancestor list>) FETCH FIRST 100 ROWS ONLY`
> ——target CREF 或**任一祖先**命中 ＝ 整條路徑在 Classic 選單看不到 → canonical 不回該列（診斷形 `PATH_HIDDEN=1`），gaps 記一行。
> 同理，target 或**任一祖先** `PORTAL_EXPIRE_DT < SYSDATE` → canonical 不回該列（診斷形 `PATH_EXPIRED=1`），gaps 記一行。
> 平台可攜性：非 Oracle 環境改用遞迴 CTE＋顯式 depth 計數＋visited 反連接，行為必須完全一致（待驗）。

**2k-4. 語系 label（§2k-C 已內含：`:languageCd`＝profile `navigation.labelLanguage`；本段為逐段來源說明）**

```sql
SELECT D.PORTAL_OBJNAME,
       D.PORTAL_LABEL AS BASE_LABEL,
       L.PORTAL_LABEL AS LANG_LABEL,
       COALESCE(NULLIF(TRIM(L.PORTAL_LABEL), ''), D.PORTAL_LABEL) AS DISPLAY_TEXT
  FROM <schema>.PSPRSMDEFN D
  LEFT JOIN <schema>.PSPRSMDEFNLANG L
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

(1) LINK 的指向機制**未證實**，先探測：LINK 列是否也帶 URI 三段？

```sql
SELECT PORTAL_NAME, PORTAL_OBJNAME, PORTAL_CREF_USGT,
       PORTAL_URI_SEG1, PORTAL_URI_SEG2, PORTAL_URI_SEG3, PORTAL_URLTEXT, PORTAL_PRNTOBJNAME
  FROM <schema>.PSPRSMDEFN
 WHERE PORTAL_REFTYPE = 'C' AND PORTAL_CREF_USGT = 'LINK'
FETCH FIRST 20 ROWS ONLY
```

(2) 其他 surface 是否存在（存在與否都要回 gap，見下），兩句逐句送：

```sql
SELECT PORTAL_CREF_USGT, COUNT(*) AS CNT FROM <schema>.PSPRSMDEFN
 WHERE PORTAL_REFTYPE = 'C' AND PORTAL_CREF_USGT IN ('GRPT','HPGT','HPGC')
 GROUP BY PORTAL_CREF_USGT FETCH FIRST 20 ROWS ONLY
```

```sql
SELECT PORTAL_OBJNAME, PORTAL_LABEL FROM <schema>.PSPRSMDEFN
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

**2l. 畫面元件與設計期屬性（一個 Page 一次；NN「## 畫面元件」與「這個欄位是什麼元件、唯讀嗎、必填嗎、查值查哪裡」）**

只列綁欄位的元件、按鈕／連結、Grid（含 Tab Separator）、Scroll Area、Scroll Bar、HTML Area、Subpage、Secondary Page；
Static Text、Frame、Group Box、Static Image、Horizontal Rule 不列（Group Box 的顯示條件走 §2h～§2i）。一次最多 40 列：回滿 40 列 → `:afterFieldNum` 換成最後一列的
FIELDNUM 再跑一次，直到不滿 40 列（第一次填 0）。

```sql
SELECT P.FIELDNUM, P.OCCURSLEVEL AS LVL, P.FIELDTYPE AS CODE,
       CASE P.FIELDTYPE WHEN 4 THEN 'Edit Box' WHEN 5 THEN 'DropDown List Box' WHEN 6 THEN 'Long Edit Box'
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
       CASE WHEN BITAND(P.FIELDUSE, 16) > 0 THEN P.ASSOCFIELDNUM + 1 END AS RELATED_TO,
       CASE WHEN BITAND(P.FIELDUSE, 8) > 0 THEN 'DISPLAY_CONTROL' END AS DC,
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

轉寫規則（照輸出原樣抄，不加不減、不解讀）：

- 欄位：`RECNAME.FIELDNAME`；沒綁 Record 的元件寫 LBLTEXT（沒有就留空）。
- 元件：CONTROL；`DropDown List Box` 寫成 App Designer 的 `Drop-Down List Box`（SQL 裡不能寫 Drop-Down，規則 7b）；
  OTHER 寫 `OTHER（代碼 <CODE>）`，不猜是什麼元件。
- 屬性：DO、INV、DC、KEY_FLAG、REQ、RDATE、AUPD 各欄有值的依序以空白串起，再接 `RELATED_TO=<RELATED_TO>`、
  `LEVEL=<LVL>`（LVL 大於 0 才寫）、`GOTO=<GOTO_COMPONENT>`、`PAGE=<SUBPAGE>`（有值才寫）。
- 查值：PROMPT_REC 有值寫 `PROMPT <PROMPT_REC> <PROMPT_EDIT>`，PROMPT_KIND／PROMPT_KEYS 有值再接
  `（<PROMPT_KIND>；鍵 <PROMPT_KEYS>）`；沒有 prompt 時寫 VALUES_EDIT 的值；都沒有留空。
- 元件是 Subpage、Secondary Page、Push Button/Hyperlink: Secondary Page → 以 SUBPAGE 的頁名再跑一次本節
  （visited 去重、深度 ≤ 8，同 §2j）。
- 寫成證據時 SQL 原樣保留（含 FROM 與頁名、`:afterFieldNum` 的實際值），每個 Page 每一批一列。

值域：

- DISPLAY_ONLY、INVISIBLE＝設計期設定；PeopleCode 在執行期改的顯示、可改、必填寫在 NN 的「## 條件 UI」，不改這裡。
- 元件名稱＝App Designer 的元件名；按鈕／超連結在冒號後接目的地：PeopleCode Command＝按下去跑所綁欄位的 FieldChange
  （內容寫在「行為邏輯」）、Internal Link＝轉到 GOTO_COMPONENT、Secondary Page＝開 SUBPAGE 那一頁、External Link＝開外部網址
  （網址不在本查詢的欄位裡）。
- Scroll Bar＝舊式的層級捲動，和 Scroll Area 一樣框住下一層的列；Tab Separator＝Grid 裡把欄位分成分頁的分隔，LBLTEXT 是分頁標籤，
  它後面的欄位到下一個 Tab Separator 為止屬於這個分頁。
- RELATED_TO＝本列是相關顯示（代碼旁的說明欄，FIELDUSE 16），值＝控制欄的 FIELDNUM（ASSOCFIELDNUM 從 0 起算，SQL 已加 1）；
  DISPLAY_CONTROL＝本列是相關顯示的控制欄（FIELDUSE 8）。
- KEY、REQUIRED、REASONABLE_DATE、AUTO_UPDATE（存檔時系統自動押時間）是 Record 欄位的設定，同一欄位在每個 Page 都一樣。
- XLAT＝值須在 Translate 清單內；YES_NO＝只收 Y／N。
- PROMPT 的 EDIT＝輸入值必須在 prompt 清單內；NO_EDIT＝只提供查詢、不檢核；DYNAMIC＝prompt 表在執行期由另一個欄位的值決定
  （PROMPT_REC 是 `%` 開頭的欄位名），追 PeopleCode 對該欄位的指派。
- PROMPT_KIND＝TABLE、VIEW、DERIVED、OTHER；view 的選取條件照長文本協定以 ES＋Source 取，不從 Oracle 撈全文。
  PROMPT_KEYS＝prompt record 的鍵（依欄位順序）；含 SETID、EFFDT 的照實寫。

**2m. Component 動作與搜尋 Record（一個 Component 一次；NN「## 畫面元件」表格的第一列）**

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

轉寫規則（照輸出原樣抄，不加不減、不解讀）：

- 頁面＝COMPONENT、#＝0、欄位留空、元件＝`Component`。
- 屬性：ACT_ADD、ACT_UPD、ACT_ALL、ACT_COR 有值的依序以空白串起；OTHER_BITS 有值再接 `OTHER=<OTHER_BITS>`。
- 查值：`SEARCH <SEARCH_REC>`；ADD_SEARCH_REC 有值再接 `；ADD_SEARCH <ADD_SEARCH_REC>`。
- 回多列（同名 Component 有多個 market 版本）每列各寫一列；0 列＝名稱不是 Component，不寫這一列，「未解事項」記一行。
- 寫成證據時 SQL 原樣保留（含 FROM 與 Component 名），一列。

值域：

- ADD＝可新增一筆新的鍵值（進入時先輸入新鍵值）；UPDATE_DISPLAY＝修改既有資料，有效日期的列只看得到目前與未來；
  UPDATE_DISPLAY_ALL＝看得到歷史列、只能改目前與未來的列；CORRECTION＝連歷史列都能改。沒有有效日期列的 Component，後三者效果相同。
- 使用者實際能用哪幾個動作還要看權限（Permission List 對該 Menu Item 授權的動作，§4）。
- SEARCH＝搜尋頁查的 Record（搜尋條件是它的搜尋鍵；列層級安全也靠它，§4）；ADD_SEARCH＝新增時用的搜尋 Record，沒有＝新增也用 SEARCH。
- OTHER＝四個動作以外的位元，照數字寫，不猜意思。

---

## 3. Process / 排程（協定角色：ps_get_process_usage）

程式 → Process Definition：

```sql
SELECT PRCSTYPE, PRCSNAME, DESCR FROM <schema>.PS_PRCSDEFN WHERE PRCSNAME = :name
```

允許執行它的 Component（Run Control 頁面所在）：

```sql
SELECT PRCSNAME, PNLGRPNAME FROM <schema>.PS_PRCSDEFNPNL WHERE PRCSNAME = :name
```

被哪些 Job 包含：

```sql
SELECT PRCSJOBNAME, PRCSNAME, PRCSJOBSEQ FROM <schema>.PS_PRCSJOBITEM WHERE PRCSNAME = :name
```

已排程的請求（recurrence 名稱在此）：

```sql
SELECT PRCSNAME, RECURNAME, RUNSTATUS, RUNDTTM
  FROM <schema>.PSPRCSRQST WHERE PRCSNAME = :name AND RECURNAME <> ' '
FETCH FIRST 50 ROWS ONLY
```

Recurrence 定義：

```sql
SELECT * FROM <schema>.PS_PRCSRECUR WHERE RECURNAME = :recurName
```

---

## 4. Security（協定角色：ps_get_security_path）

Component → Permission List（經由 Menu Item）。本句回傳的 MENUNAME 是 **technical authorization metadata**，不是導覽路徑；
「某角色實際看得到哪個入口」需另外接 §2k 的 Portal Registry 入口與 CREF 權限，本節不足以回答：

```sql
SELECT DISTINCT A.CLASSID, A.MENUNAME, A.AUTHORIZEDACTIONS
  FROM <schema>.PSAUTHITEM A
  JOIN <schema>.PSMENUITEM M
    ON A.MENUNAME = M.MENUNAME AND A.BARITEMNAME = M.ITEMNAME
 WHERE M.PNLGRPNAME = :componentName
FETCH FIRST 100 ROWS ONLY
```

Permission List → Roles：

```sql
SELECT ROLENAME, CLASSID FROM <schema>.PSROLECLASS WHERE CLASSID = :classId
```

Role → 使用者「數量」（只回彙總，不列名單）：

```sql
SELECT ROLENAME, COUNT(*) AS USER_CNT
  FROM <schema>.PSROLEUSER WHERE ROLENAME = :roleName GROUP BY ROLENAME
```

Row-level：Component 的 Search Record：

```sql
SELECT PNLGRPNAME, SEARCHRECNAME, ADDSRCHRECNAME
  FROM <schema>.PSPNLGRPDEFN WHERE PNLGRPNAME = :componentName
```

---

## 5. AE 結構（協定角色：ps_get_ae_graph 近似）

AE 有哪些 Section：

```sql
SELECT AE_APPLID, AE_SECTION, DESCR FROM <schema>.PSAESECTDEFN WHERE AE_APPLID = :aeName
```

Section 有哪些 Step：

```sql
SELECT AE_SECTION, AE_STEP, AE_STMT_TYPE
  FROM <schema>.PSAESTEPDEFN WHERE AE_APPLID = :aeName AND AE_SECTION = :section
```

> Step 的 SQL / PeopleCode **內容**不從這裡撈——照長文本協定走
> PeoplecodeElasticSearch + PeoplecodeSource。

---

## 6. Record / Field 基本盤

Record 定義與實體表名（SQLTABLENAME 空白 → PS_<RECNAME>）：

```sql
SELECT RECNAME, RECTYPE, SQLTABLENAME, RECDESCR FROM <schema>.PSRECDEFN WHERE RECNAME = :recName
```

Record 欄位清單（含 subrecord 展開）：

```sql
SELECT RECNAME, FIELDNAME, FIELDNUM, EDITTABLE
  FROM <schema>.PSRECFIELDDB WHERE RECNAME = :recName ORDER BY FIELDNUM
FETCH FIRST 200 ROWS ONLY
```

欄位被哪些 Record 使用（血緣輔助）：

```sql
SELECT RECNAME FROM <schema>.PSRECFIELDDB WHERE FIELDNAME = :fieldName
FETCH FIRST 100 ROWS ONLY
```

---

## 7. 欄位使用剖析（原生欄位無用判定）

用途：clone-contract「原生欄位無用判定」的資料面（7a～7c）與 PeopleCode 交叉參照（7d～7e），
研究時寫 NN「畫面與欄位」生命狀態欄的資料剖析也用 7a～7c。委派給 @ps-metadata-flow（oracleMCP 類）。
只回彙總，不撈明細。任何一步查不到表或欄位、逾時或失敗 → 該步停止、記 gaps，
呼叫端依「判不了就保留」處理；不換表名或欄位名再猜、不改用抽樣、不重試迴圈。

**7-0. 前置驗證（每個環境第一次使用必跑）**

```sql
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
  FROM ALL_TAB_COLUMNS
 WHERE TABLE_NAME IN ('PSRECFIELDDB', 'PSPCMNAME')
   AND COLUMN_NAME IN ('RECNAME', 'FIELDNAME', 'FIELDNUM', 'DEFRECNAME', 'DEFFIELDNAME', 'REFNAME',
                       'OBJECTVALUE1', 'OBJECTVALUE2', 'OBJECTVALUE3')
   AND OWNER = UPPER('<schema>')
 ORDER BY TABLE_NAME, COLUMN_NAME
FETCH FIRST 50 ROWS ONLY
```

- PSRECFIELDDB 缺 DEFRECNAME 或 DEFFIELDNAME → 7c 不比對預設常數（有預設常數的欄位一律保留）。
- PSPCMNAME 缺 RECNAME、REFNAME 或 OBJECTVALUE1～3 任一 → 7d 做不了，查法 a 未完成。

**7a. Record 欄位與預設常數**

```sql
SELECT FIELDNAME, FIELDNUM, DEFRECNAME, DEFFIELDNAME
  FROM <schema>.PSRECFIELDDB
 WHERE RECNAME = :recName
 ORDER BY FIELDNUM
FETCH FIRST 200 ROWS ONLY
```

- 預設常數＝DEFRECNAME 空白、DEFFIELDNAME 非空白且不以 `%` 開頭時的 DEFFIELDNAME 值；其他情況視為沒有預設常數。
- 第一次使用先拿一個已知有預設常數的欄位核對；對不上 → 7c 不比對預設常數。
- 超過 200 欄 → 加 `AND FIELDNUM > :lastFieldNum` 續查。

**7b. 實體欄位型別與統計資訊**

實體表名照 §6（SQLTABLENAME 空白 → `PS_<RECNAME>`）。

```sql
SELECT OWNER, COLUMN_NAME, DATA_TYPE, NUM_DISTINCT, NUM_NULLS, LAST_ANALYZED
  FROM ALL_TAB_COLUMNS
 WHERE TABLE_NAME = :physicalTable
 ORDER BY OWNER, COLUMN_ID
FETCH FIRST 200 ROWS ONLY
```

- 回 0 列 → 沒有實體表（View、Derived／Work），整個 Record 判不了、全部保留。
- 多個 OWNER → 只採 `<schema>`（profile `oracle.currentSchema`）那組；判斷不了就整個 Record 判不了、全部保留。
- DATA_TYPE 是 LONG、LONG RAW、RAW、CLOB、BLOB、NCLOB → 該欄判不了、保留，不進 7c。
- 統計資訊只能用來判「有使用跡象」：日期型 NUM_DISTINCT ≥ 1、其他型 NUM_DISTINCT ≥ 3 → 保留，不必進 7c。
  其餘欄位（含沒有統計資訊）是候選，進 7c。統計資訊不能用來判無用。

**7c. 非預設值彙總（候選欄位，一次 ≤ 40 欄，全表）**

```sql
SELECT COUNT(*) AS TOTAL_ROWS,
       SUM(CASE WHEN <CHAR_FIELD> <> ' ' THEN 1 ELSE 0 END) AS <CHAR_FIELD>,
       SUM(CASE WHEN <CHAR_FIELD_D> NOT IN (' ', '<預設常數>') THEN 1 ELSE 0 END) AS <CHAR_FIELD_D>,
       SUM(CASE WHEN <NUM_FIELD> NOT IN (0, <預設常數>) THEN 1 ELSE 0 END) AS <NUM_FIELD>,
       SUM(CASE WHEN <DATE_FIELD> IS NOT NULL THEN 1 ELSE 0 END) AS <DATE_FIELD>
  FROM <schema>.<physicalTable>
FETCH FIRST 1 ROWS ONLY
```

- 字元欄：不是單一空白、也不是預設常數才算有值（NULL 算沒值）；數值欄：不是 0、也不是預設常數才算有值；
  日期欄：非 NULL 就算有值。沒有預設常數的欄位只寫前半段條件。
- TOTAL_ROWS ＝ 0 → 空表（暫存／中介表常在處理後清空），整個 Record 判不了、全部保留。
- 結果 0 ＝ 該欄非預設值 0 筆；> 0 → 保留。逾時 → 這一批判不了、全部保留；不加 WHERE、不抽樣。
- 寫成證據時 SQL 原樣保留（含 FROM 實體表）。excerpt／keyRows 只寫不隨日期變動的斷言：
  `TOTAL_ROWS > 0`、為 0 的欄位、有值的欄位；不寫實際筆數（線上筆數每天變，重跑必不同）。
- NN 生命狀態欄的記法：`欄位：非預設 0 筆（全表非空，查詢日 YYYY-MM-DD）` 或
  `欄位：有值（全表，查詢日 YYYY-MM-DD）`，SQL 進 Evidence 附錄；選項生命狀態照原寫法接在同一格。

**7d. PeopleCode 交叉參照（只查 7c 結果為 0 的欄位）**

```sql
SELECT OBJECTVALUE1, OBJECTVALUE2, OBJECTVALUE3, RECNAME, REFNAME, COUNT(*) AS CNT
  FROM <schema>.PSPCMNAME
 WHERE REFNAME IN (<7c 為 0 的欄位>)
 GROUP BY OBJECTVALUE1, OBJECTVALUE2, OBJECTVALUE3, RECNAME, REFNAME
 ORDER BY OBJECTVALUE1
FETCH FIRST 200 ROWS ONLY
```

逐列判讀，算「核心路徑引用」的欄位一律保留：

1. RECNAME 是本 Record 以外、經 7e 確認的 Record → 那是別的 Record 的同名欄位，這列不算。
   RECNAME 是本 Record，或 7e 確認不是 Record 名（定義型參照）→ 繼續判下面各條。
2. OBJECTVALUE1 是 scope 中 CORE／DEPENDENCY 物件名，或本 Component 任一 Page 上出現的 Record（§2d）→ 算。
3. OBJECTVALUE1～3 任一是 `FieldFormula`（函式庫）→ 算。
4. OBJECTVALUE1 經 7e 確認是 scope 外的 Component 或 Record → 不算。
5. 其餘（Application Package、Page、AE 或判斷不出物件類型）→ 算。

回滿 200 列 → 依 REFNAME 分批重查到不滿 200 列為止；做不完 → 查法 a 未完成。

**7e. 名稱類型確認（7d 用）**

```sql
SELECT * FROM (
  SELECT 'COMPONENT' AS KIND, PNLGRPNAME AS NAME FROM <schema>.PSPNLGRPDEFN WHERE PNLGRPNAME IN (<名稱清單>)
  UNION ALL
  SELECT 'RECORD' AS KIND, RECNAME AS NAME FROM <schema>.PSRECDEFN WHERE RECNAME IN (<名稱清單>)
) FETCH FIRST 200 ROWS ONLY
```

- 名稱清單＝7d 結果中的 OBJECTVALUE1 與本 Record 以外的 RECNAME。
- 同一名稱同時是 Component 與 Record → 判斷不出類型，依 7d 第 5 條算核心路徑引用。
