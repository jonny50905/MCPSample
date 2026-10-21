# 畫面元件、Prompt／Lookup 與欄位間規則——缺口盤點與補法（提案）

> **採信基礎**：本文只採信 `main` 頭 `f76ef5e` 逐行實看的檔（兩版 sdoc 契約與 schema、`scripts/ps-sdoc*.ps1`、oracle-query-cookbook、ps-ui-flow／ps-peoplecode-flow、
> 設計文件 `spec-schema-framework.md` 與貫穿範例、rebuild-kit 對照表）。「檔案:行號」皆為實看。
> PeopleTools 表欄與代碼凡標「待校準」者，都還沒在公司環境驗證，**不得未經校準寫進 profile 或任何模型讀的檔**（cookbook 使用規則 6、8）。
> 例子一律用合成的 `TW_DEMO_*`。範圍：Spec 文件流程（DOC1，兩版共用 schema 與外環）；只談 Classic page（profile `navigation.surfaces: CLASSIC_ONLY`）。
> 日期：2026-10-14。狀態：**提案，未實作**。

---

## 0. 結論

1. 缺口不全是「schema 沒地方寫」，分三類：
   - **A 沒地方寫**：Prompt 檢核與否、動態 prompt、lookup 的有效日基準、prompt view 的選取邏輯、相關顯示（代碼旁的說明）、按鈕的動作與目標、
     Grid／Scroll 能不能增刪列與是否自動載入／存檔、系統內建檢核（Required、Prompt edit、Translate edit…）、同一欄位的多個元件、動態下拉選項。
   - **B 有地方寫，但沒有查法或契約沒要求**：元件型別（`controlType` 有欄，但 `FIELDTYPE` 拿回來沒有對照表，模型只能依資料型別猜）、
     prompt 依上層欄位過濾（`filter` 寫得出來，但沒人要求、也沒有查 prompt record 鍵結構的樣板）、lookup 視窗的欄位（`keyRoles` 有值，但 prompt 實體的欄位常沒寫）。
   - **C 寫了沒人驗**：沒有任何檢核比對元件型別、設計期屬性、prompt 與 metadata 是否一致；貫穿範例與測試都沒有一個完整的 prompt 欄位。
2. 根因：metadata 只查到「Page 上有哪些 Record.Field」（cookbook §2d）與「EDITTABLE＋筆數」（§2f）。控制項的設計期屬性、Record 欄位的 edit 設定、
   prompt record 的鍵結構都沒有查法；而且 **09 的分母只有 PeopleCode 程式**，不靠 PeopleCode 的系統檢核沒有分母、也沒有位置。
3. 建議主軸：**metadata 是確定性的事實，交給外環**——模型照固定樣板原樣轉抄代碼，外環用 profile 校準過的對照表解碼，
   解出的事實由外環帶入項目並做 L2 比對（同 STATE／TRN 的骨架欄位「外環帶入、研究包不得寫」）；模型只寫 PeopleCode 造成的動態行為與業務語意。
4. 分四期（P＝Phase，分期代號；P0 最先做）：**P0** 查法與校準（不改 schema，可先上線）→ **P1** metadata 單元與 schema 擴充 → **P2** 外環檢核、渲染投影、讀者題 → **P3** rebuild-kit 對照。
   P0 需要管理者在公司機做一次校準（只回 PeopleTools 欄位名與代碼數字，不含業務資料）。
5. **管理者回饋後的調整見 §7**：先用 SQL 驗證假設，再改走補查（ps-supplemental）把這些事實存進知識層，P1 的 meta 單元由知識層取代；分期改成 §7 的五步。

---

## 1. 現況（四個面向各有什麼）

| 面向 | schema 已有的欄位 | 研究契約 | 查法（cookbook） | 檢核／讀者題 |
|---|---|---|---|---|
| 元件類型 | 05 `controlType` 15 值（`05-ui.schema.json:185-204`），混了元件與能力：`PROMPT`、`DATE` 不是 PeopleSoft 的元件種類 | ui 節「控制項型別」一句（`research-contract.md:245`） | §2d 取回 `FIELDTYPE` 原始代碼，沒有對照表（`oracle-query-cookbook.md:180-189`）；只有 §2h／§2j 用到 2＝Group Box、11＝Subpage（:243-244） | 無 |
| 元件屬性 | 05 `label`、`presence`、`visibility`、`editability`、`options`、`displayDefault`、`interactions`；SCREEN 的 `modes`、`searchKeys`、`regions`（只有 scrollLevel、repeating） | ui 節：出現方式、顯示與可編輯條件、選項、畫面初值（:245） | 沒有任何設計期屬性的查詢；PeopleCode 只偵測 Visible／Hide／Gray／DisplayOnly／Enabled／Required（`ps-peoplecode-flow/SKILL.md:69-74`） | R05 選項儲存值在值域內（`ps-sdoc-check-lib.ps1:146-156`）、C03 每個頁面欄位有元件（:490-497）、讀者 U1 顯示／可編輯條件（`ps-sdoc-reader-lib.ps1:202-208`） |
| Prompt／Lookup | 07 `valueDomain.prompt{entity,keyField,filter}`（`07-database.schema.json:362-383`）、`relations` 的 `PROMPT_LOOKUP`（:456）；05 `valueSource{kind:PROMPT,prompt{entity,filter}}`（`05-ui.schema.json:328-371`） | data 節「值域（Translate／Prompt 的顯示文字↔儲存值）」（:176） | §2f 只取 `EDITTABLE` 與 `COUNT(*)`（:204-212）；§6 Record 欄位只查 `EDITTABLE`（:629-643） | 無。貫穿範例 07 的 4 個 prompt 欄位都只寫 entity＋keyField（例：`walkthrough/canonical/07-database.json` 的 `REQUESTER_EMPLID` 指向有效日實體），05 沒有一個元件的值來源是 PROMPT：lookup 用哪天的有效列、只列有效狀態與否、清單外的值擋不擋，文件都讀不出來 |
| 欄位間規則 | 09 BR（trigger.event／control、condition、action 的 SET_VALUE／CLEAR_VALUE／REJECT／WARN）、05 條件與 `interactions`、07 `default` 可指別欄、DRV | rules 節：分母是 PeopleCode 程式，每支一筆處置（:254） | 無欄位層的交叉參照查法（§7d 只用於無用判定） | R10、讀者 B1～B4 |

外環面：分母 `denominators.pages[].fields` 只列「綁定 Record 欄位的元件」（`research-contract.md:165`），且 `uniqueItems`（`research-packet.schema.json:352`）；
UI 自然鍵是 `<Component>.<Page>.<Record>.<欄位>`（`05-ui.schema.json:46`）。設計文件 §3.4 寫「分母用固定 SQL 樣板、外環比對 SQL 指紋」（`spec-schema-framework.md:155`），實作沒有比對。

---

## 2. 缺口盤點

類別：A 沒地方寫／B 有地方寫但沒查法或沒要求／C 寫了沒人驗。「事實在哪」欄的表欄是候選，以 §3.2 的探勘與校準為準。

### 2.1 元件類型

