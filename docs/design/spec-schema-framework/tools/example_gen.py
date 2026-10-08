# -*- coding: utf-8 -*-
"""貫穿範例的全部項目：先以自然鍵寫參照，最後依自然鍵的字元碼順序派 ID 並解開參照。"""
import json, os, re, hashlib, uuid, copy
import schema_gen as g
import example_inputs as X

JOB = 'clone-0123456789abcdef'
REV = 'r0001'
STATUS_FILE = 'status-REQ_STATUS.md'

def sha(s):
    return hashlib.sha256(s.encode('utf-8')).hexdigest()

# ---------------- symbolic refs ----------------
def r(prefix, key):
    return f'@@{prefix}|{key}@@'

ITEMS = {}  # prefix -> list of item dicts (with 'key')

def add(prefix, key, **fields):
    it = {'key': key, 'lifecycle': 'ACTIVE'}
    it.update(fields)
    it.setdefault('certainty', 'CONFIRMED')
    it.setdefault('evidence', [])
    ITEMS.setdefault(prefix, []).append(it)
    return it

# ---------------- evidence ----------------
EVIDENCE = []

def ev(kind, locator, excerpt):
    eid = f'EV-{len(EVIDENCE) + 1:04d}'
    EVIDENCE.append({'id': eid, 'kind': kind, 'locator': locator, 'excerpt': excerpt})
    return eid

def chunk(seed, excerpt):
    u = uuid.UUID(hashlib.md5(('synthetic-chunk:' + seed).encode()).hexdigest())
    return ev('CHUNK', str(u), excerpt)

def sdl(needle, start_after=None):
    start = 0
    if start_after:
        start = X.line_of(X.STATUS_DOC, start_after)
    n = X.line_of(X.STATUS_DOC, needle, start)
    line = X.STATUS_DOC.split('\n')[n - 1].strip()
    return ev('STATUS_DOC', f'{STATUS_FILE}#L{n}', line)

FC = 'flowchart TD'
SD = 'stateDiagram-v2'

# ---------------- common pieces ----------------
REQ, APV = 'TW_DEMO_REQ', 'TW_DEMO_APV'
HDR, WRK, EMP, DEPT = 'TW_DEMO_REQHDR', 'TW_DEMO_REQWRK', 'TW_DEMO_EMP', 'TW_DEMO_DEPT'
def F_(rec, fld):
    return r('FLD', f'{rec}.{fld}')
def fld(rec, f):
    return {'fld': F_(rec, f)}
def const(v, t='CHAR'):
    return {'const': v, 'type': t}
def ctx(c):
    return {'ctx': c}
def st(code):
    return {'state': r('STATE', f'REQ_STATUS:{code}')}
def P(left, op, right=None):
    p = {'left': left, 'op': op}
    if right is not None:
        p['right'] = right
    return p
def ALL(*c):
    return {'all': list(c)}
def ANY(*c):
    return {'any': list(c)}
ME = ctx('CURRENT_USER_EMPLID')
SUPERVISOR = {'drv': r('DRV', 'REQUESTER_SUPERVISOR')}
DEPT_MGR = {'drv': r('DRV', 'REQUESTER_DEPT_MANAGER')}
HAS_APPROVER = P(ctx('CURRENT_USER_OPRID'), 'HAS_ROLE', {'role': r('ROLE', 'ROLE:TW_DEMO_APPROVER')})
HAS_REQUESTER = P(ctx('CURRENT_USER_OPRID'), 'HAS_ROLE', {'role': r('ROLE', 'ROLE:TW_DEMO_REQUESTER')})
IS_REQUESTER = P(fld(HDR, 'REQUESTER_EMPLID'), 'EQ', ME)
def status_in(*codes):
    return P(fld(HDR, 'REQ_STATUS'), 'IN', [st(c) for c in codes])
def status_is(code):
    return P(fld(HDR, 'REQ_STATUS'), 'EQ', st(code))
def set_status(code):
    return {'field': F_(HDR, 'REQ_STATUS'), 'value': const(code)}
def obj(t, name):
    return r('OBJ', f'{t}:{name}')
def pc(name):
    return obj('PEOPLECODE', name)

# ---------------- evidence pool ----------------
EV_PROJECT_GOAL = ev('PROJECT_INPUT', 'project.md#L7', X.PROJECT_INPUT.split('\n')[6])
EV_PROJECT_RESP1 = ev('PROJECT_INPUT', 'project.md#L13', X.PROJECT_INPUT.split('\n')[12])
EV_PROJECT_RESP2 = ev('PROJECT_INPUT', 'project.md#L14', X.PROJECT_INPUT.split('\n')[13])
EV_META_REQ = ev('METADATA_RECEIPT', 'inventory/component-TW_DEMO_REQ.json#pages',
                 'TW_DEMO_REQ: TW_DEMO_REQPG (MAIN), TW_DEMO_REQSEC (SECONDARY)\nrecords: TW_DEMO_REQHDR, TW_DEMO_REQWRK')
EV_META_APV = ev('METADATA_RECEIPT', 'inventory/component-TW_DEMO_APV.json#pages',
                 'TW_DEMO_APV: TW_DEMO_APVPG (MAIN)\nrecords: TW_DEMO_REQHDR, TW_DEMO_REQWRK')
EV_META_PC = ev('METADATA_RECEIPT', 'inventory/peoplecode.json#core',
                '9 programs on core objects (component / record field events)')
EV_META_REC = ev('METADATA_RECEIPT', 'inventory/records.json#fields',
                 'TW_DEMO_REQHDR 11 fields; TW_DEMO_EMP 5 used; TW_DEMO_DEPT 4 used')
EV_META_ROLE = ev('METADATA_RECEIPT', 'inventory/security.json#components',
                  'TW_DEMO_REQ: TW_DEMO_REQUESTER\nTW_DEMO_APV: TW_DEMO_APPROVER')
EV_META_MSG = ev('METADATA_RECEIPT', 'inventory/messages.json#27000', '27000,1..4 (ERROR)')
EV_REQSEC = ev('METADATA_RECEIPT', 'inventory/component-TW_DEMO_REQ.json#transfers',
               'no push button / link / Transfer() opens TW_DEMO_REQSEC')
EV_SQL_STATUS = ev('SQL', "SELECT REQ_STATUS, COUNT(*) FROM PS_TW_DEMO_REQHDR GROUP BY REQ_STATUS",
                   "010|120  015|8  020|31  025|4\n030|980  090|57  099|12")
EV_SQL_XF_DATA = ev('SQL', "SELECT SUM(CASE WHEN OLD_REF_NO <> ' ' THEN 1 ELSE 0 END), SUM(CASE WHEN PRIORITY_CD <> ' ' THEN 1 ELSE 0 END), COUNT(*) FROM PS_TW_DEMO_REQHDR",
                    '0|0|1212')
EV_SQL_XF_XREF = ev('SQL', "SELECT OBJECTVALUE1, OBJECTVALUE2, OBJECTVALUE3 FROM PSPCMNAME WHERE RECNAME = 'TW_DEMO_REQHDR' AND REFNAME IN ('OLD_REF_NO','PRIORITY_CD')",
                    '(0 rows)')
EV_SQL_EMP_PROFILE = ev('SQL', "SELECT COUNT(*), SUM(CASE WHEN SUPERVISOR_ID <> ' ' THEN 1 ELSE 0 END) FROM PS_TW_DEMO_EMP",
                        '5210|5198')
EV_SQL_DEPT_PROFILE = ev('SQL', "SELECT COUNT(*), SUM(CASE WHEN MANAGER_ID <> ' ' THEN 1 ELSE 0 END) FROM PS_TW_DEMO_DEPT",
                         '87|85')

EV_PC_SUBMIT = chunk('submit', '&sup = TW_DEMO_GETSUPERVISOR(TW_DEMO_REQHDR.REQUESTER_EMPLID);\nIf None(&sup) Then Error MsgGet(27000, 3, "找不到直屬主管，無法送出。"); End-If;\nTW_DEMO_REQHDR.REQ_STATUS.Value = "020";\nTW_DEMO_REQHDR.SUBMIT_DT.Value = %Date;')
EV_PC_WITHDRAW = chunk('withdraw', 'TW_DEMO_REQHDR.REQ_STATUS.Value = "090";')
EV_PC_APPROVE = chunk('approve', 'If TW_DEMO_REQHDR.REQ_STATUS = "020" And TW_DEMO_REQHDR.AMOUNT > 50000 Then\n   TW_DEMO_REQHDR.REQ_STATUS.Value = "025";\nElse\n   TW_DEMO_REQHDR.REQ_STATUS.Value = "030"; TW_DEMO_REQHDR.APPROVER_EMPLID.Value = %EmployeeId; TW_DEMO_REQHDR.APPROVE_DT.Value = %Date;\nEnd-If;')
EV_PC_APPROVE_ACTOR = chunk('approve-actor', 'If TW_DEMO_REQHDR.REQ_STATUS = "020" And &sup <> %EmployeeId Then Error ...;\nIf TW_DEMO_REQHDR.REQ_STATUS = "025" And &mgr <> %EmployeeId Then Error ...;')
EV_PC_RETURN = chunk('return', 'If None(TW_DEMO_REQHDR.COMMENTS) Then Error MsgGet(27000, 2, "退回時必須填寫審核意見。"); End-If;\nTW_DEMO_REQHDR.REQ_STATUS.Value = "015";')
EV_PC_AMOUNT = chunk('amount', 'If TW_DEMO_REQHDR.AMOUNT <= 0 Then\n   Error MsgGet(27000, 1, "金額必須大於 0。");\nEnd-If;')
EV_PC_DEFAULT = chunk('default', 'If None(TW_DEMO_REQHDR.REQUESTER_EMPLID) Then TW_DEMO_REQHDR.REQUESTER_EMPLID = %EmployeeId; End-If;')
EV_PC_PRECHANGE = chunk('prechange', 'If TW_DEMO_REQHDR.REQ_ID = "NEW" Then\n   TW_DEMO_REQHDR.REQ_ID = TW_DEMO_NEXTREQID();\nEnd-If;')
EV_PC_POSTCHANGE = chunk('postchange', 'If TW_DEMO_REQHDR.REQ_STATUS = "020" Then\n   TW_DEMO_SCHEDNOTIFY(TW_DEMO_REQHDR.REQ_ID);\nEnd-If;')
EV_PC_POSTBUILD = chunk('postbuild', 'If %Request.GetParameter("REOPEN") = "Y" And TW_DEMO_REQHDR.REQ_STATUS = "030" Then\n   TW_DEMO_REQHDR.REQ_STATUS.Value = "010";\nEnd-If;')
EV_PC_SUPERVISOR = chunk('get-supervisor', 'SQLExec("SELECT SUPERVISOR_ID FROM PS_TW_DEMO_EMP E WHERE EMPLID = :1 AND EFF_STATUS = \'A\' AND EFFDT = (SELECT MAX(EFFDT) FROM PS_TW_DEMO_EMP WHERE EMPLID = E.EMPLID AND EFFDT <= %CurrentDateIn)", &emplid, &sup);')
EV_PC_DEPTMGR = chunk('get-deptmgr', 'SQLExec("SELECT D.MANAGER_ID FROM PS_TW_DEMO_EMP E, PS_TW_DEMO_DEPT D WHERE ... current EFFDT rows ... AND D.DEPTID = E.DEPTID", &emplid, &mgr);')
EV_PC_CONCURRENCY = chunk('concurrency', 'If TW_DEMO_REQHDR.LASTUPDDTTM <> &loadedDttm Then Error MsgGet(27000, 4, "此申請單已被其他使用者更新，請重新查詢。"); End-If;')
EV_AE_NTFY = chunk('ae-notify', 'SELECT REQ_ID, REQUESTER_EMPLID, AMOUNT FROM PS_TW_DEMO_REQHDR WHERE REQ_ID = %Bind(REQ_ID)\n-- send mail to supervisor; on failure write process log only')
EV_PAGE_HIDE_REQ = chunk('hide-req', 'If TW_DEMO_REQHDR.REQ_STATUS = "010" Or TW_DEMO_REQHDR.REQ_STATUS = "015" Then\n   TW_DEMO_REQWRK.SUBMIT_PB.Visible = True; TW_DEMO_REQWRK.WITHDRAW_PB.Visible = True;\nElse ... Visible = False; TW_DEMO_REQHDR.AMOUNT.DisplayOnly = True; End-If;')
EV_PAGE_HIDE_APV = chunk('hide-apv', 'If TW_DEMO_REQHDR.REQ_STATUS = "020" Or TW_DEMO_REQHDR.REQ_STATUS = "025" Then\n   TW_DEMO_REQWRK.APPROVE_PB.Visible = True; TW_DEMO_REQWRK.RETURN_PB.Visible = True;\nElse ... Visible = False; End-If;')
EV_ROWSEC = chunk('rowsec', 'search record TW_DEMO_APVSRCH: REQ_STATUS IN (\'020\',\'025\') AND (supervisor = %EmployeeId OR dept manager = %EmployeeId)')
EV_ROWSEC_REQ = chunk('rowsec-req', 'search record TW_DEMO_REQSRCH: REQUESTER_EMPLID = %EmployeeId')

