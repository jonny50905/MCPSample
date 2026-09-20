---
description: Spec 外環專用單段工單：$ARGUMENTS 是 clone jobId/attemptId，不接受自由業務問題
agent: ps-clone-worker
---

工單：`$ARGUMENTS`。只接受 `clone-` 加 16 碼小寫 hex、斜線、`a` 加數字的形狀；其他輸入回報無有效工單，不猜檔名。
把斜線前段當 jobId、後段當 attemptId；第一個動作 read：
`.ps-runtime/clone-spec/<jobId>/attempts/<attemptId>/manifest.md`。

讀工單、同目錄 input.json 與 clone-contract.md，依 kind 只做研究或獨立覆核。只寫本 attempt 指定的 packet.json／review.json。
不存在就結束，不能掃描別的工作取代。不要啟動整個領域研究，也不要呼叫其他 headless loop。