| 項目 | 事實在哪（待校準） | 現況 | 類別 | 不補的後果（重建端） |
|---|---|---|---|---|
| 元件型別解碼 | PSPNLFIELD.FIELDTYPE | 拿回代碼沒有對照，模型依資料型別猜 | B | 同是 CHAR(1) 的欄位，drop-down／radio／checkbox／edit box 分不出來 |
| 列舉混了能力 | 有 prompt 的 edit box、日期 edit box 在 PeopleSoft 都是 edit box | `PROMPT`、`DATE` 與 `EDIT_BOX` 並列 | A（語意） | 同一種元件寫法不一，無法機器比對 |
| 缺的型別 | HTML Area、Tree、Chart、Static Image 等 | 只能落 `OTHER` | A | 看不出是什麼；HTML Area 常放說明或客製內容 |
| 同一欄位多個元件 | Radio 每顆是一列 page field；同一欄位在表頭與 grid 各放一次 | 分母 `uniqueItems`、自然鍵只到欄位 → 疊成一筆 | A | Radio 群組靠模型自行合併；兩處屬性不同（一處唯讀）只能寫一筆 |
| 沒綁 Record 欄位的元件 | Static Text（畫面上的說明、警語）、HTML Area、部分按鈕／連結 | 不在分母；自然鍵的 `.@<名稱>` 形式（`05-ui.schema.json:46`）沒有任何規則使用 | A | 畫面上的操作說明不進 Spec |
| 元件順序 | PSPNLFIELD.FIELDNUM（處理與 tab 順序） | 05 沒有順序欄 | A | 區塊內欄位順序只能猜 |

### 2.2 元件屬性

**控制項**

| 項目 | 事實在哪（待校準） | 現況 | 類別 | 不補的後果 |
|---|---|---|---|---|
| 設計期 Display Only／Invisible | PSPNLFIELD 的使用旗標欄 | 05 的 `editability`／`presence` 寫得出來，但沒有 metadata 依據 | B＋C | 設計期唯讀被寫成 ALWAYS 可改，沒有檢核擋 |
| 相關顯示（Related Field／Display Control：代碼旁顯示說明） | PSPNLFIELD 的關聯欄 | 沒有欄位 | A | 不知道「部門代碼旁的部門名稱」從哪張表、哪個欄位來，何時刷新 |
| Checkbox 勾選／未勾選的儲存值 | page field 屬性 | 只能借 `options` 寫兩列 | A（弱） | 儲存值寫錯（Y/N、1/0） |
| Radio 每顆的儲存值與文字 | 每顆一列 page field（儲存值欄位待找） | `options` 寫得出來，但契約沒規定合併 | B | 選項漏顆或重複 |
| 按鈕／超連結的動作與目標（PeopleCode、Secondary Page、轉到別的 Component、外部連結、插列／刪列、toolbar、prompt、process） | PSPNLFIELD 的目標欄或按鈕資料表 | `interactions` 有 NAVIGATE／OPEN_MODAL／INVOKE_FUNCTION，沒有目標、沒有 metadata 依據 | A＋B | 不知道按鈕開哪一頁、轉哪個 Component |
| 密碼遮罩 | 使用旗標 | 無 | A | 資安行為漏掉 |
| 是否顯示 prompt 按鈕、typeahead | 使用旗標 | 無 | A | 中 |
| Allow Deferred Processing（欄位改了是否立刻回伺服器） | 使用旗標＋Component 處理模式 | 無 | A | FieldChange 何時生效、哪些欄位要即時連動 |
| Set Component Changed、Display Zero、貨幣符號、多行、寬度、樣式 | 使用旗標等 | 無 | A | 低（呈現類，建議不收） |
| 標籤來源（RFT 短／長、自訂文字、訊息目錄） | LBLTYPE、LABEL_ID、LBLTEXT（cookbook 已用） | `label` 只寫文字 | C | 低；ps-ui-flow 現況限制已列「Page Field 覆寫 label 的最終文字解析」尚缺（`ps-ui-flow.md:91-92`） |

**Grid／Scroll（05 SCREEN.regions）**

| 項目 | 事實在哪（待校準） | 現況 | 類別 | 不補的後果 |
|---|---|---|---|---|
| 主 Record | grid／scroll 那一列的 RECNAME（待確認） | `regions` 沒有實體 | A | 明細綁哪張表要自己推 |
| 能否插列、刪列、多列插入 | 使用旗標；PeopleCode 的 InsertEnabled／DeleteEnabled | 無；偵測清單也沒有 | A＋B | 使用者能不能新增、刪除明細列——核心行為 |
| No Auto Select／No Auto Update（資料由程式載入／存檔） | 使用旗標 | 無 | A | 重建端照預設自動載入與存檔＝行為錯 |
| 每頁列數、列選取（單選／多選） | 屬性 | 無 | A | 中 |

**Component（05 SCREEN）**

| 項目 | 事實在哪（待校準） | 現況 | 類別 | 不補的後果 |
|---|---|---|---|---|
| 可用模式 | PSPNLGRPDEFN 的模式旗標 | `modes` 由模型自填，沒有查法 | B | 模式寫錯 |
| 處理模式（Interactive／Deferred） | PSPNLGRPDEFN | 無 | A | 同上「何時生效」 |
| Component 內隱藏的 Page | PSPNLGROUP | 無 | A | 低 |
| 搜尋頁的結果欄（list box item）、替代搜尋鍵 | search record 的 Record 欄位 edit 設定 | `searchKeys` 只有搜尋鍵；search record 的欄位不一定寫 | B | 搜尋結果列表欄位與替代搜尋條件漏掉 |

### 2.3 Prompt／Lookup

| 項目 | 事實在哪（待校準） | 現況 | 類別 | 不補的後果 |
|---|---|---|---|---|
| 會不會檢核（Prompt Table Edit 與 Prompt Table with No Edit） | PSRECFIELDDB 的 edit 位元＋EDITTABLE | 沒有欄位 | A | 輸入清單外的值要擋還是放行，讀不出來 |
| 動態 prompt（`%EDITTABLE`：prompt 表在執行期由另一個欄位的值決定） | EDITTABLE 的值＋PeopleCode 對該欄位的指派 | 沒有欄位；偵測清單沒有 | A＋B | 「選了 A 類，代碼清單換成另一張表」整段漏掉 |
| 高階鍵自動帶入（prompt record 在被編輯欄位之前的鍵，取 component 內同名欄位的值） | prompt record 的鍵順序；同名規則是 PeopleTools 標準行為（以校準頁實測確認） | `filter` 寫得出來，但契約沒要求、沒有查鍵結構的樣板 | B | lookup 沒依上層欄位過濾（例：細類不依類別） |
| SETID 解析（以 SETID 為鍵的 prompt，依 set control 欄位查 TableSet） | Record 欄位／Record 的 set control 欄＋TableSet 設定 | 沒有欄位；rebuild-kit 只列為陷阱（`ps-mapping.md:98`） | A＋B | 同上 |
| 有效日 as-of（prompt 表有 EFFDT 時以哪個日期取有效列、是否只列有效狀態） | prompt record 的 EFFDT 鍵；as-of 規則是標準行為（實測確認） | ENT 的 `effectiveDating` 是實體自己的目前列規則，不是 lookup 的基準日 | A | 例：生效日在未來的列該不該出現 |
| Prompt／search view 的選取邏輯 | view 的 SQL 文字（表待找） | ENT 對 SQL_VIEW 沒有定義欄 | A | 「只列在職員工」「只列使用者部門」這類條件消失 |
| lookup 視窗的欄位與搜尋條件 | prompt record 的 search key／alt search key／list box item | 07 `keyRoles` 有這些值，但 DEPENDENCY 實體只寫「核心用到的欄位」（`research-contract.md:176`） | B | lookup 結果欄位與可搜尋欄位漏掉 |
| prompt 表進範圍 | EDITTABLE | scope 只說「查值所需的最小依賴是 DEPENDENCY」（:156），沒點名 prompt 表、view、`%EDITTABLE` 的候選表 | B | prompt 實體沒有 ENT，filter 無從引用 |
| 選後帶出的說明 | 見 2.2 相關顯示 | | A | |