# ---------------- 01 overview ----------------
add('GOAL', 'GOAL:01', basis='PROJECT_INPUT', evidence=[EV_PROJECT_GOAL],
    name='取代舊的申請審核功能',
    statement='以新系統取代舊的申請審核功能，狀態流程與審核規則維持不變。',
    successCriteria=['狀態圖上每條轉移在新系統都可操作，結果與 04、09 的規格一致。', '14 的測試案例全數通過。'])
add('RESP', 'RESP:SPEC_APPROVAL', basis='PROJECT_INPUT', evidence=[EV_PROJECT_RESP1],
    area='SPEC_APPROVAL', holder='業務單位主管')
add('RESP', 'RESP:QUESTION_RESOLUTION', basis='PROJECT_INPUT', evidence=[EV_PROJECT_RESP2],
    area='QUESTION_RESOLUTION', holder='業務承辦窗口')

def O(otype, name, inclusion, usedBy, reason, condition=None, parent=None, usedByRefs=None, evidence=None,
      fieldUsage=None, pcEvent=None, component=None):
    it = add('OBJ', f'{otype}:{name}', basis='METADATA', evidence=evidence or [],
             objectType=otype, objectName=name, inclusion=inclusion, usedBy=usedBy,
             condition=condition if condition is not None else {'na': '入口物件，進入即使用'}, reason=reason)
    if parent:
        it['parent'] = parent
    if usedByRefs:
        it['usedByRefs'] = usedByRefs
    if fieldUsage:
        it['fieldUsage'] = fieldUsage
    if pcEvent:
        it['pcEvent'] = pcEvent
    if component:
        it['component'] = component
    return it

O('COMPONENT', REQ, 'CORE', '使用者指定的根', '使用者指定的核心 Component（申請）', evidence=[EV_META_REQ], component=REQ)
O('COMPONENT', APV, 'CORE', '使用者指定的根', '使用者指定的核心 Component（主管審核）', evidence=[EV_META_APV], component=APV)
O('PAGE', 'TW_DEMO_REQPG', 'CORE', 'TW_DEMO_REQ 的主頁', '申請畫面', parent=obj('COMPONENT', REQ),
  usedByRefs=[obj('COMPONENT', REQ)], evidence=[EV_META_REQ], component=REQ)
O('PAGE', 'TW_DEMO_APVPG', 'CORE', 'TW_DEMO_APV 的主頁', '審核畫面', parent=obj('COMPONENT', APV),
  usedByRefs=[obj('COMPONENT', APV)], evidence=[EV_META_APV], component=APV)
O('SECONDARY_PAGE', 'TW_DEMO_REQSEC', 'EXCLUDED', 'TW_DEMO_REQ 內有定義，但頁面上沒有按鈕、連結或程式會開啟它',
  '元件內存在、核心路徑沒有入口', condition={'na': '核心路徑不會進入'}, parent=obj('COMPONENT', REQ),
  evidence=[EV_REQSEC], component=REQ)
O('RECORD', HDR, 'CORE', '兩個主頁的主要 Record', '申請單主檔', condition={'na': '兩頁一律讀寫'},
  usedByRefs=[obj('PAGE', 'TW_DEMO_REQPG'), obj('PAGE', 'TW_DEMO_APVPG')], evidence=[EV_META_REC],
  fieldUsage={'excluded': {'count': 2}})
O('RECORD', WRK, 'CORE', '按鈕所在的工作記錄', '承載送出、撤回、核准、退回四個按鈕事件', condition={'na': '頁面載入即存在'},
  usedByRefs=[obj('PAGE', 'TW_DEMO_REQPG'), obj('PAGE', 'TW_DEMO_APVPG')], evidence=[EV_META_REC],
  fieldUsage={'undetermined': {'code': 'NO_TABLE', 'note': '工作記錄沒有實體表，欄位都是按鈕'}})
O('RECORD', EMP, 'DEPENDENCY', '送出、核准、退回時查申請人的直屬主管與部門；審核清單的資料範圍',
  '只提供直屬主管與部門的最小介面', condition='送出、審核清單查詢、核准、退回時',
  usedByRefs=[pc('TW_DEMO_REQWRK.SUBMIT_PB.FieldChange'), pc('TW_DEMO_REQWRK.APPROVE_PB.FieldChange')],
  evidence=[EV_PC_SUPERVISOR, EV_SQL_EMP_PROFILE], fieldUsage={'noneExcludable': {'checkedOn': '2026-10-01'}})
O('RECORD', DEPT, 'DEPENDENCY', '高額案件（025）核准時查申請人部門的主管', '只提供部門主管的最小介面',
  condition='狀態 025 的核准與退回、審核清單查詢', usedByRefs=[pc('TW_DEMO_REQWRK.APPROVE_PB.FieldChange')],
  evidence=[EV_PC_DEPTMGR, EV_SQL_DEPT_PROFILE], fieldUsage={'noneExcludable': {'checkedOn': '2026-10-01'}})
for name, ev_id, event, comp, why in [
    ('TW_DEMO_REQ.SavePreChange', EV_PC_PRECHANGE, 'SAVE_PRE_CHANGE', REQ, '新單取號'),
    ('TW_DEMO_REQ.SavePostChange', EV_PC_POSTCHANGE, 'SAVE_POST_CHANGE', REQ, '送出後排入通知'),
    ('TW_DEMO_REQHDR.AMOUNT.SaveEdit', EV_PC_AMOUNT, 'SAVE_EDIT', REQ, '金額檢核'),
    ('TW_DEMO_REQHDR.REQUESTER_EMPLID.FieldDefault', EV_PC_DEFAULT, 'FIELD_DEFAULT', REQ, '申請人預設'),
    ('TW_DEMO_REQWRK.SUBMIT_PB.FieldChange', EV_PC_SUBMIT, 'FIELD_CHANGE', REQ, '送出'),
    ('TW_DEMO_REQWRK.WITHDRAW_PB.FieldChange', EV_PC_WITHDRAW, 'FIELD_CHANGE', REQ, '撤回'),
    ('TW_DEMO_REQWRK.APPROVE_PB.FieldChange', EV_PC_APPROVE, 'FIELD_CHANGE', APV, '核准'),
    ('TW_DEMO_REQWRK.RETURN_PB.FieldChange', EV_PC_RETURN, 'FIELD_CHANGE', APV, '退回'),
    ('TW_DEMO_APV.PostBuild', EV_PC_POSTBUILD, 'POST_BUILD', APV, '載入時處理（含圖外的重開邏輯）'),
]:
    O('PEOPLECODE', name, 'CORE', f'掛在 {comp} 核心路徑上的程式', why, condition={'na': '事件觸發即執行'},
      evidence=[EV_META_PC, ev_id], pcEvent=event, component=comp)
O('AE', 'TW_DEMO_NTFY', 'DEPENDENCY', 'TW_DEMO_REQ.SavePostChange 在送出成功後排入', '送審通知',
  condition='送出（010／015→020）成功後', usedByRefs=[pc('TW_DEMO_REQ.SavePostChange')], evidence=[EV_PC_POSTCHANGE, EV_AE_NTFY])
O('MESSAGE_SET', '27000', 'DEPENDENCY', '核心 PeopleCode 以 MsgGet 讀取', '提供四則錯誤訊息原文',
  condition='檢核失敗時', evidence=[EV_META_MSG])
O('ROLE', 'TW_DEMO_REQUESTER', 'DEPENDENCY', 'TW_DEMO_REQ 的元件權限', '申請人角色', condition='進入申請畫面時',
  evidence=[EV_META_ROLE])
O('ROLE', 'TW_DEMO_APPROVER', 'DEPENDENCY', 'TW_DEMO_APV 的元件權限', '審核主管角色', condition='進入審核畫面時',
  evidence=[EV_META_ROLE])

# ---------------- 07 database ----------------
def ENT(rec, name, meaning, keys, eff, physical=None):
    add('ENT', rec, basis='METADATA', evidence=[EV_META_REC], record=obj('RECORD', rec), name=name,
        businessMeaning=meaning, storageKind='SQL_TABLE', physicalName=physical or ('PS_' + rec),
        keys=[F_(rec, k) for k in keys], effectiveDating=eff)
CUR = {'asOf': ctx('CURRENT_DATE'), 'effStatusActiveOnly': True}
ENT(HDR, '申請單', '一張申請單一列；狀態、金額、事由與審核結果都在這裡。', ['REQ_ID'], {'kind': 'NONE'})
ENT(EMP, '員工任職（有效日）', '員工任職資料；本功能只用來找申請人的部門與直屬主管。', ['EMPLID', 'EFFDT'],
    {'kind': 'EFFDT', 'currentRow': CUR})
ENT(DEPT, '部門（有效日）', '部門資料；本功能只用來找部門主管。', ['DEPTID', 'EFFDT'],
    {'kind': 'EFFDT', 'currentRow': CUR})

def FLD(rec, f, label, dtype, length, required='NO', default=None, domain=None, keyRoles=(), relations=None,
        sensitivity='NONE', usage='DATA_HAS_VALUE', decimals=None, evidence=None):
    it = add('FLD', f'{rec}.{f}', basis='METADATA', evidence=evidence or [EV_META_REC], entity=r('ENT', rec),
             fieldName=f, label=label, dataType=dtype, length=length, required=required,
             default=default or {'na': '無 Record 層預設值'}, valueDomain=domain or {'free': True},
             keyRoles=list(keyRoles), sensitivity=sensitivity, usageEvidence=usage)
    if decimals is not None:
        it['decimals'] = decimals
    if relations:
        it['relations'] = relations
    return it

