# -*- coding: utf-8 -*-
"""依序重建並驗證設計提案的機器可讀部分：
schemas → 參照方向與文件層級無循環 → 貫穿範例組裝與 L1～L3 檢核 → 壞範例必須全部被擋 → 渲染樣張 → 文件 GEN 區塊。

範例刻意留下兩條測試缺口（見 walkthrough.md）；檢核結果必須恰好是這兩條，否則失敗。
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
STEPS = ['schema_gen.py', 'check_rank.py', 'assemble_check.py', 'negative_check.py', 'render.py', 'sync_docs.py']
EXPECTED = {'14-testing/L3': ['C07 TRN-005（015>090）沒有測試案例', 'C07 TRN-009（025>015）沒有測試案例']}

ENV = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
for step in STEPS:
    r = subprocess.run([sys.executable, os.path.join(HERE, step)], cwd=HERE, capture_output=True, text=True, env=ENV)
    if r.returncode:
        print(r.stdout + r.stderr)
        sys.exit(f'{step} 失敗')
rep = json.load(open(os.path.join(BASE, 'examples', 'walkthrough', 'gate-report.json'), encoding='utf-8'))
problems = []
if rep['violations'] != EXPECTED:
    problems.append('檢核結果與預期不同：' + json.dumps(rep['violations'], ensure_ascii=False))
for k in ('evidenceErrors', 'evidenceUnused', 'evidenceMissing'):
    if rep[k]:
        problems.append(f'{k}: {rep[k]}')
if not (rep['parse']['codesEqual'] and rep['parse']['transitionsEqual']):
    problems.append('兩張狀態圖不一致')
if problems:
    sys.exit('\n'.join(problems))
print('OK：schemas、範例、檢核、渲染、文件 GEN 區塊都已更新且符合預期')
