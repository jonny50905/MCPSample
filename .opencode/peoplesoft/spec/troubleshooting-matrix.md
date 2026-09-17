# Spec 引擎疑難排解矩陣（stage → 責任方 → 第一步）

結論碼 `SPEC1-<stage>-<code>` 的 stage 決定誰處理；回報時只給結論碼與 drill tuple（`ps-spec -Doctor -JobId <jobId> -Drill <stage>-<code>`）。

| stage | 名稱 | 責任方 | 什麼壞了 | 第一步 |
|---|---|---|---|---|
| 0 | integrity | 搬運／維護端（generic 檔完整性） | generic 集合與 generic.manifest.json 不符：搬運不完整、公司機誤改 generic 檔 | 公司機不得改 `scripts/**`、`.opencode/peoplesoft/spec/**`、worker agent／command；重新搬運；維護端改 generic 檔後 `-Doctor -WriteGenericManifest` 重生 |
| 1 | pack | 私有映射（公司機內部人員） | pack.json 結構：未知欄位、ID 重複、checklist 未引用、slot 與模板標記不對應、factKind／property／context 不在目錄、依賴成環 | 看 `-ValidatePack` 印出的 PACK 行（本機看）；對照 pack.schema.json 與 capabilities.json 修 pack；目錄挑不到的填 UNSUPPORTED 並提 CAP-REQ |
| 2 | plan | 引擎（generic） | 身分：Component 無 NN、多領域平手、DomainHint 打不中；pack 內容已變 | 2-03 給 `-DomainHint` 讓引擎提交 KnowledgeNeed（Research 相位建檔）；2-04 給 `-DomainHint`；2-08 重跑 `-Plan` |
| 3 | dispatch | 引擎／環境 | session 未健康結束、slot 被占、找不到 opencode | 3-03 錯開兩個外環；3-04 看 auto-loop-logs/spec/<jobId>/ 的 out／err；3-05 修 PATH |
| 4 | accept | 引擎（worker 產出品質） | 片段不合格（4-02 原因碼）、attempts≥2 → BLOCKED、來源在 session 期間改動 | `-Drill 4-02` 看原因碼：ITEM_UNKNOWN／EVIDENCE_UNKNOWN／HEADER_MISMATCH 多屬模型未照工單；4-04 重跑 `-Plan`；4-03 拆 NN 續篇縮小單位或修 NN 後重規劃 |
| 5 | knowledge | Research（補研究協定） | 等待 result／等待稽核／result 無法解決 | 5-01 跑 `ps-auto-loop -Domain <D> -SupplementalOnly`；5-04 跑下一輪稽核（`/ps-audit`）；5-05 看 `ps-supplemental -Status`，必要時人工補研究後 `-Plan` |
| 6 | render | 引擎 | render 前重驗：sourceRef／收據指紋與現況不符 | 來源 NN 改過＝正常訊號：重跑 `-Plan` → `-Run` → `-Render` |
| 7 | gate | 引擎（判定）＋私有映射（覆蓋） | SPEC_PARTIAL／BLOCKED 的 finding：缺 fact、cardinality、等級不足、UNKNOWN debt、checklist 未覆蓋 | `-Drill 7-1x／7-21` 看哪個 Rnn；7-13 提高來源等級（稽核）；7-15 給條件所需事實的 requirement；7-16 讓每個 Cnn 至少有一個可滿足的 requirement |
| 8 | mapping | 私有映射（內部覆核） | reviewedVersion≠packVersion | 內部覆核 pack 後填 reviewedVersion |
| 9 | usage | 使用者／環境 | 參數、jobId 文法、job 不存在、互斥鎖被占 | 9-04 等另一個 ps-spec 結束；9-05 jobId 只能小寫英數與連字號 |

## 固定流程（每個 job）

`-ValidatePack` → `-Plan` → `-Run`（重複直到 3-01；5-0x 時去補研究／稽核再回來）→ `-Render` → `-Gate`。
任何時候 `-Doctor -JobId <jobId>` 看 phase／單位計數；`-Drill` 拿 tuple。

## 不變量（機械驗）

- 引擎永不寫 NN／wiki／checklist；worker 只寫 `attempts/<attemptId>/fragment.md`。
- 待派單位＝plan 單位＋splits −（指紋相符的收據）；job.json 的狀態只供顯示。
- 收據以 `<unitKey>[~part].<inputFingerprint16>.json` 為鍵、不可覆寫；來源改動＝指紋變＝收據自然失效。
- `-Render` 重跑 byte 相同；來源變動時 current.json 不換。