XLAT_STATUS = [('010', '草稿'), ('015', '退回補件'), ('020', '待主管審核'), ('025', '待部門主管審核'),
               ('030', '核准'), ('090', '作廢')]
FLD(HDR, 'REQ_ID', '申請單號', 'CHAR', 10, 'ALWAYS', default=const('NEW'), keyRoles=['KEY', 'SEARCH_KEY'])
FLD(HDR, 'REQUESTER_EMPLID', '申請人', 'CHAR', 11, 'ALWAYS',
    domain={'prompt': {'entity': r('ENT', EMP), 'keyField': F_(EMP, 'EMPLID')}},
    relations=[{'target': F_(EMP, 'EMPLID'), 'kind': 'LOGICAL_FK'}], sensitivity='PERSONAL')
FLD(HDR, 'REQ_STATUS', '狀態', 'CHAR', 3, 'ALWAYS', default=const('010'),
    domain={'xlat': [{'stored': c, 'label': n, 'active': True, 'dataPresence': 'HAS_DATA'} for c, n in XLAT_STATUS]},
    evidence=[EV_META_REC, EV_SQL_STATUS])
FLD(HDR, 'AMOUNT', '金額', 'NUMBER', 11, 'ALWAYS', decimals=2)
FLD(HDR, 'REASON', '申請事由', 'CHAR', 254, 'ALWAYS')
FLD(HDR, 'COMMENTS', '審核意見', 'CHAR', 254, 'CONDITIONAL')
FLD(HDR, 'SUBMIT_DT', '送出日', 'DATE', {'na': '日期型別沒有長度'})
FLD(HDR, 'APPROVER_EMPLID', '核准者', 'CHAR', 11, sensitivity='PERSONAL',
    relations=[{'target': F_(EMP, 'EMPLID'), 'kind': 'LOGICAL_FK'}])
FLD(HDR, 'APPROVE_DT', '核准日', 'DATE', {'na': '日期型別沒有長度'})
FLD(EMP, 'EMPLID', '員工編號', 'CHAR', 11, 'ALWAYS', keyRoles=['KEY'], sensitivity='PERSONAL', usage='CODE_REFERENCED')
FLD(EMP, 'EFFDT', '生效日', 'DATE', {'na': '日期型別沒有長度'}, 'ALWAYS', keyRoles=['KEY'], usage='CODE_REFERENCED')
FLD(EMP, 'EFF_STATUS', '有效狀態', 'CHAR', 1, 'ALWAYS',
    domain={'xlat': [{'stored': 'A', 'label': '有效', 'active': True, 'dataPresence': 'HAS_DATA'},
                     {'stored': 'I', 'label': '無效', 'active': True, 'dataPresence': 'HAS_DATA'}]}, usage='CODE_REFERENCED')
FLD(EMP, 'DEPTID', '部門', 'CHAR', 10, 'ALWAYS', domain={'prompt': {'entity': r('ENT', DEPT), 'keyField': F_(DEPT, 'DEPTID')}},
    relations=[{'target': F_(DEPT, 'DEPTID'), 'kind': 'LOGICAL_FK'}], usage='CODE_REFERENCED')
FLD(EMP, 'SUPERVISOR_ID', '直屬主管', 'CHAR', 11, domain={'prompt': {'entity': r('ENT', EMP), 'keyField': F_(EMP, 'EMPLID')}},
    relations=[{'target': F_(EMP, 'EMPLID'), 'kind': 'LOGICAL_FK'}], sensitivity='PERSONAL', usage='CODE_REFERENCED',
    evidence=[EV_META_REC, EV_SQL_EMP_PROFILE])
FLD(DEPT, 'DEPTID', '部門', 'CHAR', 10, 'ALWAYS', keyRoles=['KEY'], usage='CODE_REFERENCED')
FLD(DEPT, 'EFFDT', '生效日', 'DATE', {'na': '日期型別沒有長度'}, 'ALWAYS', keyRoles=['KEY'], usage='CODE_REFERENCED')
FLD(DEPT, 'EFF_STATUS', '有效狀態', 'CHAR', 1, 'ALWAYS',
    domain={'xlat': [{'stored': 'A', 'label': '有效', 'active': True, 'dataPresence': 'HAS_DATA'},
                     {'stored': 'I', 'label': '無效', 'active': True, 'dataPresence': 'HAS_DATA'}]}, usage='CODE_REFERENCED')
FLD(DEPT, 'MANAGER_ID', '部門主管', 'CHAR', 11, domain={'prompt': {'entity': r('ENT', EMP), 'keyField': F_(EMP, 'EMPLID')}},
    relations=[{'target': F_(EMP, 'EMPLID'), 'kind': 'LOGICAL_FK'}], sensitivity='PERSONAL', usage='CODE_REFERENCED',
    evidence=[EV_META_REC, EV_SQL_DEPT_PROFILE])

REQUESTER_INPUT = [{'name': 'REQUESTER', 'from': fld(HDR, 'REQUESTER_EMPLID')}]
EFF_EMP = {'entity': r('ENT', EMP), 'rule': 'CURRENT_ROW', 'asOf': ctx('CURRENT_DATE'), 'effStatusActiveOnly': True}
EFF_DEPT = {'entity': r('ENT', DEPT), 'rule': 'CURRENT_ROW', 'asOf': ctx('CURRENT_DATE'), 'effStatusActiveOnly': True}
add('DRV', 'REQUESTER_SUPERVISOR', basis='CODE', evidence=[EV_PC_SUPERVISOR, EV_SQL_EMP_PROFILE],
    name='申請人的直屬主管', meaning='申請人目前任職資料上登記的直屬主管；送出時必須存在，020 由此人審核。',
    inputs=REQUESTER_INPUT, resultType='PERSON_ID',
    resolution={'sources': [r('ENT', EMP)],
                'joins': [{'left': F_(EMP, 'EMPLID'), 'right': {'param': 'REQUESTER'}}],
                'filter': 'ALWAYS', 'effectiveDating': [EFF_EMP], 'pick': F_(EMP, 'SUPERVISOR_ID'),
                'tieBreak': {'na': '鍵（EMPLID＋EFFDT）加目前有效列規則保證只有一列'}},
    whenNotFound={'result': 'EMPTY', 'note': '查無目前有效的任職列，或 SUPERVISOR_ID 為空白時結果為空；送出時由 09 的規則擋下。'},
    whenMultiple={'rule': 'UNIQUE_BY_KEY', 'note': '目前有效列規則下每位員工只有一列。'},
    implementedAt=[pc('TW_DEMO_REQWRK.SUBMIT_PB.FieldChange'), pc('TW_DEMO_REQWRK.APPROVE_PB.FieldChange'),
                   pc('TW_DEMO_REQWRK.RETURN_PB.FieldChange')])
add('DRV', 'REQUESTER_DEPT_MANAGER', basis='CODE', evidence=[EV_PC_DEPTMGR, EV_SQL_DEPT_PROFILE],
    name='申請人的部門主管', meaning='申請人目前任職部門的主管；025（高額）由此人審核。',
    inputs=REQUESTER_INPUT, resultType='PERSON_ID',
    resolution={'sources': [r('ENT', EMP), r('ENT', DEPT)],
                'joins': [{'left': F_(EMP, 'EMPLID'), 'right': {'param': 'REQUESTER'}},
                          {'left': F_(DEPT, 'DEPTID'), 'right': fld(EMP, 'DEPTID')}],
                'filter': 'ALWAYS', 'effectiveDating': [EFF_EMP, EFF_DEPT], 'pick': F_(DEPT, 'MANAGER_ID'),
                'tieBreak': {'na': '兩個實體都取目前有效列，結果唯一'}},
    whenNotFound={'result': 'EMPTY', 'note': '部門沒有目前有效列或 MANAGER_ID 為空白時結果為空；原系統對此沒有檢查，案件會停在 025，審核清單中沒有人看得到。'},
    whenMultiple={'rule': 'UNIQUE_BY_KEY', 'note': '兩個實體的目前有效列各只有一列。'},
    implementedAt=[pc('TW_DEMO_REQWRK.APPROVE_PB.FieldChange'), pc('TW_DEMO_REQWRK.RETURN_PB.FieldChange')])
add('XF', HDR, basis='DATA', evidence=[EV_SQL_XF_DATA, EV_SQL_XF_XREF], entity=r('ENT', HDR),
    fields=['OLD_REF_NO', 'PRIORITY_CD'], dataCheck='非預設 0 筆（全表非空，查詢日 2026-10-01）',
    codeChecks={'a': 'PeopleCode 交叉參照：核心路徑沒有指名引用。', 'b': '核心路徑沒有 AE、SQR 或 SQL 物件讀寫這兩欄。',
                'c': '既有研究文件沒有指名引用的紀錄。'})

# ---------------- 03 roles ----------------
add('ROLE', 'ROLE:TW_DEMO_APPROVER', basis='METADATA', evidence=[EV_META_ROLE], principalType='ROLE',
    object=obj('ROLE', 'TW_DEMO_APPROVER'), name='審核主管',
    membership={'kind': 'STATIC_ASSIGNMENT', 'note': '由系統管理者指派給擔任主管的人；指派作業不在本功能範圍。'})
add('ROLE', 'ROLE:TW_DEMO_REQUESTER', basis='METADATA', evidence=[EV_META_ROLE], principalType='ROLE',
    object=obj('ROLE', 'TW_DEMO_REQUESTER'), name='申請人',
    membership={'kind': 'STATIC_ASSIGNMENT', 'note': '一般員工皆有；指派作業不在本功能範圍。'})
add('PERM', 'ROLE:TW_DEMO_APPROVER>COMPONENT:TW_DEMO_APV', basis='CODE', evidence=[EV_META_ROLE, EV_ROWSEC],
    principal=r('ROLE', 'ROLE:TW_DEMO_APPROVER'), resource=obj('COMPONENT', APV), actions=['UPDATE_DISPLAY'],
    dataScope={'condition': ALL(P(fld(HDR, 'REQ_STATUS'), 'IN', [const('020'), const('025')]),
                                ANY(P(SUPERVISOR, 'EQ', ME), P(DEPT_MGR, 'EQ', ME))),
               'note': '審核清單只列出待審（020、025）且自己是直屬主管或部門主管的申請單。'},
    denial={'effect': 'ROWS_FILTERED', 'note': '查詢結果不含他人的申請單。'}, enforcement='ROW_LEVEL_SECURITY')
add('PERM', 'ROLE:TW_DEMO_REQUESTER>COMPONENT:TW_DEMO_REQ', basis='CODE', evidence=[EV_META_ROLE, EV_ROWSEC_REQ],
    principal=r('ROLE', 'ROLE:TW_DEMO_REQUESTER'), resource=obj('COMPONENT', REQ), actions=['ADD', 'UPDATE_DISPLAY'],
    dataScope={'condition': P(fld(HDR, 'REQUESTER_EMPLID'), 'EQ', ME), 'note': '只看得到自己的申請單。'},
    denial={'effect': 'ROWS_FILTERED', 'note': '查詢結果不含他人的申請單。'}, enforcement='ROW_LEVEL_SECURITY')

# ---------------- 04 workflow ----------------
for code, name in XLAT_STATUS:
    add('STATE', f'REQ_STATUS:{code}', basis='AUTHORITATIVE_DOC',
        evidence=[sdl(f'state "{code} ', start_after=SD), EV_SQL_STATUS],
        entityKey='REQ_STATUS', stateKind='SIMPLE', code=code, name=f'{code} {name}', binding=F_(HDR, 'REQ_STATUS'),
        domainLabel=name, isInitialTarget=(code == '010'), isFinal=(code in ('030', '090')), dataPresence='HAS_DATA')

