# 教訓歸檔（applied）

> `/ps-lesson` 直接套用的教訓逐筆記錄於此（症狀／根因／落點／實際修改摘要）。
> 本機套用即生效；**團隊生效以內部 git PR merge 為準**（SOP-1）。
> 本檔是歷史紀錄，**不載入任何 agent 的 context**。

### L0 純 prose 規則對小模型效力最弱（2026-07-24）
- 教訓：本專案調校期間效果最好的修復全是機械化的
  （tools deny、UUID 格式判定、行號覆蓋檢查），效果最弱的全是純 prose
  規則——promotion 時永遠先問「這條能不能機械化」。
- 落點：pending.md 的落點分類優先序即由此而來。
- 套用：設計原則，無單一 commit。

### L1 新註冊的 MCP server 預設全開，繞過 subagent 架構（2026-07-27）
- 症狀：主 agent 畫面直接出現 `PeoplecodeMe(e)tadata_find_field_usage`
  呼叫，未經委派；主 context 被工具結果灌大。
- 根因：OpenCode tools map 是**覆寫表**（沒列＝預設開）。agent 檔只
  deny 已知三個 server，新註冊的第四個不在名單上 → 九個 agent 全部
  預設可用。附帶風險：其回傳塞不進 CHUNK/SQL 證據契約，會再度誘發
  捏造證據（同 SQL-XLAT-1 型）。
- 落點：機械化（tools deny）——9 個 agent 檔全加
  `"PeoplecodeMetadata_*": false` 與 `"PeoplecodeMeetadata_*": false`
  （確切拼法待管理者確認，多列無害）；SOP-8 加「新增 MCP 先全面
  deny」檢查項；test-scenarios 加 F4。
- 套用：本 commit；後續正式整合（預定歸 ps-metadata-flow）待管理者
  提供該 server 的確切註冊名與完整工具清單。
- 後續（2026-07-27）：管理者確認註冊名為 `PeoplecodeMetadata`（單 e）→
  已移除九檔的 `PeoplecodeMeetadata_*` 備援項；正式整合仍待完整工具清單。
- 正式整合（2026-07-27）：工具＝`find_field_usage`（fieldName／pageName／
  componentName）與 `search_component_metadata`（keyword）。開放給
  ps-ui-flow／ps-metadata-flow（定位優先步驟）與 ps-auditor（任務 C
  反查角度）；**定位線索不作 evidence**（契約仍僅 CHUNK／SQL 兩種），
  其餘 agent 維持 deny。測試情境加 F5。
- 補強（2026-07-27）：自製索引不保證完整 → 空／稀少結果不得當
  「不存在」證據，必回退 cookbook／ES 正規管道；auditor 任務 C 需
  兩角度交叉才可列疑似遺漏；F5 加對應檢查點。
- 追記（2026-07-27）：server 第三個 tool `get_ae_sql_metadata`
  （aeApplid）→ 開放 ps-ae-flow（AE 結構定位優先）與 ps-metadata-flow
  （批次血緣鑽查）；同樣定位不作證、空結果必回退。
- 修正（2026-07-27）：管理者澄清**查詢鍵只有「欄位名」與「Component
  關鍵字」**（AE tool 只吃 AE 名）——Page／Record／選單名帶入必查空。
  原文件誤把 pageName／componentName 列為 find_field_usage 可查參數，
  已全數改正；ui／metadata-flow 與 auditor 加「輸入類型限定」硬規則
  （帶錯類型＝方法錯誤，不是「不存在」，改走 cookbook §2／§6 對映），
  F5 加對應檢查點。

### L2 write 工具呼叫 JSON 被截斷——大檔整檔覆寫超出小模型可靠輸出長度（2026-07-27）
- 症狀：持續出現 invalid[tool=write, error=... JSON Parse error
  expected '}']，寫入反覆失敗。
- 根因：整檔覆寫讓單次工具呼叫 JSON 隨檔案長大而變長，超過小模型
  可靠輸出長度即被截斷、JSON 沒閉合。與先前的三反引號圍欄汙染不同源。
- 落點：機械化——(1) 進度／Gaps 拆到獨立小檔 checklist.md，
  00-overview.md 階段一後凍結（agent／command／模板／lint／SOP-6
  同步改，舊領域自動遷移）；(2) 單次寫檔約 150 行上限、超過拆續篇；
  (3) 新增 SOP-9 服務端排查（輸出 token 上限、tool-call 約束解碼）。
- 套用：本 commit；測試情境 G1／H1 對齊、G2 加「00-overview 零改動」
  檢查點。

### L3 稽核只寫記分卡、跳過回灌——交付物完成後尾端步驟被丟（2026-07-27）
- 症狀：/ps-audit 產出 90-audit.md（PASS 8／FAIL 2／PARTIAL 2）後即
  結束，checklist 沒有任何 A<n> 補查行；且模型自創契約外狀態
  partial_pass。