高基數 prompt 不需要值清單（ps-ui-flow 已規定只回 metadata）；要的是 lookup 的**查法**，不是資料。

### 2.4 欄位間規則

| 相依種類 | 事實在哪 | 現況 | 類別 | 不補的後果 |
|---|---|---|---|---|
| 系統內建檢核（Required、Prompt edit、Translate edit、Y/N edit、Reasonable Date、鍵重複、有效日鍵重複） | Record 欄位的 edit 設定（不在 PeopleCode） | 09 分母只有 PeopleCode 程式 → 沒有分母、沒有位置；08 `validations`（`research-contract.md:270`）與 14 反例跟著漏 | A | 重建端少做一整類拒絕規則 |
| 系統維護欄位（System Maintained、Auto-Update：存檔時自動押時間或使用者） | Record 欄位 edit 設定 | 無 | A | 時間戳、異動者欄位不會自動更新 |
| 值相依（A 改了 B 跟著變） | FieldChange／FieldDefault／RowInit；Record 預設 `DEFRECNAME.DEFFIELDNAME` | BR SET_VALUE、FLD `default`（已有） | C（缺總覽） | 誰觸發誰要自己拼 |
| 選項相依（A 決定 B 的下拉選項） | `AddDropDownItem`／`ClearDropDownList` | 05 `options` 是靜態陣列；偵測清單沒有這兩個 | A＋B | 下拉選項不隨上層欄位變 |
| 查值相依（A 決定 B 的 lookup） | 2.3 的高階鍵、SETID、`%EDITTABLE` | 見 2.3 | A＋B | |
| 狀態相依（A 決定 B 顯示／可改／必填） | PeopleCode Visible／DisplayOnly／Enabled… | 05 條件已有；必填條件在 09 BR，05 沒有必填欄 | C | 畫面上的必填提示要跨文件拼 |
| 明細列相依（依狀態決定可否增刪列） | `InsertEnabled`／`DeleteEnabled` | 無 | A＋B | |
| 標籤相依 | `.Label =` | 偵測清單沒有 | B | 低 |
| 生效時機（即時或延後處理） | 2.2 | 無 | A | |
| 總覽：一個欄位被哪些規則影響、又影響誰 | 現有參照可反查 | 散在 05／07／09 | C | 重建端不知道哪些欄位要即時回伺服器 |

### 2.5 欄位本身（07 FLD）連帶缺的

| 項目 | 事實在哪（待校準） | 現況 | 類別 | 不補的後果 |
|---|---|---|---|---|
| 大小寫與格式（Uppercase、Format Family） | PSDBFIELD 的格式欄 | 無；rebuild-kit 把大小寫列為陷阱（`ps-mapping.md:90-91`） | A | 自動轉大寫、輸入格式漏掉 |
| 型別、長度、必填、鍵的查法 | PSDBFIELD、PSRECFIELDDB 的 edit 位元 | cookbook §6 只有 EDITTABLE；模型得自己找欄位名（使用規則 8 要先驗欄位） | B＋C | 寫錯沒人擋 |

---

## 3. 補法

### 3.1 原則

1. **metadata 交給外環**：固定樣板、原樣轉抄、外環解碼與比對；模型只寫動態行為與業務語意。
2. **代碼先校準再用**：照 `navigation:` 的先例（`customization-profile.yaml:102-113`、SOP-20），profile 新增 `pageMetadata:` 區塊；
   `verified: false` 時解碼與相關檢核一律 NOT_APPLICABLE（不擋、不猜），渲染標「metadata 未校準」。失敗模式都有值域可落（L92 的原則）。
3. **每次回應綁小**（L148／L149）：轉抄一頁一個 PS Page（或 ≤40 列）；新屬性多數由外環帶入，研究包反而變小。
4. **事實歸屬照設計 §7.5**：Record 欄位層的事實在 07（含系統檢核、prompt 語意）；Page 欄位層的事實在 05（元件、呈現、lookup 的畫面面）；
   PeopleCode 造成的變化在 05（純畫面）或 09（會拒絕或寫資料）。
5. **只加不刪**：既有欄位與列舉保留；`PROMPT`、`DATE` 視為 edit box 的別名。不新增 ID 前綴（新前綴要動 registry、層級、參照方向、渲染與測試，沒有額外價值）。

### 3.2 P0：查法與校準（不改 schema）

**cookbook 新節**（兩版同步；名稱暫定）：

| 節 | 內容 | 頻率 |
|---|---|---|
| §2l 頁面 metadata 探勘 | `ALL_TABLES` 列 `PSPNL%` 等表；`ALL_TAB_COLUMNS` 列 PSPNLFIELD、PSPNLDEFN、PSPNLGROUP、PSPNLGRPDEFN、PSRECFIELDDB、PSDBFIELD、PSRECDEFN 與 view SQL 所在表的欄位；查不到記 gap，不換名硬湊 | 每個環境一次 |
| §2m Page 控制項 canonical | 一個 Page 一次：既有已驗欄（PNLNAME、PNLFLDID、FIELDNUM、FIELDTYPE、PNLFIELDNAME、RECNAME、FIELDNAME、SUBPNLNAME、OCCURSLEVEL、LBLTYPE、LABEL_ID、LBLTEXT）＋校準後確定的旗標欄、關聯欄、按鈕目標欄；`ORDER BY FIELDNUM` | 每個 Page |
| §2n Record 欄位 canonical | 一個 Record 一次：PSRECFIELDDB 的 FIELDNUM、edit 位元、EDITTABLE、DEFRECNAME、DEFFIELDNAME、set control 欄＋PSDBFIELD 的型別、長度、小數、格式 | 每個 Record |
| §2o Prompt record 結構 | 一批 ≤20 個 prompt record（IN 清單）：RECTYPE、鍵／搜尋鍵／list box（edit 位元）、有無 EFFDT／SETID 鍵；view 的 SQL 文字逐一取，長文只取需要的段 | 每批 |
| §2p Component 屬性 | PSPNLGRPDEFN 的模式旗標、處理模式、search record、add search record（§4 已查後兩欄）；PSPNLGROUP 的 page 順序與隱藏 | 每個 Component |

**profile 校準區塊**（兩版同步；校準後回填，之前全空）：

```yaml
pageMetadata:
  columns: {}            # §2l 探勘到、各 canonical 要選的實際欄位
  fieldTypeCodes: {}     # FIELDTYPE 代碼 → 元件種類（按鈕依目標類型分）
  pageFieldFlags: {}     # 旗標欄與位元 → DISPLAY_ONLY、INVISIBLE、NO_ROW_INSERT、NO_AUTO_SELECT…
  recordFieldEdits: {}   # edit 位元 → KEY、REQUIRED、PROMPT_EDIT、XLAT_EDIT、YES_NO_EDIT…
  dbFieldFormats: {}     # 格式代碼 → UPPER、MIXED…
  componentFlags: {}     # 模式旗標、處理模式
  verified: false        # true 才解碼、帶入、檢核
```

**SOP-30 校準程序（一次；換 PeopleTools 版本重做）**：