def TRN(frm, to, sd_edge, fc_edge, trigger, actor, guard, writes, impl, reentry, impl_ev, via=None,
        side=None):
    k = f'REQ_STATUS:{"*" if frm == "INITIAL" else frm}>{to}'
    it = add('TRN', k, basis='AUTHORITATIVE_DOC',
             evidence=[sdl(sd_edge, start_after=SD), sdl(fc_edge, start_after=FC)] + impl_ev,
             entityKey='REQ_STATUS', **{'from': 'INITIAL' if frm == 'INITIAL' else r('STATE', f'REQ_STATUS:{frm}')},
             to=r('STATE', f'REQ_STATUS:{to}'), trigger=trigger, actor=actor, guard=guard, writes=writes,
             sideEffects=side or {'na': '轉移本身沒有其他副作用；送出通知由 09 的規則觸發'}, implementedAt=impl,
             reentry=reentry)
    if via:
        it['via'] = via
    return it

def T_USER(comp, action, event='FIELD_CHANGE'):
    t = {'kind': 'USER_ACTION', 'object': obj('COMPONENT', comp), 'action': action}
    if event:
        t['event'] = event
    return t
NO_GUARD = {'na': '起點只有這一個目標，沒有條件分岔'}
APPROVER_020 = ALL(HAS_APPROVER, P(SUPERVISOR, 'EQ', ME))
APPROVER_025 = ALL(HAS_APPROVER, P(DEPT_MGR, 'EQ', ME))
REQUESTER_ACTOR = ALL(HAS_REQUESTER, IS_REQUESTER)
TODAY = ctx('CURRENT_DATE')

TRN('INITIAL', '010', '[*] --> S010', 'START((開始))', T_USER(REQ, '儲存（新增模式）', None), HAS_REQUESTER, NO_GUARD,
    [set_status('010')], [{'object': obj('COMPONENT', REQ), 'event': 'Save（ADD 模式；REQ_STATUS 取 Record 預設值）'}],
    '同一張新單存檔後畫面轉為修改模式；再按儲存是一般存檔，不會再建立一張。', [EV_META_REQ])
TRN('010', '020', 'S010 --> S020', 'N010 -->|主流程| N020', T_USER(REQ, '按「送出」（TW_DEMO_REQWRK.SUBMIT_PB）'),
    REQUESTER_ACTOR, NO_GUARD,
    [set_status('020'), {'field': F_(HDR, 'SUBMIT_DT'), 'value': TODAY}],
    [{'object': pc('TW_DEMO_REQWRK.SUBMIT_PB.FieldChange'), 'event': 'FieldChange'}],
    '送出後按鈕隱藏（見 05）；兩個視窗重複送出時，後存檔者因資料已被更新而被拒絕，狀態不變。', [EV_PC_SUBMIT])
TRN('015', '020', 'S015 --> S020', 'N015 -->|退回補件| N020', T_USER(REQ, '按「送出」（TW_DEMO_REQWRK.SUBMIT_PB）'),
    REQUESTER_ACTOR, NO_GUARD,
    [set_status('020'), {'field': F_(HDR, 'SUBMIT_DT'), 'value': TODAY}],
    [{'object': pc('TW_DEMO_REQWRK.SUBMIT_PB.FieldChange'), 'event': 'FieldChange'}],
    '同 010→020；重新送出會覆寫送出日。', [EV_PC_SUBMIT])
TRN('010', '090', 'S010 --> S090', 'N010 -->|撤回作廢| N090', T_USER(REQ, '按「撤回」（TW_DEMO_REQWRK.WITHDRAW_PB）'),
    REQUESTER_ACTOR, NO_GUARD, [set_status('090')],
    [{'object': pc('TW_DEMO_REQWRK.WITHDRAW_PB.FieldChange'), 'event': 'FieldChange'}],
    '作廢是終點；撤回後按鈕隱藏，不能再操作。', [EV_PC_WITHDRAW])
TRN('015', '090', 'S015 --> S090', 'N015 -->|撤回作廢| N090', T_USER(REQ, '按「撤回」（TW_DEMO_REQWRK.WITHDRAW_PB）'),
    REQUESTER_ACTOR, NO_GUARD, [set_status('090')],
    [{'object': pc('TW_DEMO_REQWRK.WITHDRAW_PB.FieldChange'), 'event': 'FieldChange'}],
    '同 010→090。', [EV_PC_WITHDRAW])
TRN('020', '030', 'amount_check --> S030', 'D1 -->|主流程| N030', T_USER(APV, '按「核准」（TW_DEMO_REQWRK.APPROVE_PB）'),
    APPROVER_020, P(fld(HDR, 'AMOUNT'), 'LE', const('50000', 'NUMBER')),
    [set_status('030'), {'field': F_(HDR, 'APPROVER_EMPLID'), 'value': ME}, {'field': F_(HDR, 'APPROVE_DT'), 'value': TODAY}],
    [{'object': pc('TW_DEMO_REQWRK.APPROVE_PB.FieldChange'), 'event': 'FieldChange'}],
    '核准後按鈕隱藏；兩位審核者同時核准時，後存檔者被拒絕（見 08 的併發行為）。', [EV_PC_APPROVE, EV_PC_APPROVE_ACTOR],
    via=['amount_check'])
TRN('020', '025', 'amount_check --> S025', 'D1 -->|高額審核| N025', T_USER(APV, '按「核准」（TW_DEMO_REQWRK.APPROVE_PB）'),
    APPROVER_020, P(fld(HDR, 'AMOUNT'), 'GT', const('50000', 'NUMBER')), [set_status('025')],
    [{'object': pc('TW_DEMO_REQWRK.APPROVE_PB.FieldChange'), 'event': 'FieldChange'}],
    '轉入 025 後由部門主管審核；直屬主管不能再操作。', [EV_PC_APPROVE, EV_PC_APPROVE_ACTOR], via=['amount_check'])
TRN('025', '030', 'S025 --> S030', 'N025 -->|高額審核| N030', T_USER(APV, '按「核准」（TW_DEMO_REQWRK.APPROVE_PB）'),
    APPROVER_025, {'na': '025 按核准只有一個目標'},
    [set_status('030'), {'field': F_(HDR, 'APPROVER_EMPLID'), 'value': ME}, {'field': F_(HDR, 'APPROVE_DT'), 'value': TODAY}],
    [{'object': pc('TW_DEMO_REQWRK.APPROVE_PB.FieldChange'), 'event': 'FieldChange'}],
    '核准者欄位記錄部門主管；同 020→030 的併發行為。', [EV_PC_APPROVE, EV_PC_APPROVE_ACTOR])
TRN('020', '015', 'S020 --> S015', 'N020 -->|退回補件| N015', T_USER(APV, '按「退回」（TW_DEMO_REQWRK.RETURN_PB）'),
    APPROVER_020, NO_GUARD, [set_status('015')],
    [{'object': pc('TW_DEMO_REQWRK.RETURN_PB.FieldChange'), 'event': 'FieldChange'}],
    '退回後按鈕隱藏；申請人可修改後重新送出。', [EV_PC_RETURN, EV_PC_APPROVE_ACTOR])
TRN('025', '015', 'S025 --> S015', 'N025 -->|退回補件| N015', T_USER(APV, '按「退回」（TW_DEMO_REQWRK.RETURN_PB）'),
    APPROVER_025, NO_GUARD, [set_status('015')],
    [{'object': pc('TW_DEMO_REQWRK.RETURN_PB.FieldChange'), 'event': 'FieldChange'}],
    '同 020→015；重新送出後回到 020，由直屬主管重新審核。', [EV_PC_RETURN, EV_PC_APPROVE_ACTOR])

def T(frm, to):
    return r('TRN', f'REQ_STATUS:{frm}>{to}')
def FLOW(label, narrative, steps, entry, exit_, exceptions):
    add('FLOW', f'REQ_STATUS:{label}', basis='AUTHORITATIVE_DOC',
        evidence=[sdl(f'|{label}|', start_after=FC)], entityKey='REQ_STATUS', scenarioType=label, narrative=narrative,
        steps=[{'seq': i + 1, 'transition': t, 'description': d} for i, (t, d) in enumerate(steps)],
        entryStates=entry, exitStates=exit_, preconditions={'na': '進入條件即各步驟轉移的起點狀態'},
        exceptions=exceptions)
FLOW('主流程', '申請人建立並送出，直屬主管核准；金額不超過 50000 時一次核准結案。',
     [(T('*', '010'), '申請人建立草稿'), (T('010', '020'), '申請人送出'), (T('020', '030'), '直屬主管核准（金額 ≤ 50000）')],
     ['INITIAL'], [r('STATE', 'REQ_STATUS:030')],
     '金額超過 50000 轉入「高額審核」；主管退回轉入「退回補件」；草稿可轉入「撤回作廢」。')
FLOW('高額審核', '金額超過 50000 時，直屬主管核准後再由部門主管核准。',
     [(T('020', '025'), '直屬主管核准（金額 > 50000），轉部門主管'), (T('025', '030'), '部門主管核准')],
     [r('STATE', 'REQ_STATUS:020')], [r('STATE', 'REQ_STATUS:030')], '部門主管可退回，轉入「退回補件」。')
FLOW('退回補件', '審核者退回後，申請人補件重新送出，回到直屬主管審核。',
     [(T('020', '015'), '直屬主管退回'), (T('025', '015'), '部門主管退回'), (T('015', '020'), '申請人修改後重新送出')],
     [r('STATE', 'REQ_STATUS:020'), r('STATE', 'REQ_STATUS:025')], [r('STATE', 'REQ_STATUS:020')],
     '退回補件中的申請人也可撤回，轉入「撤回作廢」。')
FLOW('撤回作廢', '申請人在送出前或被退回後撤回，申請單作廢結束。',
     [(T('010', '090'), '撤回草稿'), (T('015', '090'), '撤回退回中的申請')],
     [r('STATE', 'REQ_STATUS:010'), r('STATE', 'REQ_STATUS:015')], [r('STATE', 'REQ_STATUS:090')],
     {'na': '作廢是終點'})

# ---------------- 06 architecture ----------------
add('IF', 'AE:TW_DEMO_NTFY', basis='CODE', evidence=[EV_PC_POSTCHANGE, EV_AE_NTFY], ifType='NOTIFICATION',
    object=obj('AE', 'TW_DEMO_NTFY'), name='送審通知', direction='OUTBOUND',
    trigger={'kind': 'ON_TRANSITION', 'transitions': [T('010', '020'), T('015', '020')],
             'note': '送出成功後由 SavePostChange 排入程序，非同步執行。'},
    performs=[], reads=[F_(HDR, 'REQ_ID'), F_(HDR, 'REQUESTER_EMPLID'), F_(HDR, 'AMOUNT'), F_(EMP, 'SUPERVISOR_ID')],
    writes=[], parameters=[{'name': 'REQ_ID', 'source': fld(HDR, 'REQ_ID')}],
    format={'na': '不是檔案介面'}, errorHandling='寄送失敗只寫入程序紀錄，不影響申請單狀態。',
    retry={'na': '原系統不重試'}, idempotency='同一張單重複排入會重複寄送通知。')