- 根因：小模型寫完主要交付物即視為任務完成，排在其後的步驟（回灌、
  自檢）被靜默丟棄——與「複述計畫就停」同族。
- 落點：機械化順序——回灌**先於**記分卡（非 PASS ≥ 1 而 checklist
  無新 A 行＝禁止寫 90-audit.md）；回灌對象改「任何非 PASS 判定」
  （網住自創狀態）；命令加結束前 read checklist.md 自檢；模板加
  順序約束註記；H1 改致命檢查點＋狀態詞彙檢查。
- 套用：本 commit（ps-deep-research／ps-audit 命令／audit-template／
  test-scenarios H1）。
- 後續確認（2026-07-27）：舊版 90-audit 的「已回灌」節其實列好了
  5 個 A 項——模型**在報告裡聲稱已回灌，實際檔案一行未寫**
  （填表代替做事：模板有該節，就把它當一般章節填完）。遷移時已把
  這 5 項搬進 checklist.md。新順序（checklist 先寫、報告節只准抄錄
  實際行）＋結束前 read 自檢即針對此機制。

### L4 第二輪稽核沒重驗——記分卡數字原封不動（2026-07-27）
- 症狀：消化完 A 項、全數打勾後結束，90-audit.md 與上一輪完全相同
  （自創章節與 partial_pass 原樣保留）＝報告未重寫。
- 根因：(1)「總計 2 輪上限」**沒有持久化的輪次可查**——跨 session
  模型看到 90-audit.md 已存在，即可判定「稽核做過了」跳過；
  (2) 勾完 A 項「感覺完成」，收尾自動稽核是尾端步驟再度被丟
  （L3 同族）；(3) 沒有「禁止沿用舊報告」規則，就算重寫也可能抄舊數字。
- 落點：機械化——(1) 觸發改「本 run 勾過 A 項或全勾且未稽核 → 必須
  稽核」，明文「90-audit.md 已存在不是跳過理由」；(2) 輪次持久化：
  checklist.md 記「稽核輪次：N」，每輪 +1 並寫進報告表頭（新鮮度
  肉眼可驗）；(3) 上限改「單次 run 最多一輪」，不需跨 session 計數；
  (4) 判定只准來自本輪 auditor 回報，禁止 read 舊 90-audit.md；
  (5) H1 加致命檢查點（輪次未 +1＝抄舊帳）；lint 警缺輪次表頭。
- 套用：本 commit（ps-deep-research／兩個命令／兩個模板／README／
  test-scenarios H1／lint）。

### L5 首輪全量稽核量大：回灌改以檔彙整；自創判定詞就近映射（2026-07-27）
- 症狀：輪次 1 真實重驗產出 84 筆證據判定（58 PASS／10 FAIL／
  16 UNVERIFIABLE）＋48 筆 claim 判定（19 VERIFIED／29 筆用自創詞
  weakened/contradicted）。非 PASS 共 55 筆——逐筆回灌會塞爆
  checklist.md（回到大檔覆寫→JSON 截斷的老問題）；自創詞再現
  （堵不完，改吸收）。
- 落點：機械化——(1) 回灌單位改「一檔一行」彙整（上限＝檔案數），
  禁止逐筆開項；(2) 自創判定詞**就近映射**（claim 層→DISPUTED、
  證據層→FAIL），lint 擴充詞彙警告；(3) A 項處理規則明確化：FAIL
  重取證、DISPUTED 二選一（補證據保 CONFIRMED 或降級 INFERRED，
  不得原樣保留）、UNVERIFIABLE 重驗一次不迴圈。
- 套用：本 commit。
- 解讀備忘：首輪 69% 證據存活率屬正常起點；29 筆 DISPUTED 中預期
  相當比例是 9B 稽核員把「找不到支持」誤標為「矛盾」——定向補查後
  會翻回或正確降級。指標看輪次間趨勢，不看單輪絕對值。
- 追記（2026-07-27）：輪次 1 報告 16 筆 UNVERIFIABLE **全無明細與
  原因**——根因是模板缺陷：明細節標題只寫「FAIL / DISPUTED」，9B
  照格子填表，沒開格子就不寫。模板改「FAIL / DISPUTED / UNVERIFIABLE
  明細」＋範例列＋「每筆一列、原因逐字取自 auditor 回報」；step 4 與
  H1 加對應要求。原因欄是判斷環境問題（逾時類）vs 資料問題的依據。

### L6 認知修正：目標模型實為 Qwen3.6-35B-A3B（262K），非 Qwen 3.5 9B（2026-07-27）
- 事實：管理者確認地端模型為 Qwen3.6-35B-A3B（262K context）。依
  Qwen 命名慣例，A3B＝MoE 每 token 活躍參數約 3B——知識廣度屬 35B
  級、**程序紀律屬 ~3B 小模型級**，與觀察到的失敗光譜完全一致
  （內容會寫、程序會掉：唸而不做、填表代做、丟尾端步驟、自創詞、
  長 JSON 截斷）。
