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
