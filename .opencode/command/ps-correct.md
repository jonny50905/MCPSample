---
description: 登錄人工指正的業務知識並本機立即生效——查重後更新 wiki entity（作廢不刪除、來源標 human、verified）；團隊生效走內部 git PR 審核
agent: ps-deep-research
---
把以下人工指正的業務知識更新進知識庫：

$ARGUMENTS

**禁止複述計畫——第一個回應必須是工具呼叫：先 grep
`docs/ps-research/wiki/` 以物件名與 aliases 查重，然後立刻更新。**

步驟：
1. 查重：已有 entity 檔 → 就地更新；沒有 → 依 entity 模板建檔
   （檔名＝物件名）並更新 wiki/index.md。
2. 更新（作廢不刪除）：與指正矛盾的舊 Observations 移入「Invalidated」
   節（附日期與一句原因）；新增正確敘述，來源標 `human:<今日日期>`
   （指正中有佐證 chunk／SQL 就一併附上）。
3. frontmatter：`status: verified`、`reviewed: true`、更新
   `last_verified`；aliases 補上指正中出現的稱呼。
4. 相關 NN 檔含舊敘述者同步修正（僅該敘述，其他一字不動）。
5. 回覆兩點提醒：(a) 重啟後問答立即引用此條目；(b) 團隊生效需
   commit 走**內部 git PR 審核**（審核者看 diff 裁決——與 /ps-lesson
   同一套治理，本流程內不設額外人工蓋章步驟）。

唯一例外：指正與現有 `verified` 條目衝突且無法並存 → 兩案並陳寫入
該檔、回覆請管理者裁決，不逕自覆蓋。