- 影響評估：**全部機械化規則維持不變**——每一條都源自本模型實際
  犯過的錯（非 9B 規格推測），對更強模型亦無害。
- 本檔先前條目中的「9B／小模型」字樣一律實指本模型；歷史紀錄
  不回改（作廢不刪除原則）。
- 待查環境疑點：(1) 早期「context 很快用滿」與 262K 不符——檢查
  serving 端 context 上限（如 num_ctx 類設定）是否遠小於 262K；
  (2) write JSON 截斷屬「輸出 token 上限」問題，與 context 無關，
  SOP-9 兩槓桿（加大輸出上限＋約束解碼）仍為最高價值環境修法。
- 套用：test-scenarios／README 的型號字樣已更正；原始需求 spec 與
  lessons 舊條目保留原樣。

### L7 輪次 2 報告被「覆核上輪判定」取代——想寫的東西沒格子就掀桌（2026-07-27）
- 症狀：輪次 2 機制全對（輪次 +1、回灌先行），但 90-audit.md 記分卡
  被「Auditor 正確 5／部分不可查 2／Auditor 有誤 4」取代——模型整輪
  在處理 A 項，就把「上輪判定 vs 我的覆核」寫成整份報告，全量記分卡
  消失。
- 價值發現：覆核數據本身很有用——**稽核員誤報率 4/11 ≈ 36%**，證實
  DISPUTED 灌水假說；文件真實缺陷 ≈ 5，非 55。
- 落點：模板加「上輪回灌項覆核」節（屬實／誤報／不可查，第 2 輪起
  必填）**給它格子**；同時明文「該節不取代記分卡；記分卡＝本輪全量
  重驗數字」「稽核範圍＝全部已打勾項」；H1 加致命檢查點（僅覆核無
  全量＝不合格）；lint 章節清單同步。
- 原則收錄：模板沒開的格子它不寫；想寫的沒格子它就換掉整張表——
  **兩個方向都要開格子**。
- 套用：本 commit。

### L8 task 委派 JSON 截斷——整份檔案被貼進委派 prompt（2026-07-27）
- 症狀：invalid[tool=task, json parsing failed]，出現於寫完領域
  markdown 之後（打勾前快驗附近）。
- 根因：與 L2 同族（單次輸出過長被截斷）——模型剛寫完檔，順手把
  整份內容貼進給 auditor 的委派 prompt。auditor 本就有 read 權限
  （任務 A 第一步即「Read 目標檔」），委派只需要檔案路徑。
- 落點：機械化——委派瘦身規則（prompt 約 30 行上限；禁貼檔案／
  報告全文；驗檔委派只傳路徑）；task 失敗 → 縮短重委派、失敗 2 次
  標 ⚠ 跳過；SOP-9 補條目；新增 F6 測試情境（總數 37）。
- 套用：本 commit。
- 探針結果（2026-07-27）：輸出上限探針**能完整數到 3000**（輸出
  ≥ 約 8K tokens）——輸出 token 上限**不是**瓶頸。截斷／壞格更可能
  是「長結構化 JSON 的格式可靠度」問題（A3B 長輸出時跳脫／閉合
  出錯機率隨長度上升）。結論：瘦身與小檔規則維持不變（治發生面）；
  伺服器端唯一高價值槓桿＝ **tool-call 約束解碼**；不必追「加大
  輸出上限」。
- 追記（2026-07-30）：輸出偶見 `</think>` 等內部標記洩漏＝chat
  template／reasoning parser 未對齊（Qwen3 系混合思考模型），且
  是 JSON 壞格的可能來源之一。SOP-10 加對齊檢查與「關閉 thinking」
  評估項（工具密集用途通常更穩更快）；lint 加髒標記污染檢查。

### L12 一檔一行工單讓「紙上打勾」有機可乘——id 修復改走 lint 清單手術式（2026-07-30）
- 症狀：A29~A39 兩批跑完＋輪次 6 稽核，lint 縮寫 id 僅 14→13
  （幾乎未修），且一檔被破壞性覆寫（新增 3 筆缺章節）。
- 根因：per-file 彙整工單粒度太粗——模型「處理過該檔」即可打勾，
  檔內逐筆的 id 修復被靜默跳過；「逐字取回傳」規則存在但**缺交付
  驗證**（沒有人核對修了哪幾筆）。
- 落點：(1) **修復必附收據**：舊→新 id 對照表，無收據不得打勾；
  (2) **lint 清單驅動**：把 lint 輸出的 檔×id 清單直接貼進指令
  逐筆處理（原子化、可核對、模型不需自己找目標）；(3) 修復波
  前後各 commit 內部 git（快照）；(4) 受損檔走 SOP-4 部分還原；
  (5) 輪次 6 報告視為不可信，lint 歸零後以新 session /ps-audit
  重測（輪次 7）作畢業依據。
