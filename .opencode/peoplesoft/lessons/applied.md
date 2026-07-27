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