# ---------------- 02 functional requirements ----------------
def FR(comp, op, name, desc, kind, modes, actors, realizes, pre, outcome):
    add('FR', f'{comp}:{op}', basis='DERIVED', derivedFrom=list(realizes) or [obj('COMPONENT', comp)],
        component=comp, name=name, description=desc, frKind=kind, entry={'object': obj('COMPONENT', comp), 'modes': modes},
        actors=actors, realizes=list(realizes), preconditions=pre, outcome=outcome, priority='MUST')
FR(REQ, 'CREATE', '建立申請', '申請人在新增模式輸入金額與事由並存檔，建立狀態為草稿的申請單。', 'TRANSITION', ['ADD'],
   [{'role': r('ROLE', 'ROLE:TW_DEMO_REQUESTER')}], [T('*', '010')], {'na': '新建沒有前置狀態'},
   '產生一張狀態 010 的申請單，申請人為目前使用者、單號已取號。')
FR(REQ, 'SUBMIT', '送出申請', '申請人把草稿或退回補件中的申請單送出給直屬主管審核。', 'TRANSITION', ['UPDATE_DISPLAY'],
   [{'role': r('ROLE', 'ROLE:TW_DEMO_REQUESTER')}], [T('010', '020'), T('015', '020')], status_in('010', '015'),
   '狀態變為 020，記錄送出日，並排入送審通知。')
FR(REQ, 'WITHDRAW', '撤回申請', '申請人撤回尚未送出或被退回的申請單，申請單作廢。', 'TRANSITION', ['UPDATE_DISPLAY'],
   [{'role': r('ROLE', 'ROLE:TW_DEMO_REQUESTER')}], [T('010', '090'), T('015', '090')], status_in('010', '015'),
   '狀態變為 090（終點）。')
FR(APV, 'APPROVE', '核准申請', '直屬主管核准待審申請；金額超過 50000 時轉部門主管再核准。', 'TRANSITION', ['UPDATE_DISPLAY'],
   [{'role': r('ROLE', 'ROLE:TW_DEMO_APPROVER')}, SUPERVISOR, DEPT_MGR],
   [T('020', '030'), T('020', '025'), T('025', '030')], status_in('020', '025'),
   '狀態變為 030 並記錄核准者與核准日；或在高額時變為 025。')
FR(APV, 'RETURN', '退回申請', '審核者填寫意見後退回，申請人可補件重新送出。', 'TRANSITION', ['UPDATE_DISPLAY'],
   [{'role': r('ROLE', 'ROLE:TW_DEMO_APPROVER')}, SUPERVISOR, DEPT_MGR], [T('020', '015'), T('025', '015')],
   status_in('020', '025'), '狀態變為 015，保留審核意見。')

# ---------------- 05 UI ----------------
def FRr(comp, op):
    return r('FR', f'{comp}:{op}')
def CONTROL(comp, page, rec, f, ctype, label, usedBy, ev_ids, editability, visibility='ALWAYS', presence='VISIBLE',
            binding=None, value_kind='FREE', options=None, region='HEADER'):
    it = add('UI', f'{comp}.{page}.{rec}.{f}', basis='METADATA', evidence=ev_ids, uiKind='CONTROL', usedBy=usedBy,
             screen=r('UI', f'{comp}.{page}'), region=region, controlType=ctype,
             binding=binding or {'fld': F_(rec, f)}, label=label, presence=presence, visibility=visibility,
             editability=editability, valueSource={'kind': value_kind},
             displayDefault={'na': '顯示資料庫中的值'})
    if options:
        it['options'] = options
    return it
BUTTON = {'na': '按鈕；原系統以工作記錄欄位承載事件，不保存資料'}
for comp, page, title, modes, usedBy, ev_ids in [
    (REQ, 'TW_DEMO_REQPG', '申請單', ['ADD', 'UPDATE_DISPLAY'],
     [FRr(REQ, 'CREATE'), FRr(REQ, 'SUBMIT'), FRr(REQ, 'WITHDRAW')], [EV_META_REQ]),
    (APV, 'TW_DEMO_APVPG', '申請單審核', ['UPDATE_DISPLAY'], [FRr(APV, 'APPROVE'), FRr(APV, 'RETURN')], [EV_META_APV]),
]:
    add('UI', f'{comp}.{page}', basis='METADATA', evidence=ev_ids, uiKind='SCREEN', usedBy=usedBy,
        component=obj('COMPONENT', comp), page=obj('PAGE', page), title=title, pageRole='MAIN', modes=modes,
        searchKeys=[F_(HDR, 'REQ_ID')],
        regions=[{'key': 'HEADER', 'label': '申請內容', 'scrollLevel': 0, 'repeating': False},
                 {'key': 'ACTIONS', 'label': {'na': '按鈕列沒有標題'}, 'scrollLevel': 0, 'repeating': False}])
EDIT_REQ = status_in('010', '015')
EDIT_APV = status_in('020', '025')
CONTROL(REQ, 'TW_DEMO_REQPG', HDR, 'AMOUNT', 'EDIT_BOX', '金額', [FRr(REQ, 'CREATE'), FRr(REQ, 'SUBMIT')],
        [EV_META_REQ, EV_PAGE_HIDE_REQ], EDIT_REQ)
CONTROL(REQ, 'TW_DEMO_REQPG', HDR, 'REASON', 'LONG_EDIT', '申請事由', [FRr(REQ, 'CREATE'), FRr(REQ, 'SUBMIT')],
        [EV_META_REQ, EV_PAGE_HIDE_REQ], EDIT_REQ)
CONTROL(REQ, 'TW_DEMO_REQPG', HDR, 'REQ_STATUS', 'DROP_DOWN', '狀態',
        [FRr(REQ, 'CREATE'), FRr(REQ, 'SUBMIT'), FRr(REQ, 'WITHDRAW')], [EV_META_REQ], 'NEVER', value_kind='XLAT',
        options=[{'label': n, 'stored': c} for c, n in XLAT_STATUS])
CONTROL(REQ, 'TW_DEMO_REQPG', WRK, 'SUBMIT_PB', 'PUSH_BUTTON', '送出', [FRr(REQ, 'SUBMIT')],
        [EV_META_REQ, EV_PAGE_HIDE_REQ], 'ALWAYS', visibility=EDIT_REQ, presence='CONDITIONAL', binding=BUTTON,
        value_kind='NONE', region='ACTIONS')
CONTROL(REQ, 'TW_DEMO_REQPG', WRK, 'WITHDRAW_PB', 'PUSH_BUTTON', '撤回', [FRr(REQ, 'WITHDRAW')],
        [EV_META_REQ, EV_PAGE_HIDE_REQ], 'ALWAYS', visibility=EDIT_REQ, presence='CONDITIONAL', binding=BUTTON,
        value_kind='NONE', region='ACTIONS')
CONTROL(APV, 'TW_DEMO_APVPG', HDR, 'AMOUNT', 'EDIT_BOX', '金額', [FRr(APV, 'APPROVE'), FRr(APV, 'RETURN')],
        [EV_META_APV], 'NEVER')
CONTROL(APV, 'TW_DEMO_APVPG', HDR, 'REASON', 'LONG_EDIT', '申請事由', [FRr(APV, 'APPROVE'), FRr(APV, 'RETURN')],
        [EV_META_APV], 'NEVER')
CONTROL(APV, 'TW_DEMO_APVPG', HDR, 'COMMENTS', 'LONG_EDIT', '審核意見', [FRr(APV, 'APPROVE'), FRr(APV, 'RETURN')],
        [EV_META_APV, EV_PAGE_HIDE_APV], EDIT_APV)
CONTROL(APV, 'TW_DEMO_APVPG', WRK, 'APPROVE_PB', 'PUSH_BUTTON', '核准', [FRr(APV, 'APPROVE')],
        [EV_META_APV, EV_PAGE_HIDE_APV], 'ALWAYS', visibility=EDIT_APV, presence='CONDITIONAL', binding=BUTTON,
        value_kind='NONE', region='ACTIONS')
CONTROL(APV, 'TW_DEMO_APVPG', WRK, 'RETURN_PB', 'PUSH_BUTTON', '退回', [FRr(APV, 'RETURN')],
        [EV_META_APV, EV_PAGE_HIDE_APV], 'ALWAYS', visibility=EDIT_APV, presence='CONDITIONAL', binding=BUTTON,
        value_kind='NONE', region='ACTIONS')

def UIr(comp, page, rec, f):
    return r('UI', f'{comp}.{page}.{rec}.{f}')

# ---------------- 09 business logic ----------------
for n, text in [(1, '金額必須大於 0。'), (2, '退回時必須填寫審核意見。'), (3, '找不到直屬主管，無法送出。'),
                (4, '此申請單已被其他使用者更新，請重新查詢。')]:
    add('MSG', f'27000,{n}', basis='METADATA', evidence=[EV_META_MSG], messageSet=27000, messageNumber=n, text=text,
        severity='ERROR')
def M(n):
    return r('MSG', f'27000,{n}')
def BR(loc, code, name, kind, applies, trigger, cond, action, boundaries, modes, ev_ids, order=1):
    add('BR', f'{loc}:{code}', basis='CODE', evidence=ev_ids, name=name, brKind=kind, appliesTo=applies, trigger=trigger,
        condition=cond, action=action, order=order, boundaries=boundaries, modeDifferences=modes,
        implementedAt={'object': pc(loc), 'event': loc.split('.')[-1]})
BR('TW_DEMO_REQHDR.AMOUNT.SaveEdit', 'AMOUNT_POSITIVE', '金額必須大於 0', 'VALIDATION',
   [FRr(REQ, 'CREATE'), FRr(REQ, 'SUBMIT'), FRr(REQ, 'WITHDRAW')],
   {'event': 'SAVE_EDIT', 'modes': ['ADD', 'UPDATE_DISPLAY']}, P(fld(HDR, 'AMOUNT'), 'LE', const('0', 'NUMBER')),
   {'kind': 'REJECT', 'message': M(1)},
   '0 拒絕；最小可接受 0.01（小數 2 位）；未輸入時數值欄存 0，視同 0 拒絕。', {'na': '新增與修改相同'}, [EV_PC_AMOUNT])
BR('TW_DEMO_REQHDR.REQUESTER_EMPLID.FieldDefault', 'REQUESTER_DEFAULT', '申請人預設為目前使用者', 'DEFAULTING',
   [FRr(REQ, 'CREATE')], {'event': 'FIELD_DEFAULT', 'modes': ['ADD']}, P(fld(HDR, 'REQUESTER_EMPLID'), 'IS_BLANK'),
   {'kind': 'SET_VALUE', 'assignments': [{'field': F_(HDR, 'REQUESTER_EMPLID'), 'value': ME}]},
   {'na': '沒有數值或日期判斷'}, '只在新增模式；修改模式不會重設申請人。', [EV_PC_DEFAULT])
BR('TW_DEMO_REQ.SavePreChange', 'ASSIGN_REQ_ID', '新單取號', 'DEFAULTING', [FRr(REQ, 'CREATE')],
   {'event': 'SAVE_PRE_CHANGE', 'transitions': [T('*', '010')], 'modes': ['ADD']},
   P(fld(HDR, 'REQ_ID'), 'EQ', const('NEW')),
   {'kind': 'SET_VALUE', 'assignments': [{'field': F_(HDR, 'REQ_ID'),
                                          'value': {'expr': '現有最大 REQ_ID 的數值加 1，左補零到 10 碼'}}]},
   '第一張單取 0000000001；兩張新單同時存檔可能取到同號，後存檔者因主鍵重複而失敗（原系統沒有重試）。',
   '只在新增模式。', [EV_PC_PRECHANGE])