- 套用：本 commit（agent 硬規則／SOP-2）。
- 結果驗證（2026-07-30）：手術式一次修復 **13/13 全數成功**。
  成功要因＝拿掉模型的「自主發現」段、粒度降到原子、收據交付、
  lint 前後驗收。**通用原則入庫：確定性工具負責「找目標」與
  「驗結果」，模型只負責中間非它不可的工具操作**——任何
  「叫模型修東西」的場景都適用此形。
- 輪次 7 里程碑（2026-07-30）：首份全合規＋健康文件的全量體檢——
  證據 PASS 83%（91/110，趨勢 69→78→73→83）、UNVERIFIABLE 僅 3、
  縮寫 id 類 FAIL＝0。殘餘 FAIL 16（新組成待原因分類）與
  DISPUTED 28/68（41%，回到稽核員噪音帶）進入人工抽驗畢業程序：
  真問題定向收尾、噪音行政結案（打勾＋⚠人工判定誤報）並以本輪
  數字為該領域基準地板。
- 措辭更正（2026-07-30，管理者指正）：縮寫 id＝0 是**存量清零**
  （手術修復的成果），**不是類別根除**——寫入端防線（模板範例＋
  禁縮寫規則）尚未經歷大量新寫入的實戰。驗證計畫：斷鏈補課的新
  entity 檔（首戰）與新領域首輪 research（第二戰）寫完各跑 lint，
  新檔持續乾淨才可宣告根除。原則：**修好存量 ≠ 堵住流量，
  兩者要分開驗證**。

### L13 輪次 7 FAIL 16 的三家族——lint 盲區、稽核過嚴、手術缺驗貨（2026-07-30）
- 症狀分類：(A) 截斷 id 仍現身稽核＝**lint 盲區**（只掃「ChunkId」
  前綴寫法，表格等其他位置的 8 碼漏抓，手術只修了看得見的）；
  (B) case mismatch／wrong_line／count_mismatch＝**稽核過嚴＋時效**
  （程式碼大小寫不敏感；quote 命中行號漂移；線上 DB 筆數本來會變）；
  (C) data flow 表無 chunk id、修復 id 內容不符 claim＝**真缺陷**
  （證據義務未履行；手術重取抓錯 chunk 仍硬填——缺「回傳必含原
  quote」的驗貨步驟）。
- 落點：機械化——(1) lint 廣域截斷偵測（任何位置的獨立 8 碼 hex
  含字母者）；(2) auditor 比對正規化（大小寫不分、空白摺疊）＋
  PASS(LINE_DRIFT)＋FAIL(STALE_DATA)（時效與造假分流）；
  (3) 修復前驗貨：重取 ChunkText 必含原 quote 才准寫入，抓錯禁止
  硬填；(4) STALE_DATA 修法＝更新數字。
- 待決：ES 查無那批取決於「索引近期是否重建」（是→SOP-11 正常
  死亡重取；否→id 本身有誤）。
- 套用：本 commit。
- 抽查解謎（2026-07-30）：「ES 查無」實為**假死**——程式碼存在，
  是 Component 事件（PreBuild／PostBuild）。死因＝定位鍵用錯：
  Component 層級 PeopleCode **沒有 Record.Field**，正確路徑＝
  Component 名搜檔 → get_file_structure → 按 Event 挑單元；拿事件名
  當全庫關鍵字＝滿庫都是、等於沒搜。落點：peoplecode-flow 加
  Component 事件定位鍵規則；auditor 判 NOT_FOUND 前強制「二次定位」
  （用 evidence 自帶的 filePath／ObjectName／EventName 重找），
  找回→FAIL(ID_RELINK) 附新 id（修法＝換 id，最便宜）。
- 再深挖（2026-07-30，管理者抽查）：被喊查無的 id **本身有效**
  （確為該 event 13 個 chunk 之一）→ 稽核員根本沒直接解引用，
  而是用搜尋／瀏覽「看到與否」代替——ES 一頁 10 筆、event 有 13
  chunk，尾巴 3 顆永遠不在第一頁。**分頁紀律（單頁 ≠ 全部）當年
  教了研究 flows，稽核員漏打疫苗**。落點：auditor 明文「解引用
  一律直接 get_chunks_details(ChunkId)，禁止以搜尋有無代替」＋
  二次定位全程綁分頁紀律（§5.1）。原則：**新 agent 上線時，共用
  檢索紀律要逐一確認有綁，不會自動繼承**。

### L24 ES MCP 程式 bug 造成假查無——歷史判定修帳（2026-08）
- 事件：lint 手術期間，管理者發現某 Component event 的 peoplecode
  「ES 查無」但實際存在——追查為 **PeoplecodeElasticSearch MCP
  程式錯誤**，已修復、可正常查得。
