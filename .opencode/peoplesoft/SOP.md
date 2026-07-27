# 管理者 SOP（人工作業標準程序）

適用對象：系統管理者（維護規則檔、把關教訓、管理內部 git 的人）。
一般使用者只需要 OpenCode 對話（問答、`/ps-research`、`/ps-audit`、`/ps-lesson`），
不需要本文件。

---

## SOP-1 教訓 PR 審查——最重要的一份

**流程**：同事 `/ps-lesson` → **該機立即生效**（agent 直接修落點檔＋記錄
applied.md）→ 同事 commit ＋ push → 內部 git 開 **PR** → 你審 diff →
merge（全隊採納）或退回。把關點在合併，不在事前。

```text
【審 PR 時看五件事（看 diff 即可，單筆 2~5 分鐘）】
□ 1. 落點優先序對嗎？機械化檢查 > 資料修正 > 窄規則 > AGENTS.md
     （能用 lint / 格式判定 / tools deny 解決的，不該寫成 prose 規則）
□ 2. 是「最小新增」嗎？——只加不刪；有任何既有規則被改寫/移除 → 退回
□ 3. 措辭會不會太寬、誤傷正常行為？
□ 4. 測試檢查點有跟著加進 test-scenarios.md 嗎？
□ 5. 沒把握 → 把 diff 遮敏後貼給較強模型審（物件名可代稱；機密不出機器）

【merge 後】
□ 通知全員 pull ＋ 重啟 OpenCode（教訓才會到每台機器）

【退回時】
□ PR reject ＋ 註明理由
□ 通知該同事在本機 revert 該 commit（他的機器退回原狀）
□ 若教訓本身有價值只是落點/措辭不對 → 修改後重新提交
```

**節奏**：教訓 PR 隨到隨審或每日批次；會導致嚴重錯誤決策的緊急教訓即時處理。
**例外案件**：`pending.md` 裡狀態 PENDING 的（agent 沒把握自動套用的）——
人工判斷落點後自行修改、記錄 applied.md、照常走 PR。

---

## SOP-2 Lint 執行

**時機**：每個領域 `/ps-research` 跑完後；`/ps-audit` 前；懷疑格式壞掉時。

```text
□ 1. 終端機執行：.\scripts\ps-doc-lint.ps1 -Domain <領域>
□ 2. 綠色 PASS → 結束
□ 3. 紅色 FAIL → 逐項處理：
     - 「checklist 已打勾但檔案不存在」「檔案未列於清單」
       → 對話叫 deep-research 修（或人工補 checklist 行）
     - 「ChunkId 非 UUID / 自編 id」→ 證據捏造，跑 /ps-audit 該領域
     - 「缺章節 / 無 confidence 標註」→ 對話叫 deep-research 重寫該檔該節
     - wiki 類警告（斷鏈 / 孤兒 / 過期 / frontmatter 缺欄）
       → 斷鏈孤兒叫 deep-research 修；stale 排入下次 /ps-research
□ 4. 修完重跑 lint 確認
```

---

## SOP-3 內部 Git

**原則**：產出（docs/ps-research/）與框架（.opencode/）都 commit 到**內部** git；
**嚴禁推到任何外部 remote**。

```text
□ 何時 commit：
  - 一個領域研究完成或告一段落後
  - /ps-audit 跑完後（含 90-audit.md 與回灌）
  - 教訓套用後（SOP-1 第 9 步）
  - 人工修正文件後
□ Commit message 前綴（讓 git log 可過濾）：
  - kb(research): <領域> 新增/更新研究
  - kb(audit):    <領域> 稽核與回灌
  - kb(fix):      人工修正 <檔案>（含 reviewed 標記）
  - kb(rule):     教訓套用 <L編號>
□ 推送前檢查：git remote -v 確認只有內部 remote
□ 回答「這條事實哪次加的」：git log --follow / git blame <entity檔>
```

---

## SOP-4 回滾（文件被 agent 弄壞時）

```text
□ 1. 先確認災情範圍：git status / git diff（未 commit 的變更）
□ 2. 未 commit 的壞變更 → git checkout -- docs/ps-research/<壞掉的路徑>
□ 3. 已 commit 的壞變更 → git log 找壞 commit → git revert <sha>
     （用 revert 不用 reset——保留歷史）
□ 4. 回滾後把肇因登錄教訓：/ps-lesson <一句話描述 agent 做了什麼壞事>
```

---

## SOP-5 人工修正文件與 reviewed 標記

**時機**：你（或領域專家）確認某份文件 / entity 檔內容有誤，要人工修正。

```text
□ 1. 修正內容時遵守「作廢不刪除」：
     - entity 檔：舊事實移到「## Invalidated」節標日期原因，新事實寫回 Observations
     - 領域文件：錯誤敘述改正，必要時在該段留一行「（更正：原載…，經確認為…）」
□ 2. 該檔 frontmatter 改 reviewed: true
     → 從此 agent 不得覆寫此檔既有內容（只能追加），重生成也會跳過
□ 3. 若這個錯反映系統性問題 → 順手 /ps-lesson 登錄
□ 4. git commit（前綴 kb(fix):）
```

---

## SOP-6 Checklist 人工加項

盤點漏了功能時，兩種方式擇一：

```text
方式 A（推薦）：對話裡講——「把 TW_XXX 加進 <領域> 的調查清單」
方式 B（手改）：編輯 00-overview.md 的「調查進度」，照格式加一行：
              - [ ] NN <功能名> `<物件名>` → NN-<物件名>.md
之後跑 /ps-research <領域> 就會查它。
```

---

## SOP-7 Obsidian（選配的人類閱讀介面）

不裝完全不影響任何功能。要裝：

```text
□ 1. Obsidian → Open folder as vault → 選 docs/ps-research/
□ 2. 立刻把 .obsidian/ 加進內部 git 的 .gitignore
     （至少 ignore .obsidian/workspace.json——它每次開檔都變）
□ 3. 注意：不要用 Obsidian 的 Properties 圖形介面改 frontmatter
     ——它會重排/改寫 YAML 格式，跟 agent 寫入互相打架產生幻影 diff。
     要改 frontmatter 用純文字模式或編輯器改。
□ 4. 好處：wikilink 點擊跳轉、backlink 面板、graph view、
     全域搜尋 `- [ ]` 看所有未完成調查
```

---

## SOP-8 環境異動時的對齊檢查

```text
□ 新增 MCP server 註冊 → 先在**全部 9 個 agent 檔**的 tools 加
  "<註冊名>_*": false（tools map 是覆寫表：沒列＝預設全開，主 agent 會
  直接呼叫繞過 subagent 架構；其回傳也塞不進證據契約，誘發捏造）。
  之後要用再走正式整合：選定歸屬 subagent → 該檔改 allow ＋補工具
  對照表＋定義證據格式，其餘 agent 檔維持 deny
□ MCP server 註冊名變了 → 改 agent 檔 tools 的 "<註冊名>_*" 前綴
  （含 deny 項），前綴大小寫須完全一致
□ 換模型 → 重跑 Smoke Set（test-scenarios.md §5，9 題）確認規則遵循沒退化
□ OpenCode 升版 → 確認 agent（Tab 清單）、command（/ 清單）、
  skill 都有載入；異常先看 frontmatter 格式
□ PeopleTools 升版 → cookbook 的表名/欄位抽 2~3 條樣板實跑驗證
```