1. 一般 session 叫主代理照 §2l 探勘，回報表與欄位清單（只有 PeopleTools 欄位名）。
2. 管理者挑一兩個熟悉的 Classic 畫面當「校準頁」，下表元件各找一個；主代理以 §2m／§2n 取回這些元件的列（列裡的物件名留在本機）。
3. 對照 PIA 上看到的行為填對照；回報只用一行代號，例：
   `CAL1 FT EB=?,DD=?,LE=?,CB=?,RB=?,GR=?,SA=?,HA=?,PBPC=?,PBSP=?,PBTR=? FU DO=?,INV=?,NRI=?,NRD=?,NAS=?,NAU=? UE KEY=?,REQ=?,PE=?,XE=?,YN=?,SM=?,AU=?`（? 填觀察到的數字；沒有該元件的格留空，不猜）。
4. 回填 profile、`verified: true`；applied.md 記觀察值與日期，profile 註解只留結論。

校準頁要有：edit box、drop-down、long edit、checkbox、radio 群組、設計期唯讀欄位、設計期隱藏欄位、會檢核的 prompt 欄位、不檢核的 prompt 欄位、
代碼旁有說明的欄位、必填欄位、PeopleCode 按鈕、開 secondary page 的按鈕、轉到別的 Component 的連結、不能新增列的 grid 與可以新增列的 grid（或 scroll area）、
有效日 prompt、以 SETID 為鍵的 prompt。可選捷徑：先查 PSXLATITEM 有沒有這些代碼欄的 translate 值，有就當候選，仍以校準頁核對。

同一次實測確認標準行為（附錄 B）：輸入 prompt 清單外的值、有效日 prompt 的 lookup 會不會列出未來生效或無效狀態的列、上層欄位改了 lookup 是否跟著過濾。

### 3.3 P0：PeopleCode 偵測清單補齊

`ps-peoplecode-flow/SKILL.md:69-74` 的封閉清單加：`AddDropDownItem(`、`ClearDropDownList(`（動態選項）、`.Label =`（動態標籤）、
`.InsertEnabled =`、`.DeleteEnabled =`（明細列能否增刪）、對 `EDITTABLE` 欄位的指派（`%EDITTABLE` 動態 prompt；字面寫法待確認）。
研究契約同步寫明去處：選項與標籤、增刪列 → 05；動態 prompt → 07（§3.5）。

### 3.4 P1：metadata 單元與分母

- **新研究單元 `meta`**（每個 Component 一個主題；排在範圍之後、資料之前）：游標清單由外環從範圍的分母與 EDITTABLE 算出——一頁＝一個 PS Page（超過 40 列依 FIELDNUM 切）、
  一個 Record，或一批 prompt record。研究包不寫項目，只寫本單元專屬的附加資料 `pageControls`、`recordFields`、`promptRecords`、`componentProps`（原始代碼＋SQL 證據）。
  工作機械化，可比照讀者用低 effort。
- **外環**：驗 SQL 與樣板一致（正規化後比對指紋，補上設計 §3.4 沒實作的那一步）、驗列的格式；以 profile 解碼後：
  1. C03 分母改用**控制項身分**（Page＋FIELDNUM；radio 群組合併成一個；非 Record 元件依種類納入：HTML Area 必收、Static Text 收、純裝飾不收）。
  2. ui／data 工單預填「本頁元件的 metadata 事實（外環解碼）」——研究單元不必再為這些事實查 DB。
  3. §3.7 的 L2 檢核。
- **覆核**：覆核 session 重跑同一條樣板逐列比對（機械、便宜）。
- **另一條路（要管理者決定）**：PowerShell 直接用 SQLcl 已儲存連線跑固定 SELECT，完全不經模型轉抄。最穩，但跨過「scripts 不碰 DB」的現行邊界（設計 §14 的取捨列，`spec-schema-framework.md:1006`）。

### 3.5 P1：schema 擴充（兩版與設計目錄的 schema 逐位元同步）

**05 UI——CONTROL**

| 欄位 | 誰寫 | 內容 |
|---|---|---|
| `pageField` | 外環帶入 | `{fieldNum, pageFieldName, occursLevel, subpage, members}`（members＝radio 群組各顆的 FIELDNUM） |
| `controlType` | 研究寫、外環比對 | 列舉加 `HTML_AREA`、`TREE`、`CHART`、`STATIC_IMAGE`；`PROMPT`、`DATE` 保留為 edit box 別名 |
| `designFlags` | 外環帶入 | `DISPLAY_ONLY`、`INVISIBLE`、`PASSWORD`、`NO_PROMPT_BUTTON`、`DEFERRED_PROCESSING`…（校準後定案的封閉清單） |
| `relatedDisplay` | 外環帶入 | `{of: UI, field: FLD}`：本元件顯示 `of` 元件代碼對應的說明欄 |
| `checkbox` | 外環帶入（metadata 沒有時研究寫） | `{checked, unchecked}` 儲存值，須屬於欄位值域 |
| `button` | 外環帶入動作與目標，研究補效果 | `{action: PEOPLECODE｜SECONDARY_PAGE｜TRANSFER｜EXTERNAL_LINK｜SCROLL_ACTION｜TOOLBAR_ACTION｜PROMPT_ACTION｜PROCESS｜OTHER, target}` |
| `optionSets` | 研究寫 | `[{when: 條件, options: [{label, stored}]}]`：PeopleCode 動態選項；儲存值須在值域內（R05 擴充） |

自然鍵：第一個元件照舊 `<Component>.<Page>.<Record>.<欄位>`；同欄位的其他元件 `…<欄位>@<FIELDNUM>`；非 Record 元件 `<Component>.<Page>.@<頁面欄位名或種類_FIELDNUM>`（現行 pattern 已容許 `.@` 形式）。

**05 UI——SCREEN 與 regions**

| 欄位 | 誰寫 | 內容 |
|---|---|---|
| `regions[].entity` | 外環帶入 | 區塊主 Record 的 ENT |
| `regions[].rowInsert`、`rowDelete` | 外環帶入設計期值，研究補條件 | `ALWAYS｜NEVER｜條件`（PeopleCode InsertEnabled／DeleteEnabled） |
| `regions[].dataLoad`、`dataSave` | 外環帶入 | `AUTO｜BY_CODE`；`BY_CODE` 須以 `implementedBy` 指到 BR（C12） |
| `regions[].rowSelection`、`rowsPerPage` | 外環帶入 | 中優先 |
| `processingMode` | 外環帶入 | `INTERACTIVE｜DEFERRED` |

**07 資料**

| 欄位 | 誰寫 | 內容 |
|---|---|---|
| FLD `edits` | 研究寫、外環比對（P2 起可改外環帶入） | `PROMPT_EDIT`、`PROMPT_NO_EDIT`、`XLAT_EDIT`、`YES_NO_EDIT`、`REASONABLE_DATE`、`SYSTEM_MAINTAINED`、`AUTO_UPDATE`…；`required`、`keyRoles` 不動 |
| FLD `format` | 同上 | `{case: UPPER｜MIXED｜NA, family: 原文｜NA}` |
| `valueDomain.prompt.validation` | 研究寫、外環比對 | `EDIT｜NO_EDIT` |
| `valueDomain.prompt.effectiveDating` | 研究寫 | 沿用 DRV `resolution.effectiveDating` 的結構（rule、asOf、effStatusActiveOnly） |
| `valueDomain.prompt.setControl` | 研究寫 | `{field: FLD}`：SETID 依哪個欄位解析 |
| `valueDomain.prompt.dynamic` | 研究寫 | `{selector: FLD, cases: [{stored, entity}]}`：`%EDITTABLE`；指派 selector 的程式照常是 09 的 BR |
| `valueDomain.prompt.unboundKeys` | 研究寫 | 高階鍵沒綁定（lookup 列出全部）時列出並附證據 |
| ENT `definedBy` | 研究寫 | SQL_VIEW／DYNAMIC_VIEW 作為 prompt 或 search record 時，指向一個 `resultType: ROW_SET` 的 DRV（選取邏輯沿用 DRV 的 resolution，讀者題 D1～D3 自動適用） |