- 歷史修帳：過去「ES 查無」類判定（文件 gaps 的查無、稽核
  NOT_FOUND、部分假死案）**多了一個共犯**——先前歸因的定位鍵／
  分頁行為問題仍真實，但部分案例的主因可能是本 bug。冤案由
  「稽核二次定位＋已修復的 MCP」在後續 audit／補課輪自動平反，
  不開專案式重查。
- 落點：SOP-8 加「MCP 程式修改」對齊檢查項（直通測試各 tool；
  檢索類修復→歷史查無帶嫌疑；重建索引→走 SOP-11）。
- 原則：**工具鏈本身也是嫌疑人**——連續出現「不合理的查無」時，
  除了模型行為與資料，第三個要查的是 MCP server 程式。
- 套用：本 commit。
- 追記（管理者實測揭露真空區）：MCP 修復後重跑 lint，錯誤的
  「查無 PreBuild、可用 PostBuild 替代」敘述**未被平反**——lint 只驗
  格式、audit 任務 A/B 只驗既有證據與正面主張，**負面宣告寫入後
  無任何機制重測**（先前「下輪自動平反」的說法錯誤，修帳）。
  堵法：(1) 寫入端「查無必附查法收據」（無查法不得寫查無）；
  (2) auditor 任務 A 新增「查無宣告抽驗」→ 查得到判
  FAIL(FALSE_NEGATIVE) 回灌補查；工具鏈修復後首輪**全量**抽驗
  （歷史平反機制）。本案個案：/ps-correct 修敘述＋SOP-6 手加
  補查項實查 PreBuild。

### L23 畢業宣言——寫入攪動地板與維運模式（2026-08）
- 判定：PASS 率 86%（史上最高）、FAIL 於 6↔12 帶區震盪、殘餘全為
  已知慢性類——達成收斂判準。「感覺沒盡頭」的機制解釋：**修復即
  寫入，寫入以低固定率播新小瑕疵**（寫入攪動地板）；research 後
  緊接 audit 的衝刺迴圈＝永動工單機。
- 處置：首領域**畢業**。收尾批次（lint 手術清縮寫存量＋欄位錯待
  cookbook 規則 8 後修＋其餘 A 項行政結案）→ 轉維運模式（SOP-13：
  問答隨時、lint 每寫入波、research 按需、audit 僅 CR 後／月度）。
- 慢性類策略入帳（回應稽核的兩個 lesson 提議，不另開）：
  truncated-chronic＝lint 手術按波清理，不為它跑稽核；
  wrong-column 類＝cookbook 規則 8「查詢前欄位驗證」（不確定欄位
  先查 all_tab_columns，禁憑記憶）。
- 記分卡格式仍會飄（本輪又回總數式）——資料在就不追殺，lint 章節
  警告持續留痕即可。
- 套用：本 commit。

### L22 「過簡」不是反駁——深度建議與品質缺陷分流（2026-08）
- 症狀：15 檔 9 紅燈，但證據層僅 FAIL 6／UNVERIFIABLE 2（史上最
  健康）；紅燈大戶＝DISPUTED 12，主力為「過於簡化的業務描述」
  集中五檔。
- 判定：「寫得太淺」提不出事實矛盾點，依 L14 前提本就不合法
  DISPUTED——敘述為真、只是不夠深，屬**編輯建議**非品質缺陷。
- 落點：auditor 明文「過簡 → VERIFIED＋gaps 建議補充；不得
  DISPUTED、不染紅、不生成強制工單」。五檔要不要加深＝管理者的
  產品決策（可作選配批次）。
- 附：PS_ 假說經管理者抽驗證實（36 筆全為 PS_TW_XXX 自家表）——
  task C 覆蓋帳待下輪正規化重判後翻正。
- 套用：本 commit。

### L21 task C 首跑的三個發現——PS_ 前綴比對假象、空白附錄盲區、合計列（2026-08）
- 發現：(1) 「37 筆核心表 36 筆未覆蓋」高度可疑——SQL 表名帶
  `PS_` 前綴、文件寫 Record 名，逐字比對必然全滅（待管理者抽 3 筆
  驗證）→ auditor task C 加正規化規則（去 PS_、大小寫不分、
  [[連結]] 算出現），未正規化的未覆蓋清單無效；
  (2) 某檔 Evidence 附錄「有標題無內容」——lint 只驗章節存在
  → 加空白附錄違規檢查；(3) 記分卡回到正版一檔一列格式但無總數
  → 模板加「合計」列。
- 處置：A80~A87 中「遺漏表」類先擱置（等正規化後下輪重判）；
  縮寫×2／SQL 欄位錯×3／五檔過簡描述／空白附錄照常消化。
- 套用：本 commit。

### L20 checklist 熱檔會隨輪次肥大——已勾項歸檔（2026-08）
- 症狀（管理者預警）：調查進度隨每輪稽核回灌累積 A 項、已勾項
  永留 → 整檔覆寫的 JSON 隨歷史變長，走回 L2 截斷老路；找
  「第一個未勾項」的掃描噪音也隨之增加。