BR('TW_DEMO_REQ.SavePostChange', 'NOTIFY_SUPERVISOR', '送出後通知直屬主管', 'SIDE_EFFECT', [FRr(REQ, 'SUBMIT')],
   {'event': 'SAVE_POST_CHANGE', 'transitions': [T('010', '020'), T('015', '020')]}, status_is('020'),
   {'kind': 'NOTIFY', 'interface': r('IF', 'AE:TW_DEMO_NTFY')}, {'na': '沒有數值或日期判斷'},
   {'na': '只在送出成功的存檔執行'}, [EV_PC_POSTCHANGE])
BR('TW_DEMO_REQWRK.SUBMIT_PB.FieldChange', 'SUPERVISOR_REQUIRED', '送出時申請人必須有直屬主管', 'VALIDATION',
   [FRr(REQ, 'SUBMIT')],
   {'event': 'FIELD_CHANGE', 'control': UIr(REQ, 'TW_DEMO_REQPG', WRK, 'SUBMIT_PB'),
    'transitions': [T('010', '020'), T('015', '020')]},
   P(SUPERVISOR, 'NOT_EXISTS'), {'kind': 'REJECT', 'message': M(3)},
   'SUPERVISOR_ID 為空白（單一空白）視同找不到。', {'na': '只在按送出時檢查'}, [EV_PC_SUBMIT, EV_PC_SUPERVISOR])
BR('TW_DEMO_REQWRK.RETURN_PB.FieldChange', 'RETURN_COMMENT_REQUIRED', '退回時必須填寫審核意見', 'VALIDATION',
   [FRr(APV, 'RETURN')],
   {'event': 'FIELD_CHANGE', 'control': UIr(APV, 'TW_DEMO_APVPG', WRK, 'RETURN_PB'),
    'transitions': [T('020', '015'), T('025', '015')]},
   P(fld(HDR, 'COMMENTS'), 'IS_BLANK'), {'kind': 'REJECT', 'message': M(2)},
   '只輸入空白字元視同未填寫。', {'na': '直屬主管與部門主管相同'}, [EV_PC_RETURN])

def BRr(loc, code):
    return r('BR', f'{loc}:{code}')
PROGRAM_DISPOSITIONS = [
    {'program': pc('TW_DEMO_APV.PostBuild'), 'kinds': ['OFF_DIAGRAM_ONLY'], 'items': [],
     'note': '只有狀態圖外的「核准後重開為草稿」邏輯，列入 90 問題清單。'},
    {'program': pc('TW_DEMO_REQ.SavePostChange'), 'kinds': ['BUSINESS_RULES'],
     'items': [BRr('TW_DEMO_REQ.SavePostChange', 'NOTIFY_SUPERVISOR')]},
    {'program': pc('TW_DEMO_REQ.SavePreChange'), 'kinds': ['BUSINESS_RULES'],
     'items': [BRr('TW_DEMO_REQ.SavePreChange', 'ASSIGN_REQ_ID')]},
    {'program': pc('TW_DEMO_REQHDR.AMOUNT.SaveEdit'), 'kinds': ['BUSINESS_RULES'],
     'items': [BRr('TW_DEMO_REQHDR.AMOUNT.SaveEdit', 'AMOUNT_POSITIVE')]},
    {'program': pc('TW_DEMO_REQHDR.REQUESTER_EMPLID.FieldDefault'), 'kinds': ['BUSINESS_RULES'],
     'items': [BRr('TW_DEMO_REQHDR.REQUESTER_EMPLID.FieldDefault', 'REQUESTER_DEFAULT')]},
    {'program': pc('TW_DEMO_REQWRK.APPROVE_PB.FieldChange'), 'kinds': ['TRANSITION_IMPL'],
     'items': [T('020', '030'), T('020', '025'), T('025', '030')]},
    {'program': pc('TW_DEMO_REQWRK.RETURN_PB.FieldChange'), 'kinds': ['TRANSITION_IMPL', 'BUSINESS_RULES'],
     'items': [T('020', '015'), T('025', '015'), BRr('TW_DEMO_REQWRK.RETURN_PB.FieldChange', 'RETURN_COMMENT_REQUIRED')]},
    {'program': pc('TW_DEMO_REQWRK.SUBMIT_PB.FieldChange'), 'kinds': ['TRANSITION_IMPL', 'BUSINESS_RULES'],
     'items': [T('010', '020'), T('015', '020'), BRr('TW_DEMO_REQWRK.SUBMIT_PB.FieldChange', 'SUPERVISOR_REQUIRED')]},
    {'program': pc('TW_DEMO_REQWRK.WITHDRAW_PB.FieldChange'), 'kinds': ['TRANSITION_IMPL'],
     'items': [T('010', '090'), T('015', '090')]},
]

# ---------------- 08 api ----------------
CONCURRENCY = {'strategy': 'STALE_DATA_CHECK',
               'legacyBehavior': '開啟後到存檔之間若資料已被他人更新，存檔被拒絕並顯示訊息，該筆維持先存檔者的結果，本次輸入不寫入。',
               'message': M(4)}
def OP(comp, frop, op, name, kind, invoked, auth, inputs, outputs, pre, validations, effects, boundary, write_order,
       on_fail, conc, idem, events, prog, ev_ids):
    add('OP', f'{comp}:{frop}:{op}', basis='DERIVED', derivedFrom=[FRr(comp, frop)], evidence=ev_ids, component=comp,
        fr=FRr(comp, frop), name=name, opKind=kind, invokedFrom=invoked, authorization=auth, inputs=inputs,
        outputs=outputs, preconditions=pre, validations=validations, effects=effects,
        transaction={'boundary': boundary, 'writeOrder': write_order, 'onFailure': on_fail, 'concurrency': conc,
                     'idempotency': idem},
        legacyOrigin={'object': prog, 'events': events})
ROLLBACK = {'kind': 'ROLLBACK_ALL', 'note': '任何檢核失敗或存檔錯誤時整筆不寫入，狀態不變。'}
ONE_ROW = '單一列更新（TW_DEMO_REQHDR）；通知在交易提交後才排入。'
OP(REQ, 'CREATE', 'SAVE_NEW', '儲存新申請單', 'CREATE', {'na': '新增模式的工具列儲存，不是頁面上的元件'},
   HAS_REQUESTER,
   [{'name': 'AMOUNT', 'field': F_(HDR, 'AMOUNT'), 'required': True}, {'name': 'REASON', 'field': F_(HDR, 'REASON'), 'required': True}],
   [{'name': 'REQ_ID', 'field': F_(HDR, 'REQ_ID')}, {'name': 'REQ_STATUS', 'field': F_(HDR, 'REQ_STATUS')}],
   {'na': '新建沒有前置狀態'}, [BRr('TW_DEMO_REQHDR.AMOUNT.SaveEdit', 'AMOUNT_POSITIVE')],
   {'transitions': [T('*', '010')], 'writes': [{'field': F_(HDR, 'AMOUNT'), 'value': {'param': 'AMOUNT'}},
                                               {'field': F_(HDR, 'REASON'), 'value': {'param': 'REASON'}}]},
   'SINGLE_UNIT', '新增一列（TW_DEMO_REQHDR）。', ROLLBACK,
   {'strategy': 'NOT_APPLICABLE', 'legacyBehavior': '新單不存在併發更新；取號的併發行為見 09 的取號規則。'},
   {'repeatable': False, 'behavior': '存檔後畫面轉為修改模式，再按儲存不會建立第二張單。'},
   ['FieldDefault', 'SaveEdit', 'SavePreChange'], obj('COMPONENT', REQ), [EV_META_REQ])
OP(REQ, 'SUBMIT', 'SUBMIT', '送出申請', 'TRANSITION', [UIr(REQ, 'TW_DEMO_REQPG', WRK, 'SUBMIT_PB')], REQUESTER_ACTOR,
   [{'name': 'REQ_ID', 'field': F_(HDR, 'REQ_ID'), 'required': True},
    {'name': 'AMOUNT', 'field': F_(HDR, 'AMOUNT'), 'required': True}, {'name': 'REASON', 'field': F_(HDR, 'REASON'), 'required': True}],
   [{'name': 'REQ_STATUS', 'field': F_(HDR, 'REQ_STATUS')}], status_in('010', '015'),
   [BRr('TW_DEMO_REQWRK.SUBMIT_PB.FieldChange', 'SUPERVISOR_REQUIRED'), BRr('TW_DEMO_REQHDR.AMOUNT.SaveEdit', 'AMOUNT_POSITIVE')],
   {'transitions': [T('010', '020'), T('015', '020')],
    'writes': [{'field': F_(HDR, 'AMOUNT'), 'value': {'param': 'AMOUNT'}}, {'field': F_(HDR, 'REASON'), 'value': {'param': 'REASON'}}],
    'interfaces': [r('IF', 'AE:TW_DEMO_NTFY')]},
   'SINGLE_UNIT', ONE_ROW, ROLLBACK, CONCURRENCY,
   {'repeatable': False, 'behavior': '送出後按鈕隱藏；同一張單不能重複送出。'},
   ['FieldChange', 'SaveEdit', 'SavePostChange'], pc('TW_DEMO_REQWRK.SUBMIT_PB.FieldChange'), [EV_PC_SUBMIT, EV_PC_CONCURRENCY])
OP(REQ, 'WITHDRAW', 'WITHDRAW', '撤回申請', 'TRANSITION', [UIr(REQ, 'TW_DEMO_REQPG', WRK, 'WITHDRAW_PB')], REQUESTER_ACTOR,
   [{'name': 'REQ_ID', 'field': F_(HDR, 'REQ_ID'), 'required': True}], [{'name': 'REQ_STATUS', 'field': F_(HDR, 'REQ_STATUS')}],
   status_in('010', '015'), [BRr('TW_DEMO_REQHDR.AMOUNT.SaveEdit', 'AMOUNT_POSITIVE')],
   {'transitions': [T('010', '090'), T('015', '090')], 'writes': []},
   'SINGLE_UNIT', '單一列更新（TW_DEMO_REQHDR）。', ROLLBACK, CONCURRENCY,
   {'repeatable': False, 'behavior': '撤回後按鈕隱藏；作廢的單不能再操作。'},
   ['FieldChange', 'SaveEdit'], pc('TW_DEMO_REQWRK.WITHDRAW_PB.FieldChange'), [EV_PC_WITHDRAW, EV_PC_CONCURRENCY])
OP(APV, 'APPROVE', 'APPROVE', '核准申請', 'TRANSITION', [UIr(APV, 'TW_DEMO_APVPG', WRK, 'APPROVE_PB')],
   ANY(ALL(status_is('020'), APPROVER_020), ALL(status_is('025'), APPROVER_025)),
   [{'name': 'REQ_ID', 'field': F_(HDR, 'REQ_ID'), 'required': True},
    {'name': 'COMMENTS', 'field': F_(HDR, 'COMMENTS'), 'required': False}],
   [{'name': 'REQ_STATUS', 'field': F_(HDR, 'REQ_STATUS')}], status_in('020', '025'), [],
   {'transitions': [T('020', '030'), T('020', '025'), T('025', '030')],
    'writes': [{'field': F_(HDR, 'COMMENTS'), 'value': {'param': 'COMMENTS'}}]},
   'SINGLE_UNIT', ONE_ROW, ROLLBACK, CONCURRENCY,
   {'repeatable': False, 'behavior': '核准後按鈕隱藏；同一狀態不能重複核准。'},
   ['FieldChange', 'SaveEdit'], pc('TW_DEMO_REQWRK.APPROVE_PB.FieldChange'), [EV_PC_APPROVE, EV_PC_CONCURRENCY])