高階鍵綁定沿用既有 `filter`（`{"left":{"fld":"@FLD/TW_DEMO_SUBTYPE.REQ_TYPE"},"op":"EQ","right":{"fld":"@FLD/TW_DEMO_REQHDR.REQ_TYPE"}}`），不另開欄位。

### 3.6 P1：研究契約（兩版逐字同句，只換機制用語）

- **scope**：prompt 表（EDITTABLE）、prompt／search view、`%EDITTABLE` 的候選表、search record 與 add search record 列為 DEPENDENCY，`usedBy` 寫哪個欄位的 lookup。
- **meta**（新）：照 §2m／§2n／§2o／§2p 原樣查、原樣轉抄；不寫項目。
- **data**：`edits`、`format` 依工單預填的 metadata；prompt 欄位寫 `validation`、高階鍵綁定（`filter` 或 `unboundKeys`）、有效日 prompt 的 `effectiveDating`、
  SETID 的 `setControl`、`%EDITTABLE` 的 `dynamic`；prompt 與 search 實體的 search key、alt search key、list box 欄位一律寫 FLD（算核心用到）；view 寫 `definedBy`。
- **ui**：一個元件一筆（radio 群組一筆、同欄位多處各一筆）；非 Record 元件依種類；`optionSets`；regions 的增刪列條件與 `BY_CODE` 的實作規則；
  按鈕效果；`controlType` 不再寫 `PROMPT`／`DATE`；外環帶入的欄位不得寫。
- **rules**：§3.3 新偵測樣式的程式照常處置（UI_BEHAVIOR）；`BY_CODE` 載入／存檔的程式寫成 BR，並由 region 的 `implementedBy` 引用。

### 3.7 P2：外環——檢核、渲染投影、讀者題

**新檢核**（未校準 → R15～R17、R19 為 NOT_APPLICABLE）

| 代碼 | 層 | 檢查 |
|---|---|---|
| R15 | L2 | `controlType` 與解碼一致（`PROMPT`／`DATE` 視同 `EDIT_BOX`） |
| R16 | L2 | 設計期旗標與條件不矛盾：`DISPLAY_ONLY` 的元件 `editability` 不得是 ALWAYS；`INVISIBLE` 的元件 `presence` 不得是 VISIBLE |
| R17 | L2 | EDITTABLE 非空的欄位，FLD 值域必須是 prompt（`%EDITTABLE` 必須有 `dynamic`）；`validation` 與 edit 位元一致；entity 對應 EDITTABLE |
| R18 | L2 | prompt 實體在 keyField 之前的鍵，每個都在 `filter` 以 EQ 綁定，或列在 `unboundKeys` |
| R19 | L2 | FLD 的 `required`、`keyRoles`、`edits`、`format` 與解碼一致 |
| C11 | L3 | 每個 prompt／search 實體有 ENT，其 search key、list box 欄位有 FLD |
| C12 | L3 | `dataLoad`／`dataSave` 為 `BY_CODE` 的區塊有實作規則 |
| C03 擴充 | L3 | 分母改用控制項身分 |

**渲染投影**（外環計算，不派新 ID）

- 05：每個畫面一張元件表（順序、型別、綁定、標籤、必填（取 07）、可改、顯示、值來源／lookup、設計期屬性）；每個 prompt 欄位一節 lookup
  （實體、高階鍵綁定、as-of、顯示欄、搜尋欄、是否檢核、相關顯示）；grid 屬性。
- 09：「系統內建檢核」一節，由 07 `edits` 推導；08 每個 OP 附「本操作涉及欄位的系統檢核」（FR → 元件 → FLD）。
- 05 末：**欄位相依矩陣**——每個欄位「影響它的」與「它影響的」（值、選項、查值、顯示／可改、檢核），由 BR 的 trigger／condition／assignments、
  UI 條件與 optionSets、prompt 的 filter／dynamic、FLD `default` 反查。重建端據此決定哪些欄位要即時回伺服器。

**讀者題**：U2（這個 lookup 的篩選引用了哪些項目；IDS）、U3（這個欄位改了會影響哪些元件或欄位；IDS，答案取自相依矩陣）、
D4（輸入不在清單內的值會怎樣；KIND＝EDIT／NO_EDIT＋實體）。

### 3.8 P2：16 AI 實作指引固定條款

在 `ai-instructions.json` 加固定條款：各種 `edits` 的語意（Required、Prompt edit 依高階鍵與 as-of 查實體、Translate edit 只收有效值、Y/N、Reasonable Date、
System Maintained／Auto-Update）、lookup 的預設行為、相關顯示的刷新、Interactive／Deferred 的時機、No Auto Select／No Auto Update、grid 增刪列。
條款只寫 P0 校準頁實測確認過的行為。

### 3.9 P3：rebuild-kit

`rebuild-kit/docs/build/ps-mapping.md:20` 的 Prompt Table 列展開：lookup API 的參數＝高階鍵綁定＋as-of＋SETID；結果欄＝list box 欄位；
存檔與欄位事件的檢核＝`validation`；回應的 `fieldStates` 加 lookup 與 `optionSets`；按鈕動作；grid 增刪列；相關顯示刷新。

---

## 4. 分期、改動檔案與驗證

| 期 | 內容 | 改動（兩版對應） | 驗證 | 公司機 |
|---|---|---|---|---|
| P0 | cookbook §2l～§2p、profile `pageMetadata:`、SOP-30、偵測清單、ps-ui-flow 現況限制 | `oracle-query-cookbook.md`、`customization-profile.yaml`、`SOP.md`、`skills/ps-peoplecode-flow/SKILL.md`、`skills/ps-ui-flow/SKILL.md`、`agent(s)/ps-ui-flow.md`、applied.md 記課 | ps-agent-doc-lint、test-claude-variant；搬運包重生 | 校準一次（回一行代號） |
| P1 | meta 單元、schema、研究契約、範例 | `ps-sdoc.ps1`、`ps-sdoc-lib.ps1`（單元表、附加資料）、`research-packet.schema.json`、05／07 schema（兩版＋設計目錄）、兩版 `research-contract.md`／`review-contract.md`、`sdoc/examples`（test-sdoc-assemble -WriteExamples）、`scripts/tests/sdoc-test-fixtures.ps1` | test-sdoc、test-sdoc-assemble、test-sdoc-run、5.1 靜態守衛、需要時 Windows 5.1 CI | 一個 Component 首跑 |
| P2 | 解碼帶入、R15～R19／C11～C12、渲染投影、讀者題、16 條款 | `ps-sdoc-check-lib.ps1`、`ps-sdoc-render-lib.ps1`、`ps-sdoc-reader-lib.ps1`、`ai-instructions.json` | 同上，另加刻意破壞（型別不符、唯讀寫成可改、prompt 漏綁鍵） | 同上 |
| P3 | rebuild-kit 對照 | `rebuild-kit/docs/build/ps-mapping.md` 等 | — | — |