- 落點：機械化——每輪稽核回灌時把所有已打勾項 append 到
  `checklist-archive.md`（冷檔，永不回讀），checklist.md 常態只留
  輪次行＋未勾項＋Gaps；lint 對帳改「checklist＋archive 合併」。
  現存肥檔於下輪稽核首次歸檔時自動瘦身。
- 原則：**熱檔（反覆整檔覆寫）必須有歸檔機制，否則終將肥死**
  ——log.md／applied.md 的「冷熱分離」哲學套用到 checklist。
- 套用：本 commit。

### L19 oracle 裸表名查不到——CURRENT_SCHEMA 機械化（2026-08）
- 症狀：稽核 FAIL 7 筆「view 不存在」；管理者實測加 [schema].TABLE
  前綴即查到＝cookbook 樣板用裸表名、登入帳號不是 PeopleTools 表的
  擁有者。可能同時解釋歷史部分 UNVERIFIABLE(view 不可用)。
- 落點：機械化——連線生命週期插入第 3 步「ALTER SESSION SET
  CURRENT_SCHEMA=<local-env.yaml 的 oracle.currentSchema>」
  （唯一准許的非 SELECT；一次設定、全程裸表名照舊——遠優於要求
  小模型每句加前綴）。schema 實名屬機敏 → local-env.yaml 本機檔
  （.gitignore 擋、人工搬運不覆蓋；example 範本入 repo）。
  三個 flow agent＋auditor 生命週期同步更新。
- 另修：auditor 原因欄「寫人話」標準（管理者反映 E5/E6 類代號
  不可讀）——固定格式「文件說／實際取到／差異」。
- 本輪其餘三類系統性（LINE_DRIFT／ID_RELINK／QUOTE 類）已由 L18
  三鐵律與修法選單覆蓋，未重複開 lesson。
- 修正（管理者）：本案 schema 名**非機敏** → 淘汰 local-env.yaml
  機制，設定移入 customization-profile.yaml 的 oracle.currentSchema
  （隨 repo 搬運、免額外人工步驟）。
- 套用：本 commit。

### L18 證據格式三鐵律——本機 /ps-lesson 首次自主產出、PR 收編（2026-08）
- 來源：地端模型執行 /ps-lesson（稽核三類系統性 FAIL：無 id 檔案
  行號型／行號飄移／8 碼縮寫）自主分類並套用——落點選擇正確
  （契約＋稽核模板＋測試檢查點）、未越界碰 scripts/、有記帳。
  **H2 現場測試通過**。
- 內容（收編後正式版）：證據三鐵律——(1) CHUNK 必附完整 36 字元
  id；(2) 行號對應當前內容；(3) 全欄位禁止縮寫、逐字取自工具回傳。
  缺一放 gaps 不入 findings。落點：subagent-report-contract／
  audit-template FAIL 詞彙表／F7 測試情境（總數 39）。
- 治理備註：本機帳本曾將此課編為 L16，與 repo 的 L16（/ps-correct）
  **撞號**——人工搬運期間兩本帳各自生長所致。以 repo 為準收編為
  L18；本機 applied.md 以整檔覆蓋歸一。原則：**流水號以 canonical
  repo 為準；本機產出的教訓經 PR 收編時由審核者定號**。
- 套用：本 commit。

### L17 oracleMCP 跨視窗搶用——單通道紀律（2026-08）
- 症狀：問答常回「OracleMCP 無法執行 SQL」；輪次 9 稽核 5 筆
  UNVERIFIABLE(view 不可用) 同族。
- 根因：SQLcl 單一有狀態連線；使用模式常「一邊跑稽核一邊問答」，
  兩個 OpenCode 視窗互不知情地搶同一通道 → connect 卡死／逾時。
  序列化規則只管單 session 內，跨視窗管不到（也管不了）。
- 落點：(1) SOP-12 單通道操作紀律（一次一個 oracle 使用者＋快篩
  三步）；(2) orchestrator 轉譯規則——BLOCKED 不得說成「無法執行
  SQL」，照實說「通道忙碌，稍後重試」並照常回答非 DB 部分。
- 附註：wiki 補課完成後，多數資料題可由 verified 條目直接回答，
  對 oracle 的依賴會自然下降。
- 套用：本 commit。
- 修正（2026-08，管理者實驗）：build 模式 3 subagent **同時呼叫
  oracleMCP 成功**——推翻「絕對單行」強命題。理論修正為：
  (1) 重載排隊逾時（稽核 SQL 風暴打滿通道 → 並行查詢排隊 >30s →
  觸發自家逾時規則 → BLOCKED）；(2) 待驗的 fratricide 假說
  （connect→查→disconnect 生命週期在共用連線下，一方 disconnect
  拆掉他方）。SOP-12 措辭由「一次一個使用者」放寬為「重載期間
  不並行」。決定性實驗：audit SQL 段並發問答 3 次，看塞車 vs
  連線錯誤。原則重申：**假設要被實驗修正，包括我們自己立的**。