OP(APV, 'RETURN', 'RETURN', '退回申請', 'TRANSITION', [UIr(APV, 'TW_DEMO_APVPG', WRK, 'RETURN_PB')],
   ANY(ALL(status_is('020'), APPROVER_020), ALL(status_is('025'), APPROVER_025)),
   [{'name': 'REQ_ID', 'field': F_(HDR, 'REQ_ID'), 'required': True},
    {'name': 'COMMENTS', 'field': F_(HDR, 'COMMENTS'), 'required': True}],
   [{'name': 'REQ_STATUS', 'field': F_(HDR, 'REQ_STATUS')}], status_in('020', '025'),
   [BRr('TW_DEMO_REQWRK.RETURN_PB.FieldChange', 'RETURN_COMMENT_REQUIRED')],
   {'transitions': [T('020', '015'), T('025', '015')], 'writes': [{'field': F_(HDR, 'COMMENTS'), 'value': {'param': 'COMMENTS'}}]},
   'SINGLE_UNIT', ONE_ROW, ROLLBACK, CONCURRENCY,
   {'repeatable': False, 'behavior': '退回後按鈕隱藏；同一狀態不能重複退回。'},
   ['FieldChange', 'SaveEdit'], pc('TW_DEMO_REQWRK.RETURN_PB.FieldChange'), [EV_PC_RETURN, EV_PC_CONCURRENCY])

def OPr(comp, frop, op):
    return r('OP', f'{comp}:{frop}:{op}')

# ---------------- 14 testing ----------------
def D_(rec, f, v, note=None):
    d = {'field': F_(rec, f), 'value': v}
    if note:
        d['note'] = note
    return d
def TC(comp, frop, typ, code, name, covers, state, actor, data, steps, expected, verification):
    pre = {'actor': actor, 'data': data, 'synthetic': True}
    if state:
        pre['state'] = state
    add('TC', f'{comp}:{frop}:{typ}:{code}', basis='DERIVED', derivedFrom=[FRr(comp, frop)], component=comp, name=name,
        scenarioType=typ, fr=FRr(comp, frop), covers=covers, preconditions=pre,
        steps=[dict(seq=i + 1, **s) for i, s in enumerate(steps)], expected=expected, verification=verification)
BASE = [D_(HDR, 'REQUESTER_EMPLID', 'E1001'), D_(EMP, 'SUPERVISOR_ID', 'E2001', 'E1001 的目前有效任職列'),
        D_(EMP, 'DEPTID', 'D100', 'E1001 的目前有效任職列'), D_(DEPT, 'MANAGER_ID', 'E3001', 'D100 的目前有效列')]
AS_SUP = P(SUPERVISOR, 'EQ', ME)
AS_REQ = IS_REQUESTER
S = lambda c: r('STATE', f'REQ_STATUS:{c}')
APV_PB = UIr(APV, 'TW_DEMO_APVPG', WRK, 'APPROVE_PB')
RET_PB = UIr(APV, 'TW_DEMO_APVPG', WRK, 'RETURN_PB')
SUB_PB = UIr(REQ, 'TW_DEMO_REQPG', WRK, 'SUBMIT_PB')
WD_PB = UIr(REQ, 'TW_DEMO_REQPG', WRK, 'WITHDRAW_PB')
AMT_REQ = UIr(REQ, 'TW_DEMO_REQPG', HDR, 'AMOUNT')
CMT = UIr(APV, 'TW_DEMO_APVPG', HDR, 'COMMENTS')
OP_APPROVE, OP_RETURN = OPr(APV, 'APPROVE', 'APPROVE'), OPr(APV, 'RETURN', 'RETURN')
OP_SUBMIT, OP_WITHDRAW, OP_CREATE = OPr(REQ, 'SUBMIT', 'SUBMIT'), OPr(REQ, 'WITHDRAW', 'WITHDRAW'), OPr(REQ, 'CREATE', 'SAVE_NEW')

TC(APV, 'APPROVE', 'BOUNDARY', 'AMOUNT_AT_LIMIT', '金額剛好 50000 時一次核准', {'transitions': [T('020', '030')]},
   S('020'), AS_SUP, BASE + [D_(HDR, 'REQ_STATUS', '020'), D_(HDR, 'AMOUNT', '50000.00')],
   [{'action': '以 E2001 開啟該申請單並按「核准」', 'control': APV_PB, 'operation': OP_APPROVE}],
   {'resultState': S('030'), 'data': [D_(HDR, 'APPROVER_EMPLID', 'E2001'), D_(HDR, 'APPROVE_DT', '測試當日')]},
   '查該列 REQ_STATUS＝030、APPROVER_EMPLID＝E2001、APPROVE_DT＝測試當日。')
TC(APV, 'APPROVE', 'BOUNDARY', 'AMOUNT_OVER_LIMIT', '金額 50000.01 時轉部門主管', {'transitions': [T('020', '025')]},
   S('020'), AS_SUP, BASE + [D_(HDR, 'REQ_STATUS', '020'), D_(HDR, 'AMOUNT', '50000.01')],
   [{'action': '以 E2001 開啟該申請單並按「核准」', 'control': APV_PB, 'operation': OP_APPROVE}],
   {'resultState': S('025')}, '查該列 REQ_STATUS＝025；APPROVER_EMPLID 未寫入。')
TC(APV, 'APPROVE', 'NEGATIVE', 'NOT_SUPERVISOR', '具審核角色但不是直屬主管者看不到申請單',
   {'transitions': [T('020', '030')]}, S('020'),
   ALL(HAS_APPROVER, P(SUPERVISOR, 'NE', ME)), BASE + [D_(HDR, 'REQ_STATUS', '020'), D_(HDR, 'AMOUNT', '1000.00')],
   [{'action': '以 E2999（具審核角色、但不是 E1001 的直屬主管）查詢該申請單'}],
   {'noDataChange': True}, '查詢結果不含此單；該列資料不變。')
TC(APV, 'APPROVE', 'POSITIVE', 'HIGH_AMOUNT_END_TO_END', '高額案件兩段核准',
   {'flows': [r('FLOW', 'REQ_STATUS:高額審核')], 'transitions': [T('020', '025'), T('025', '030')]},
   S('020'), AS_SUP, BASE + [D_(HDR, 'REQ_STATUS', '020'), D_(HDR, 'AMOUNT', '80000.00')],
   [{'action': '以 E2001 按「核准」，狀態轉為 025', 'control': APV_PB, 'operation': OP_APPROVE},
    {'action': '以 E3001（D100 部門主管）開啟同一張單並按「核准」', 'control': APV_PB, 'operation': OP_APPROVE}],
   {'resultState': S('030'), 'data': [D_(HDR, 'APPROVER_EMPLID', 'E3001')]},
   '第一步後 REQ_STATUS＝025；第二步後 REQ_STATUS＝030、APPROVER_EMPLID＝E3001。')
TC(APV, 'RETURN', 'NEGATIVE', 'BLANK_COMMENT', '未填意見不能退回', {'rules': [BRr('TW_DEMO_REQWRK.RETURN_PB.FieldChange', 'RETURN_COMMENT_REQUIRED')]},
   S('020'), AS_SUP, BASE + [D_(HDR, 'REQ_STATUS', '020'), D_(HDR, 'COMMENTS', ' ', '單一空白，即未填')],
   [{'action': '以 E2001 不填審核意見，按「退回」', 'control': RET_PB, 'operation': OP_RETURN}],
   {'message': M(2), 'noDataChange': True}, '畫面顯示訊息 27000,2；該列 REQ_STATUS 仍為 020。')
TC(APV, 'RETURN', 'POSITIVE', 'RETURN_WITH_COMMENT', '填寫意見後退回', {'transitions': [T('020', '015')]},
   S('020'), AS_SUP, BASE + [D_(HDR, 'REQ_STATUS', '020')],
   [{'action': '以 E2001 填寫審核意見「請補附件」，按「退回」', 'control': RET_PB, 'operation': OP_RETURN,
     'inputs': [D_(HDR, 'COMMENTS', '請補附件')]}],
   {'resultState': S('015'), 'data': [D_(HDR, 'COMMENTS', '請補附件')]}, '查該列 REQ_STATUS＝015、COMMENTS＝請補附件。')
TC(REQ, 'CREATE', 'BOUNDARY', 'AMOUNT_MIN', '金額 0.01 可建立', {'rules': [BRr('TW_DEMO_REQHDR.AMOUNT.SaveEdit', 'AMOUNT_POSITIVE')]},
   'INITIAL', AS_REQ, [D_(EMP, 'SUPERVISOR_ID', 'E2001', 'E1001 的目前有效任職列')],
   [{'action': '以 E1001 在新增模式輸入金額 0.01 與事由後儲存', 'control': AMT_REQ, 'operation': OP_CREATE,
     'inputs': [D_(HDR, 'AMOUNT', '0.01'), D_(HDR, 'REASON', '測試')]}],
   {'resultState': S('010')}, '產生一列，REQ_STATUS＝010、AMOUNT＝0.01。')
TC(REQ, 'CREATE', 'NEGATIVE', 'AMOUNT_ZERO', '金額 0 不能建立', {'rules': [BRr('TW_DEMO_REQHDR.AMOUNT.SaveEdit', 'AMOUNT_POSITIVE')]},
   'INITIAL', AS_REQ, [D_(EMP, 'SUPERVISOR_ID', 'E2001', 'E1001 的目前有效任職列')],
   [{'action': '以 E1001 在新增模式輸入金額 0 與事由後儲存', 'control': AMT_REQ, 'operation': OP_CREATE,
     'inputs': [D_(HDR, 'AMOUNT', '0'), D_(HDR, 'REASON', '測試')]}],
   {'message': M(1), 'noDataChange': True}, '畫面顯示訊息 27000,1；沒有新增任何列。')
TC(REQ, 'CREATE', 'POSITIVE', 'CREATE_DRAFT', '建立草稿', {'transitions': [T('*', '010')],
   'rules': [BRr('TW_DEMO_REQ.SavePreChange', 'ASSIGN_REQ_ID'), BRr('TW_DEMO_REQHDR.REQUESTER_EMPLID.FieldDefault', 'REQUESTER_DEFAULT')]},
   'INITIAL', AS_REQ, [D_(EMP, 'SUPERVISOR_ID', 'E2001', 'E1001 的目前有效任職列')],
   [{'action': '以 E1001 在新增模式輸入金額 1000 與事由後儲存', 'operation': OP_CREATE,
     'inputs': [D_(HDR, 'AMOUNT', '1000'), D_(HDR, 'REASON', '測試')]}],
   {'resultState': S('010'), 'data': [D_(HDR, 'REQUESTER_EMPLID', 'E1001'), D_(HDR, 'REQ_ID', '10 碼數字（不是 NEW）')]},
   '產生一列，REQ_STATUS＝010、REQUESTER_EMPLID＝E1001、REQ_ID 為 10 碼數字。')