schema 改動會改變框架指紋：已在跑的 job 會開新版本，meta、data、ui 單元重研究（其他單元的收據照常沿用與否依現行規則）。

---

## 5. 風險與取捨

| 風險 | 對策 |
|---|---|
| 代碼對照因 PeopleTools 版本而異 | profile 化＋校準；未校準降級為 NOT_APPLICABLE，不猜 |
| 模型轉抄出錯 | SQL 指紋、覆核重跑同一樣板、外環內部一致性（Page 上的 Record 欄位必在 Record 分母裡） |
| 成本（單工 DB、504） | 每個 Page／Record 一條查詢、每頁 ≤40 列；ui／data 單元因預填少查 DB、研究包變小 |
| 屬性收太多＝噪音 | 只收會改變行為或驗收結果的屬性；座標、字型、樣式、寬度不收（順序例外） |
| 系統檢核進覆蓋分母會讓測試數暴增 | 預設只進 16 條款與 05／08／09 投影，不進 C07（見 §6 第 3 題） |
| Fluid 頁 | 不在範圍；profile 改成 CLASSIC_AND_FLUID 時另案 |

---

## 6. 要管理者決定的事

1. **校準**：能否在公司機跑 §2l 探勘與校準頁（只回 PeopleTools 欄位名與代碼數字）？
2. **metadata 取得方式**：維持「模型轉抄＋外環驗指紋」，或允許 PowerShell 直接用 SQLcl 已儲存連線跑固定 SELECT？
3. **系統內建檢核**要不要進 08 檢核清單與 14 反例的覆蓋分母（C08／C07）？
4. **範圍**：只做 Classic；屬性只收行為類（§3.5 的清單）——同意與否？
5. **順序**：建議 P0 先做（不改 schema、可先上線），P1＋P2 等校準結果一起做。

---

## 附錄 A：待校準的表欄

| 表 | 已在 cookbook 使用（可沿用） | 待探勘 |
|---|---|---|
| PSPNLFIELD | PNLNAME、PNLFLDID、FIELDNUM、FIELDTYPE、PNLFIELDNAME、RECNAME、FIELDNAME、SUBPNLNAME、LBLTEXT、LBLTYPE、LABEL_ID、OCCURSLEVEL、FIELDLEFT／TOP／RIGHT／BOTTOM、PTHIDEFIELDS | 使用旗標欄、相關顯示／display control 欄、按鈕目標欄、radio 值欄、checkbox 值欄 |
| PSRECFIELDDB | RECNAME、FIELDNAME、FIELDNUM、EDITTABLE、DEFRECNAME、DEFFIELDNAME | edit 位元欄、set control 欄 |
| PSDBFIELD | — | 型別、長度、小數、格式、format family |
| PSPNLGRPDEFN | PNLGRPNAME、SEARCHRECNAME、ADDSRCHRECNAME | 模式旗標、處理模式 |
| PSPNLGROUP | PNLGRPNAME、PNLNAME、ITEMLABEL | 順序、隱藏 |
| PSRECDEFN | RECNAME、RECTYPE、SQLTABLENAME、RECDESCR | set control 欄 |
| view SQL 所在表 | — | 表名、類型欄 |

FIELDTYPE 只有 2＝Group Box、11＝Subpage 已在 cookbook 使用；其餘代碼一律由校準取得。

edit 位元的常見對照（**未在公司環境驗證**；只當校準的候選，核對後才可回填）：
1 Key、2 Duplicate Order Key、4 System Maintained、8 Audit Field Add、16 Alternate Search Key、32 List Box Item、64 Descending Key、128 Audit Field Change、
256 Required、512 Translate Table Edit、1024 Audit Field Delete、2048 Search Key、4096 Reasonable Date、8192 Yes/No Table Edit、16384 Prompt Table Edit、32768 Auto-Update。

## 附錄 B：要以校準頁實測確認的標準行為

| 行為 | 一般認知（待確認） | 影響 |
|---|---|---|
| prompt 高階鍵 | 被編輯欄位之前的鍵，取 component 內同名欄位的值過濾 | R18、`filter` |
| SETID prompt | 依 set control 欄位查 TableSet 得 SETID | `setControl` |
| 有效日 prompt | 以所在列的 EFFDT（沒有則今天）取有效列，可能只列有效狀態 | `effectiveDating` |
| Prompt Table Edit | 清單外的值被擋；No Edit 則放行 | `validation` |
| Reasonable Date | 日期離今天太遠時警告（不擋） | 16 條款 |
| `%EDITTABLE` | prompt 表名取自哪個工作欄位 | `dynamic.selector` |

---

## 7. 管理者回饋後的調整（2026-10-14）

管理者回饋三點：先用 SQL 驗證（給 SQL、說明怎麼看，管理者回報符不符合）；P0／P1 的意思；改走補查，讓之後的研究一併找出並存起來。

### 7.1 先用 SQL 驗證

- **第一輪**：`ui-metadata-check-r1.md`（說明）＋`ui-metadata-check-r1.sql`（整份可一次跑）。驗表與欄位在不在、PeopleTools 版本、欄位型別代碼、Record 型別代碼、
  Record 欄位 edit 位元（以 EDITTABLE、translate 值、欄位型別、鍵、search record 交叉核對）、頁面元件型別代碼（以綁定欄位的型別、translate 值、
  同欄位重複、SUBPNLNAME 交叉核對）、prompt 的分布。多數段落自己標 OK／CHECK，回報只有代碼與數字。
  已在本機以合成資料驗過：假設成立時全 OK；把位元（16384↔8192）或元件代碼（7↔8）對調時，對應項目標 CHECK。
- **第二輪**（等第一輪結果）：管理者熟悉的一個 Classic 畫面逐欄核對解碼（只回對不上的 FIELDNUM）、設計期屬性的位元（唯讀、隱藏、相關顯示、必填）、
  Component 的可用模式與處理模式、prompt 行為在 PIA 實測（清單外的值、有效日 prompt、上層欄位過濾）。
- 兩輪的結論回填 profile `pageMetadata:`（§3.2），applied.md 記觀察值與日期。
- **第一輪結果（公司環境，2026-10-16，部分）**：V1 表都看得到；V3 候選欄位全部存在（含第二輪要用的 PSPNLFIELD.FIELDUSE／PNLFIELDNAME／LBLTYPE、
  PSRECFIELDDB.USEEDIT2／SETCNTRLFLD／DEFGUICONTROL、PSDBFIELD.FORMAT／FORMATFAMILY、PSRECDEFN.SETCNTRLFLD、PSPNLGRPDEFN.ACTIONS、
  PSSQLTEXTDEFN.SQLTYPE／SQLTEXT）；V4a、V4b 全 OK、V4c 全 0（PSDBFIELD.FIELDTYPE 0／1／2／4／6 與 RECTYPE 0／2 的對照成立）。
  V2、V5、V6、V7 報 ORA-00942：在 SQL Developer 手動跑時沒設 CURRENT_SCHEMA，帳號只有部分表有同義字（PSDBFIELD、PSRECDEFN 查得到；
  PSSTATUS、PSPNLFIELD、PSPNLGRPDEFN、PSRECFIELDDB 查不到）。說明檔已把設 schema 改成第 0 步，待重跑。