### L16 新增 /ps-correct——資深同事指正業務知識的一鍵入庫（2026-08）
- 動機：最高頻的真實修正場景＝資深同事指正業務邏輯（資料病，非
  行為病）——原路徑（/ps-research 全跑或 SOP-5 人工改檔）太重。
- 設計：/ps-correct <正確知識> → 查重 → 作廢不刪除更新 entity →
  來源標 `human:<日期>`、status verified＋reviewed: true（**本機立即
  生效；人審＝內部 git PR 看 diff**，流程內不設額外蓋章步驟，與
  /ps-lesson 同治理）。
- 配套機制：auditor 新約定——human 型來源＋reviewed: true 免解引用
  （PASS(HUMAN_VERIFIED)）；claim 層不得僅因「查無程式證據」反駁
  human 已驗知識（需明確矛盾證據）。堵住「人教的知識被稽核反覆
  質疑標 stale」的缺口。
- 落點：新 command／auditor 兩處／entity 模板 sources 註記／
  orchestrator 指正協定／AGENTS.md／README／簡報／H3 測試情境
  （總數 38）。
- 套用：本 commit。

### L15 OpenCode 內建 subagent 側門——同名覆寫補鎖（2026-08）
- 症狀：問答（orchestrator）主畫面出現直呼 PeoplecodeMetadata 等
  MCP、以及「EXPLORE TASK」；同題最終回「查不到」。
- 根因：OpenCode（1.17.15 **本就內建**，非升版帶來）有三個內建
  subagent（general／explore／scout）——**內建 agent 不在本專案
  九檔封鎖體系內，MCP 預設全開**（L1 覆寫表教訓的新變種：側門，
  從部署第一天就開著、此次首次被委派漏入）。委派未指名 ps-* 時
  會漏到內建；explore 只探索本機 repo 檔案，查不到 PeopleSoft →
  回報查無被當成最終答案。
- 落點：機械化——(1) .opencode/agent/ 放 general／explore／scout
  **同名覆寫檔**封 4 個 MCP；(2) orchestrator／deep-research 硬規則
  「委派必須指名 ps-*；內建回來的查無無效」；(3) F3 加致命檢查點；
  (4) SOP-8 加「內建 agent 盤點＋同名覆寫」檢查（升版時必查、
  部署時也該查一次）。
- 原則：**平台的預設能力（現在有的＋未來空降的）都在封鎖體系的
  守備範圍**——同名覆寫是唯一可預先部署的鎖。
- 套用：本 commit。

### L14 DISPUTED 抽查歸零——稽核員邊界病＋不可裁決病歷；畢業裁決成立（2026-07-30）
- 抽查結果：DISPUTED 樣本**零筆證實文件為錯**。組成＝(1) 邊界病：
  目標在第 121 行、chunk 只到 120 → 不取下一段就喊矛盾（§5.1
  邊界接續沒綁）；(2) 取證未竟：只取 SavePostChange 就判、SaveEdit
  沒驗——依契約該判 UNVERIFIABLE 卻判 DISPUTED；(3) 病歷不可裁決：
  明細無「claim／取到什麼／矛盾在哪」三要素，人與覆核都無法判。
- 落點：auditor 判 DISPUTED 前置兩前提（取證完整含邊界接續與
  多 event 全取；必附三要素病歷）——缺一改判 UNVERIFIABLE；
  audit-template 明細加三要素要求。
- 畢業裁決：輪次 7 的嚇人數字（FAIL 16／DISPUTED 28）經人工抽驗
  定性為**稽核程序債為主**（查無批＝id 有效、case/行號/數值＝已
  分流雜訊、DISPUTED 樣本零實錘）；文件實際健康。處置＝殘餘實項
  （廣域 lint 縮寫、資料流補證、WRONG_KIND 改引）收一批定向批次，
  其餘行政結案；以修補後稽核員跑**輪次 8 作為基準輪**。
- 套用：本 commit。

### L9 ChunkId 被縮寫成 8 碼 hex——git SHA 習慣汙染 UUID（2026-07-27）
- 症狀：輪次 3 證據層 FAIL 10 的大宗是「非 UUID 格式」——實際是
  文件裡 ChunkId 只剩前 8 碼 hex（縮寫習慣同 git SHA），證據本體
  （filePath／行號／quote）多為真，被機械檢查誤判 FABRICATED。
- 根因：模板僅示意 `<uuid>` 佔位、未示範完整長度；「逐字複製」是
  prose 規則（L0：效力最弱層）；模型以縮寫求可讀性。
- 落點：機械化——(1) 兩模板改用完整 36 字元假 UUID 範例＋禁縮寫
  註記；(2) 硬規則「ChunkId 禁止縮寫」；(3) auditor 區分
  FAIL(TRUNCATED_ID)（8 碼樣式）與 FAIL(FABRICATED)；(4) A 項處理
  加 TRUNCATED_ID 廉價修法（依 filePath＋行號重找補全，不重做
  分析）；(5) lint 對 8 碼樣式給專屬訊息；(6) G2 加檢查點。
