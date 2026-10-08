# 19 決策紀錄

> `clone-0123456789abcdef/19`｜版本 r0001｜狀態 **in_review**｜L1 PASS · L2 PASS · L3 NOT_APPLICABLE · L4 NOT_APPLICABLE · L5 NOT_APPLICABLE
> 依賴文件：01、90｜未解問題：無
> 決策 1
> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。

## 決策（DEC）

### DEC-001　不重建「核准後重開為草稿」

- 自然鍵：`DEC:0001`
- 決策標題：不重建「核准後重開為草稿」
- 背景：Q-002：TW_DEMO_APV.PostBuild 有一段狀態圖外的 030→010 邏輯。
- 考慮過的選項：
  - 選項：不重建；結果：新系統沒有重開功能；需要時以資料維護處理。
  - 選項：補進 STATUS 文件並重建；結果：狀態圖新增 030→010，04、02、08、14 要補對應項目。
- 決定：不重建。
- 理由：這是管理者以特殊參數做的資料維護，不是業務流程；STATUS 文件不納入。
- 決策者：業務單位主管
- 決策日期：2026-10-08
- 決策狀態：ACCEPTED
- 回答的問題：Q-002（OFF_DIAGRAM_TRANSITION:REQ_STATUS:030>010）
- 影響的規格項目：OBJ-007（TW_DEMO_APV.PostBuild）
- 對規格的效果：DROP
- 來源：人工決策；證據 EV-0064