- **第一輪結果（續，2026-10-16）**：V2 PeopleTools 8.59。V5 除 AU 外全 OK——帶 32768 的欄位 98.6% 是日期／時間型（門檻 99 訂太嚴，對應成立；
  其餘 1.4% 視為殘留旗標，實作時 Auto-Update 只認日期／時間型欄位）。已成立的 edit 位元：1 Key、32 List Box Item、64 Descending、512 Translate、
  2048 Search Key、4096 Reasonable Date、8192 Yes/No、16384 Prompt Table Edit、32768 Auto-Update；256 Required、16 Alternate Search Key、
  4 System Maintained 與稽核位元還沒驗。DYN＝4182（PSRECFIELDDB 展開子 record 後的列數）：動態 prompt 很常見，第 3、4 步必做。
  V7：當 prompt 的 Record 7291 個，其中 view 5395（74%）、以 EFFDT 為鍵 1429（20%）、以 SETID 為鍵 372（5%）、EDITTABLE 指向不存在的 Record 107——
  view 的選取邏輯是 lookup 的主體；範圍內出現指向不存在 Record 的 prompt 時開 90 問題。V4d OK（之後的 SQL 以 RECNAME 欄位的 FORMAT 當大寫基準，不寫死數字）。
  V6 第一版對整張 PSPNLFIELD 用分析函數，在 PROD 太久；改成只看客製頁面（名稱前綴走索引）、先分組再彙總，待重跑。
- 管理者用 admin 帳號跑；agent 用的唯讀帳號還沒有這些表的 SELECT。授權清單（14 張 PeopleTools 定義表）與授權後的檢查 SQL 在說明檔「權限」一節；
  agent 依 profile `oracle.currentSchema` 設 schema，不需要同義字。
- **第一輪結果（續，2026-10-19）**：V6 輕量版跑完，CODE 0～9、11 除 Group Box 外全 OK（NONE 也算正常）。Group Box 的 CHECK 判斷是「沒綁 Record 的比例 ≥ 50」——
  但 Group Box 常綁 Record 欄位讓 PeopleCode 隱藏整塊（L92 的情形），這條判斷不準；改以 G1（高度與框內有無元件）確認，待跑。OTHER 那行（其他代碼）待抄回。
  agent 用的唯讀帳號：管理者已授權、手動確認 14 張表都查得到。唯讀帳號執行 `ALTER SESSION SET CURRENT_SCHEMA` 報 ORA-02421——設 CURRENT_SCHEMA 不需要權限，
  02421 是名稱那段寫法不被接受（常見是多了單引號或 `< >`）；正確寫法與「不能設就由 DBA 建同義字」的備案已寫進說明檔，待管理者回報。
  若確認是引號造成，查詢手冊「設 schema」那步要補一句「名稱不加引號」（兩版、記課）——agent 自己執行同一句。
- **第一輪結果（完，2026-10-19）**：G1＝GB_H 153、EB_H −17、GB_IN 98、GB_REC 78、OK——代碼 2 是 Group Box（98% 框內有其他元件；
  78% 綁了 Record 欄位，PeopleCode 控制整塊顯示很常見）。Edit Box 的 FIELDBOTTOM − FIELDTOP 平均是負的：座標的上下語意依元件不同，
  用高度、寬度之前要先查清楚（cookbook §2i 的框內判斷不受影響，GB_IN 就是用它算的）。V3c1 沒有缺欄：cookbook §2h～§2j 用到的
  PNLFLDID、LBLTEXT、LABEL_ID、PTHIDEFIELDS、FIELDLEFT／TOP／RIGHT／BOTTOM 都在。V3c2 太長，改成第二輪的 Y/N 探查。
  其他代碼（客製頁面，`代碼:筆數:旗標`）：10:30:N、12:1088、15:1、16:30:N、18:56:S:N、19:587、21:12:S、23:59:N、24:9:N、25:425:L、27:588:N。
  依旗標推測（待第二輪核對）：12 按鈕／超連結（最多）、18 Secondary Page、19 Grid、21 開 secondary page 的按鈕、25 HTML Area、27 Scroll Area；
  10、15、16、23、24 是版面類或其他按鈕類。第二輪 SQL 在 `ui-metadata-check-r2.md`。
- **第二輪結果（2026-10-19）**：R2A＝NYYYYYYYYN、EXTRA 3——PSPNLFIELD 有 ASSOCFIELDNUM 與 7 個 GOTO 欄（PORTAL、NODE、MENU、PNLGRP、MKT、PNL、
  PNLACTION），沒有 DSPLCNTRLFLD、POPUPNAME；另有 3 個同類樣式的欄位未點名。R2B 挑到的頁面 CODES＝12,19,21,25,27；R2C 管理者跑出來只有代碼 19、
  核對確實是 Grid（應是 R2C 換了頁名，其餘代碼改由第三輪依特徵自動判斷）。唯讀帳號以「擁有者.PSPNLFIELD」查詢正常＝有權限；
  不加擁有者的查法（agent 的寫法）還沒測。第三輪 SQL 在 `ui-metadata-check-r3.md`：R3A 依 SUBPNLNAME／GOTOPNLGRPNAME／是否綁 Record／
  長字元／框內有無元件判其餘代碼；R3B 以 ASSOCFIELDNUM（相關顯示一定唯讀）算 FIELDUSE 的唯讀與 Display Control 位元；R3C 鍵欄位帶 256 的比例。
- **第三輪結果（2026-10-19）**：R3A 沒有 CHECK——12 跑 PeopleCode 的按鈕、16 轉到別的 Component 的連結、18 Secondary Page、21 開 secondary page 的按鈕、
  25 HTML Area、27 Scroll Area 依特徵成立；10（30 筆）、23（59 筆）MIXED，15（1 筆）、24（9 筆）CONTAINER，先列「其他元件（未校準）」。
  R3B：REL_N 1984、97% 是 Edit Box；FIELDUSE 16 在相關顯示幾乎都有、在其他 Edit Box 不到一半＝唯讀位元的最強候選（DO=16）；沒找到 Display Control 位元（DC=NONE）；
  ASSOCFIELDNUM 指到的欄只有 8% 有 prompt（CTL_PROMPT 8），與「相關顯示的控制欄通常有 prompt」不符——對應方式可能差一號或不是這個意思，第四輪 R4A 一次比幾種假設。
  R3C：KEY_REQ 23、NONKEY_REQ 5——鍵欄位不會自動帶 256；256 是不是 Required 改拿已知欄位核對（R4B）。
- 唯讀帳號 A 測試 FAIL（裸表名 ORA-00942）；`ALTER SESSION` 不能用、DBA 不建同義字 → 框架改成每個表名寫 `<schema>.表名`
  （L150、SOP-30；兩版 cookbook 規則 1a 與四個查 DB 的 agent）。本文件之後的 SQL 一律帶 `<schema>.`。第四輪 SQL 在 `ui-metadata-check-r4.md`
  （R4A ASSOCFIELDNUM 對應、R4B 必填位元、R4C 唯讀／隱藏位元、R4D Component 動作、R4E 唯讀帳號缺哪些表）。