- 套用：本 commit。
- 附註：此發現大幅下修真實缺陷率——輪次趨勢（claim 層
  VERIFIED 19→30、DISPUTED 29→13；證據 UNVERIFIABLE 16→9）
  顯示系統在收斂，FAIL 卡 10 主因即縮寫誤判。

### L10 長 run 尾端的自動稽核必塌縮——改為超過門檻就換 session（2026-07-27）
- 症狀：連續處理 13 個 A 項（中途已停機一次要人推）的 run，
  尾端自動稽核產出：無記分卡、僅 13 筆（＝A 項數）、明細只有
  A16~A28——範圍塌縮成「只覆核剛做的事」；「全量重驗」prose 規則
  與 H1 致命檢查點皆未擋住。
- 規律：新 session 的獨立稽核（輪次 3）格式最合規；長 run 尾端
  稽核（首輪、輪次 4）皆塌——**稽核執行品質 ∝ context 新鮮度**。
- 落點：機械化——(1) 收尾稽核加門檻：本 run 打勾 ≤ 5 項才當場
  稽核；> 5 項禁止當場稽核，改提示開新 session 跑 /ps-audit（或
  重跑 /ps-research，全勾態自動接）；(2) lint 全量對帳：每個 NN 檔
  必須出現在 90-audit 內文，缺列＝範圍塌縮警告；(3) 13 筆全過
  亦證明 TRUNCATED_ID 廉價修法有效。
- 套用：本 commit（agent／command／README／lint）。

### L11 輪次 5 全量重驗的三類指紋：紙上修復＋證據類型誤用＋環境噪音（2026-07-27）
- 症狀：FAIL 13／UNVERIFIABLE 8 的原因分布＝「chunk 又是 8 碼截斷」
  （多數）＋「AE SQL 無 SELECT 可重跑」＋「task JSON 失敗／空結果」。
  無「chunk 查無」→ 模型未憑記憶編假 UUID（假說 B 未發生）。
- 根因：(1) 紙上修復——A16~A28 的修復輪發生在 13 項馬拉松 session
  的劣化 context（與稽核塌縮同病灶）；(2) 契約缺口——程式內 SQL
  語句（AE_SQL 等）被標成 `kind: SQL`，稽核員無法重跑非 SELECT；
  (3) 稽核執行期的工具噪音被正確記錄於原因欄（隔離成功）。
- 落點：機械化——(1) 處理端對稱門檻：單次 run 至多處理 6 項，達標
  即停換 session；(2) 契約明文：`SQL` 證據僅限實際執行過的 SELECT，
  程式內 SQL 一律 CHUNK；auditor 新判定 FAIL(WRONG_KIND)（不執行、
  不判 UNVERIFIABLE）；A 項處理加 WRONG_KIND 改引用規則；
  (3) id 補全防造假：必須逐字取自本次 get_chunks_details 回傳，
  禁止憑記憶補尾巴；(4) lint 的 8 碼清單＝截斷修復的確定性工單
  （不依賴稽核計數）。
- 套用：本 commit。
- lint 首跑全量盤點（2026-07-27）：FAIL 24＝縮寫 id ＋**缺章節**
  （行為邏輯／Evidence 附錄——劣化 session 破壞性覆寫的直接證據，
  「整檔覆寫必須保留其他內容」prose 規則被違反）；WARN 109 多為
  wikilink 斷鏈＝歸戶欠課。處置：缺章節優先走**內部 git 考古還原**
  （SOP-4，零重跑、零捏造）；縮寫 id 走 A 項工單；斷鏈另開分批
  補課（一次 10 個、先查重）。

### L25 「追加」在工具層是整檔重寫——append 目標檔是隱形的無界熱檔（2026-08）
- 症狀：輪次 15 稽核在「歸檔＋寫 log」步驟 Preparing write 卡死
  20 分鐘無輸出。回灌 A 項已先落檔（該步驟前完成），損失僅記帳。
- 根因：write 工具只有整檔覆寫——規則寫「append 到
  checklist-archive.md」，執行上是 read 全檔＋重寫全檔；archive
  每輪成長，第 15 輪已超出單次 write 可靠上限（L2 同族），
  且被迫回讀違反「archive 永不回讀」本意。L20 替 checklist 瘦身時，
  肥大被**搬進 archive 而非消滅**——熱檔問題換了地址。
- 落點：機械化——歸檔改**每輪寫新檔** `checklist-archive-r<N>.md`
  （單次小 write；禁止 read／改寫既有 archive 檔）；lint 對帳改
  合併 `checklist-archive*.md` 全部分片。原則：**真 append＝開新檔**；
  任何「只追加」規則都必須附分片條件，否則就是下一個卡死點。
- 套用：本 commit（agent／command／lint／checklist-template）。