TC(REQ, 'CREATE', 'POSITIVE', 'MAIN_FLOW_END_TO_END', '主流程：建立、送出、核准',
   {'flows': [r('FLOW', 'REQ_STATUS:主流程')], 'transitions': [T('*', '010'), T('010', '020'), T('020', '030')]},
   'INITIAL', AS_REQ, BASE[1:],
   [{'action': '以 E1001 建立金額 1000 的申請單', 'operation': OP_CREATE, 'inputs': [D_(HDR, 'AMOUNT', '1000'), D_(HDR, 'REASON', '測試')]},
    {'action': '以 E1001 按「送出」', 'control': SUB_PB, 'operation': OP_SUBMIT},
    {'action': '以 E2001 開啟該單並按「核准」', 'control': APV_PB, 'operation': OP_APPROVE}],
   {'resultState': S('030'), 'data': [D_(HDR, 'APPROVER_EMPLID', 'E2001')]}, '各步驟後 REQ_STATUS 依序為 010、020、030。')
TC(REQ, 'SUBMIT', 'NEGATIVE', 'NO_SUPERVISOR', '沒有直屬主管不能送出',
   {'rules': [BRr('TW_DEMO_REQWRK.SUBMIT_PB.FieldChange', 'SUPERVISOR_REQUIRED')]}, S('010'), AS_REQ,
   [D_(HDR, 'REQUESTER_EMPLID', 'E1001'), D_(HDR, 'REQ_STATUS', '010'), D_(EMP, 'SUPERVISOR_ID', ' ', 'E1001 的目前有效任職列為單一空白')],
   [{'action': '以 E1001 按「送出」', 'control': SUB_PB, 'operation': OP_SUBMIT}],
   {'message': M(3), 'noDataChange': True}, '畫面顯示訊息 27000,3；該列 REQ_STATUS 仍為 010。')
TC(REQ, 'SUBMIT', 'POSITIVE', 'RESUBMIT_AFTER_RETURN', '退回後補件重新送出',
   {'flows': [r('FLOW', 'REQ_STATUS:退回補件')], 'transitions': [T('020', '015'), T('015', '020')]}, S('020'), AS_SUP,
   BASE + [D_(HDR, 'REQ_STATUS', '020')],
   [{'action': '以 E2001 填寫意見後按「退回」', 'control': RET_PB, 'operation': OP_RETURN, 'inputs': [D_(HDR, 'COMMENTS', '請補附件')]},
    {'action': '以 E1001 修改事由後按「送出」', 'control': SUB_PB, 'operation': OP_SUBMIT}],
   {'resultState': S('020'), 'data': [D_(HDR, 'SUBMIT_DT', '測試當日')]}, '第一步後 REQ_STATUS＝015；第二步後 020，SUBMIT_DT 更新。')
TC(REQ, 'SUBMIT', 'POSITIVE', 'SUBMIT_FROM_DRAFT', '草稿送出', {'transitions': [T('010', '020')],
   'rules': [BRr('TW_DEMO_REQ.SavePostChange', 'NOTIFY_SUPERVISOR')]}, S('010'), AS_REQ,
   BASE + [D_(HDR, 'REQ_STATUS', '010'), D_(HDR, 'AMOUNT', '1000.00')],
   [{'action': '以 E1001 按「送出」', 'control': SUB_PB, 'operation': OP_SUBMIT}],
   {'resultState': S('020'), 'data': [D_(HDR, 'SUBMIT_DT', '測試當日')]},
   '查該列 REQ_STATUS＝020、SUBMIT_DT＝測試當日；送審通知程序已排入一筆。')
TC(REQ, 'WITHDRAW', 'POSITIVE', 'WITHDRAW_DRAFT', '撤回草稿',
   {'flows': [r('FLOW', 'REQ_STATUS:撤回作廢')], 'transitions': [T('010', '090')]}, S('010'), AS_REQ,
   [D_(HDR, 'REQUESTER_EMPLID', 'E1001'), D_(HDR, 'REQ_STATUS', '010'), D_(HDR, 'AMOUNT', '1000.00')],
   [{'action': '以 E1001 按「撤回」', 'control': WD_PB, 'operation': OP_WITHDRAW}],
   {'resultState': S('090')}, '查該列 REQ_STATUS＝090；畫面不再顯示送出與撤回按鈕。')

# ---------------- 16 AI instructions ----------------
AI_CLAUSES = [
    ('READING', '先讀 00-index：閱讀順序、ID 前綴對照、本版狀態。看到任何 ID，到前綴對照表指定的文件找定義；以 ID 為準，不以章節位置為準。'),
    ('SCOPE', '只實作 01～19 本體列出的項目。90 問題清單中的圖外狀態與圖外轉移不實作，除非 19 有決策把它納入。'),
    ('DATA', '07「不建置的原生欄位」所列欄位不建資料欄、不上畫面、不寫規則。DEPENDENCY 實體只建文件列出的欄位（最小介面）。'),
    ('DATA', '狀態碼、選項儲存值、訊息原文一律保留原值；畫面文字可以調整，但不得更改儲存值。'),
    ('LOGIC', '條件的空白語意照共同定義實作：字元欄空白＝NULL 或單一空白；數值欄未輸入視為 0；日期欄未輸入為 NULL。'),
    ('UNKNOWN_HANDLING', '遇到 UNRESOLVED 或文件沒有說明的行為，不要自行補上；記下 ID 與問題回報，等待 19 的決策。'),
    ('UNKNOWN_HANDLING', 'NOT_APPLICABLE 表示已查證「沒有」，不要補做；它不是待辦。'),
    ('SCOPE', '文件不指定技術。不要把原系統的 Component、Page、Record 結構當成必須照搬的架構；要保留的是可觀測行為與資料語意。'),
    ('TRACEABILITY', '在程式、測試與提交訊息標註實作的 ID（FR、BR、TC…），讓驗收能逐項對照 18 的完成條件。'),
    ('CHANGE_DISCIPLINE', '發現規格矛盾或錯誤時不要自行修改規格；回報 ID 與證據，由 19 的決策處理後再實作。'),
]
for i, (cat, clause) in enumerate(AI_CLAUSES):
    add('AI', f'AI:{i + 1:02d}', basis='TEMPLATE', category=cat, clause=clause)

# ---------------- 90 questions ----------------
add('Q', 'OFF_DIAGRAM_STATE:REQ_STATUS:099', basis='COMPUTED', evidence=[EV_SQL_STATUS], category='OFF_DIAGRAM_STATE',
    severity='INFO', grade='HIGH', question='PROD 有 REQ_STATUS＝099 的資料，但狀態圖沒有這個狀態。是歷史資料（只需資料移轉對應），還是狀態圖漏畫？',
    affects=[F_(HDR, 'REQ_STATUS')], observed={'entityKey': 'REQ_STATUS', 'code': '099'}, raisedBy='RESEARCH',
    status='OPEN')
add('Q', 'OFF_DIAGRAM_TRANSITION:REQ_STATUS:030>010', basis='COMPUTED', evidence=[EV_PC_POSTBUILD],
    category='OFF_DIAGRAM_TRANSITION', severity='INFO', grade='LOW',
    question='TW_DEMO_APV.PostBuild 在特殊參數下會把 030 改回 010（核准後重開），狀態圖沒有這條轉移。要不要重建？',
    affects=[pc('TW_DEMO_APV.PostBuild')],
    observed={'entityKey': 'REQ_STATUS', 'from': '030', 'to': '010', 'location': 'TW_DEMO_APV.PostBuild'},
    raisedBy='RESEARCH', status='ANSWERED', proposedAnswer='看起來是管理者的資料維護入口，不是業務流程。')
add('Q', 'READER_UNDERSPECIFIED:TW_DEMO_APV:APPROVE:APPROVE#concurrency', basis='COMPUTED', category='READER_UNDERSPECIFIED',
    severity='BLOCKING', question='兩位審核者同時核准同一張單時，後存檔者看到什麼、資料變成怎樣，文件沒有說明（原文只寫「原系統有檢查」）。',
    affects=[OPr(APV, 'APPROVE', 'APPROVE')], raisedBy='READER', status='WITHDRAWN')

SUPPRESSED = {'definitionOnlyCount': 2, 'definitionOnlyCodes': [{'entityKey': 'REQ_STATUS', 'code': '040'},
                                                               {'entityKey': 'REQ_STATUS', 'code': '050'}]}

# ---------------- ID assignment ----------------
IDMAP = {}
for prefix in g.PREFIX_INFO:
    for i, it in enumerate(sorted(ITEMS.get(prefix, []), key=lambda x: x['key'])):
        IDMAP[(prefix, it['key'])] = f'{prefix}-{i + 1:03d}'
        it['id'] = IDMAP[(prefix, it['key'])]

PAT = re.compile(r'@@([A-Z]+)\|(.+?)@@')
def resolve(o):
    if isinstance(o, dict):
        return {k: resolve(v) for k, v in o.items()}
    if isinstance(o, list):
        return [resolve(v) for v in o]
    if isinstance(o, str):
        m = PAT.fullmatch(o)
        if m:
            k = (m.group(1), m.group(2))
            if k not in IDMAP:
                raise KeyError(f'unresolved symbolic ref {k}')
            return IDMAP[k]
        if '@@' in o:
            raise ValueError('embedded ref in text: ' + o)
    return o

def ordered(it, prefix):
    """id/key/base fields first for readability."""
    head = ['id', 'key', 'lifecycle', 'component', 'basis', 'certainty', 'inference', 'evidence', 'derivedFrom']
    out = {k: it[k] for k in head if k in it}
    for f in g.ITEM_TYPES[prefix]['fields']:
        if f.name in it:
            out[f.name] = it[f.name]
    extra = [k for k in it if k not in out]
    if extra:
        raise ValueError(f'{prefix} {it["key"]} unknown fields {extra}')
    return out

def build():
    for prefix in ITEMS:
        ITEMS[prefix] = [resolve(ordered(it, prefix)) for it in sorted(ITEMS[prefix], key=lambda x: x['key'])]
    return ITEMS

# DEC needs Q id -> created after assignment
def add_dec():
    qid = IDMAP[('Q', 'OFF_DIAGRAM_TRANSITION:REQ_STATUS:030>010')]
    md = X.decisions_md(qid)
    n = X.line_of(md, qid)
    e = ev('HUMAN_DECISION', f'decisions.md#L{n}', md.split('\n')[n - 1])
    it = {'id': 'DEC-001', 'key': 'DEC:0001', 'lifecycle': 'ACTIVE', 'basis': 'HUMAN_DECISION', 'certainty': 'CONFIRMED',
          'evidence': [e], 'title': '不重建「核准後重開為草稿」', 'context': f'{qid}：TW_DEMO_APV.PostBuild 有一段狀態圖外的 030→010 邏輯。',
          'options': [{'option': '不重建', 'consequence': '新系統沒有重開功能；需要時以資料維護處理。'},
                      {'option': '補進 STATUS 文件並重建', 'consequence': '狀態圖新增 030→010，04、02、08、14 要補對應項目。'}],
          'decision': '不重建。', 'rationale': '這是管理者以特殊參數做的資料維護，不是業務流程；STATUS 文件不納入。',
          'decidedBy': '業務單位主管', 'decidedOn': '2026-10-08', 'status': 'ACCEPTED', 'resolves': [qid],
          'affects': [IDMAP[('OBJ', 'PEOPLECODE:TW_DEMO_APV.PostBuild')]], 'effect': 'DROP'}
    ITEMS['DEC'] = [it]
    return md

if __name__ == '__main__':
    build()
    add_dec()
    print({p: len(v) for p, v in ITEMS.items()})