- **第四輪結果（2026-10-20，唯讀帳號跑）**：R4A＝ALL N 15154 P 14 R 0；H0 N 1984 P 54 R 22；H2 N 1867 P 13 R 1；NB N 1984 P 41 R 17（H1 沒回）——
  H0 成立：ASSOCFIELDNUM＝相關顯示的控制欄 FIELDNUM（控制欄有 prompt 的比例是全體 Edit Box 的 4 倍；相關顯示的 Record 就是 prompt 表的佔 22%，
  其餘多半是說明由 PeopleCode 或另一個 view 帶出）；NB 偏高是因為控制欄常緊接在相關顯示前面。R4B＝REQ=Y、OPT=N → USEEDIT 256＝Required。
  R4C＝勾 Display Only 的三個欄位都是 BITS 1,16，沒勾的 NONE，Display Only＋Invisible 的是 1,2（公司頁面沒有只勾 Invisible 的）→
  FIELDUSE 1＝Display Only、2＝Invisible；16 不是唯讀（R3B 的 DO=16 改判：16 幾乎只出現在相關顯示，應是 Related Field 旗標；框架改用 ASSOCFIELDNUM，
  不靠 16）。R3B 沒選出 1，是因為一般 Edit Box 超過一半本來就唯讀（門檻 IN_OTH ≤ 50）。R4D＝ACTIONS 2＝只勾 Update/Display → 位元 2＝Update/Display；
  Add、Update/Display All、Correction 的位元還沒核對（分布那行沒回），Component 動作先不進框架。R4E＝32 張表唯讀帳號都看得到。
  → 第 2、3 步開始：cookbook §2l（每個 Page 一次，解碼只用已核對的代碼）、NN 新節「## 畫面元件」、補研究事實類別 UI.CONTROLS（L151）。
- **第四輪後續（2026-10-20）**：管理者確認 ACTIONS 的位元順序（1 Add、2 Update/Display、4 Update/Display All、8 Correction）→ Component 動作與搜尋 Record
  進框架（cookbook §2m，寫成「## 畫面元件」第一列；L152）。R4A～R4D 和官方對照：USEEDIT 與 Oracle PeopleCode API（QueryDBRecordField 的 Flag）一致；
  FIELDUSE 1、2、16 與社群整理一致（Oracle：勾 Related Field 會自動勾 Display Only，對上 R4C 的 1,16）；ACTIONS 與 PSAUTHITEM.AUTHORIZEDACTIONS
  同一組位元；已解碼的元件代碼一致，12／16／21 依按鈕目的地改叫 PeopleCode Command／Internal Link／Secondary Page，5 改叫 Drop-Down List Box。
  對不上的：代碼 10、15、23、24（社群：Scroll Bar、External Link 按鈕、Horizontal Rule、Tab Separator）與 FIELDUSE 8（社群：Display Control；第三輪 DC=NONE）
  → 第五輪 SQL `ui-metadata-check-r5.md`（R5A 特徵＋App Designer 對照、R5B 8／16 與 ASSOCFIELDNUM 交叉）。對照表與來源在第五輪說明檔。
- **第五輪結果（2026-10-21）**：R5A 以 App Designer 確認 10 Scroll Bar、15 External Link 按鈕、23 Horizontal Rule、24 Tab Separator（和社群表一致；
  SAMPLE_NUM 對上 Order 頁籤的 tab order＝FIELDNUM）→ §2l 解碼 10、15、24，23 不列（L153）。R5B＝CTL_N 1105、B8_N 2044、BOTH8 84、REL_N 1984：
  以 tab order 對應的控制欄只有 8% 帶 8，帶 8 的欄位數卻和相關顯示個數相近 → 懷疑 ASSOCFIELDNUM 存的是控制欄的 Field ID（PNLFLDID），
  第四輪 H0 只在沒調過順序的頁面成立。第六輪 SQL `ui-metadata-check-r6.md`（H0 與 H3 同時比、B16 補回）。結果出來前，§2l 的 RELATED_TO、
  DISPLAY_CONTROL 不當定論。
- **第六輪結果（2026-10-21）**：R6＝N 1984、SAME 1005、H0 1984,149,8,97、H3 1697,236,30,339、B16 1984,2177、DUPID 0——tab order（H0）與 Field ID（H3）
  找到的控制欄有 Prompt 的比例都在一般 Edit Box 水準、帶 8 的少：兩種都不對。帶 16 的比 ASSOCFIELDNUM 大於 0 的多 193 個（那些 ASSOCFIELDNUM＝0）。
  新假設 ASSOCFIELDNUM 從 0 起算（控制欄 tab order＝ASSOCFIELDNUM＋1）；R4A 回報的 H0 數字應是 H1 那一行。第七輪 `ui-metadata-check-r7.md`
  （改用 16 挑相關顯示，比 tab order＋1 與 Field ID＋1；可選 App Designer 對一個例子）。管理者另指示：驗證只確認代碼意思、不盤點數量（L155）。

### 7.2 改走補查與知識層（取代 §3.4 只活在 Spec job 裡的 meta 單元）

- **研究**（`/ps-research`）：NN 的「畫面與欄位」一併記元件型別、設計期屬性、查值（prompt：會不會檢核、高階鍵、有效日、SETID、動態 prompt、lookup 欄位）；
  「行為邏輯」一併記欄位間相依（值、選項、查值、顯示／可改、檢核）。之後研究的新 NN 自動帶這些內容。
- **補查**（`ps-supplemental`，SOP-23）：已畢業或已有 NN 的物件，以新的事實類別送補研究工單（暫名 `UI.CONTROL_DETAIL`、`UI.LOOKUP`、
  `BEHAVIOR.FIELD_DEPENDENCY`，加進 `spec/capabilities.json`），迷你圈委派 ps-ui-flow／ps-peoplecode-flow 查，外環只追加地合併進 NN，照常稽核、畢業、
  投影 wiki、進知識索引。查法收據（可重跑的 SELECT）跟著 NN 走。
- **Spec 文件**：ui／data 研究單元照現行契約先讀知識層（KNOWLEDGE），知識層沒有或過期才現查；外環的比對（§3.7 的 R15～R19）取知識層或 Spec 分母的解碼結果。
  知識層缺料時要不要由外環自動送補查，跟 SPEC1 的 `ps-spec -Plan` 自動提交一樣做，第 4 步再定。
- **要先處理的相容性**：「畫面與欄位」那張 5 格表（欄位｜顯示文字｜類型｜選項｜生命狀態）被 3 處直接解析——補研究合併（`ps-supplemental-lib.ps1` 的節格式）、
  知識索引（`ps-knowledge-lib.ps1`，整節的表格列都算欄位列）、CLONE1 抽取（`ps-spec-lib.ps1`）；NN lint（`ps-doc-lint.ps1`）只檢查這節存在。
  新內容要另起子節或新節、不改那張表的格數，並讓這 3 處只讀自己那張表；格式在驗證後定。

### 7.3 新的順序

| 步 | 內容 | 取代 |
|---|---|---|
| 第 1 步 | SQL 驗證兩輪（§7.1），結果回填 profile | P0 的校準 |
| 第 2 步 | 查法進框架：cookbook 新節、profile 對照、PeopleCode 偵測清單（§3.2、§3.3） | P0 其餘 |
| 第 3 步 | 知識層：NN 格式、研究規則、補查的事實類別、四處解析相容（§7.2） | P1 的 meta 單元 |
| 第 4 步 | Spec 文件吃知識層：schema 擴充、研究契約、外環檢核、渲染投影、讀者題、16 條款（§3.5～§3.8） | P1 其餘、P2 |
| 第 5 步 | rebuild-kit 對照（§3.9） | P3 |
