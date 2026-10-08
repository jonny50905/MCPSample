# -*- coding: utf-8 -*-
"""貫穿範例的合成輸入：STATUS 文件（兩張 Mermaid 圖）、專案輸入檔、人工裁決檔。"""

STATUS_DOC = '''# 申請單狀態流程（合成範例）

本檔是 STATUS 權威文件的合成範例：一個狀態實體（申請單的 REQ_STATUS），同時提供 flowchart 與 stateDiagram-v2。

## 情境流程

```mermaid
flowchart TD
    START((開始)) -->|主流程| N010["010 草稿"]
    N010 -->|主流程| N020["020 待主管審核"]
    N020 -->|主流程| D1{金額判斷}
    D1 -->|主流程| N030["030 核准"]
    D1 -->|高額審核| N025["025 待部門主管審核"]
    N025 -->|高額審核| N030
    N020 -->|退回補件| N015["015 退回補件"]
    N025 -->|退回補件| N015
    N015 -->|退回補件| N020
    N010 -->|撤回作廢| N090["090 作廢"]
    N015 -->|撤回作廢| N090
```

## 狀態圖

```mermaid
stateDiagram-v2
    state "010 草稿" as S010
    state "015 退回補件" as S015
    state "020 待主管審核" as S020
    state "025 待部門主管審核" as S025
    state "030 核准" as S030
    state "090 作廢" as S090
    state amount_check <<choice>>
    [*] --> S010
    S010 --> S020
    S015 --> S020
    S020 --> amount_check
    amount_check --> S030
    amount_check --> S025
    S025 --> S030
    S020 --> S015
    S025 --> S015
    S010 --> S090
    S015 --> S090
    S030 --> [*]
    S090 --> [*]
    note right of S025 : 部門主管審核
```
'''

PROJECT_INPUT = '''# 專案輸入（合成範例）

## 目標

| 目標 | 成功標準 |
|---|---|
| 以新系統取代舊的申請審核功能，狀態流程與審核規則維持不變 | 狀態圖上每條轉移在新系統都可操作，結果與 04／09 的規格一致；14 的測試案例全數通過 |

## 決策責任

| 範圍 | 職稱或單位類別 |
|---|---|
| SPEC_APPROVAL | 業務單位主管 |
| QUESTION_RESOLUTION | 業務承辦窗口 |

## 狀態圖

| 狀態實體 | 檔案 | 狀態欄位（選填） |
|---|---|---|
| REQ_STATUS | status-REQ_STATUS.md | TW_DEMO_REQHDR.REQ_STATUS |
'''

def decisions_md(qid_offdiag_trn):
    return f'''# 人工裁決（合成範例）

| 問題 ID | 決定 | 理由 | 效果 | 決定者類別 | 日期 |
|---|---|---|---|---|---|
| {qid_offdiag_trn} | 不重建「核准後重開為草稿」 | 這是管理者以特殊參數做的資料維護，不是業務流程；STATUS 文件不納入 | DROP | 業務單位主管 | 2026-10-08 |
'''

def line_of(text, needle, start=0):
    """1-based line number of the first line containing needle (after line index start)."""
    for i, line in enumerate(text.split('\n')):
        if i >= start and needle in line:
            return i + 1
    raise KeyError(needle)
