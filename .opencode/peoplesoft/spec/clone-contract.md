# 核心功能重建 Spec 契約

## 目標與範圍

讀者是看不到原 PeopleSoft 程式、但能用現代語言與架構開發的獨立 LLM。它應可由本文件實作指定 Component 的可觀測核心行為，並以保留的原始識別字回查 PeopleSoft。描述行為契約，不替使用者選框架，不要求照搬 Component Processor。

1. 使用者指定的 Component 是根。先以 metadata 確認真實 Component、Page／Subpage／Scroll／Record 關係與可執行入口，不以名稱相似、同表出現或域內共存當作核心。
2. scope 每筆明確分類 CORE／DEPENDENCY／EXCLUDED：實際入口與功能路徑是 CORE；被這條路徑真正呼叫、讀寫、查值或授權所需的最小依賴是 DEPENDENCY；只原生有關聯、未使用、其他功能分支則 EXCLUDED。delivered／custom 本身不決定分類。
3. 必須沿可證明的呼叫／資料／權限鏈追到足夠實作；不能把一跳限制誤當功能邊界，也不能無限制掃整個 PeopleSoft。每次只派工單相關一段，仍未查完就續頁或列缺口。
4. 必需的 PeopleSoft 原生依賴寫成最小替代介面：輸入、輸出、lookup／驗證規則、錯誤與副作用；不把它的其他頁面、管理功能、未走分支一併移植。保留短排除表與理由，不在正文展開排除物件。
5. 多個 Component 各有自己的完整章節。若共享交易、狀態或依賴，明示關係與差異；不能用「同上」取代另一個 Component 的必要條件，也不能自行增加未指定的核心 Component。

## 必備深度

每個 topic 的固定欄位以 clone-profile.json 為準。欄位值可以多行，但單筆不得把多個不同條件壓成模糊摘要。

- scope：根身分、核心操作、使用鏈、相依介面、明確排除與未知邊界。
- flows：角色、入口與模式、前置條件、順序、分支判斷、成功結果、失敗路徑；每個判斷用原始 Record.Field／參數與值表示。
- ui：搜尋與新增／修改模式、Page／Subpage／Scroll level、控制項、原始 Record.Field、顯示 label、型別／長度、預設值來源、必填／可見／可編輯的精確條件、選項 label↔stored value、Prompt／Translate 來源、觸發事件與畫面刷新。
- data：logical／physical key、型別／長度／精度／nullable、預設、關聯與基數、讀寫欄位、有效日期／序號、來源與用途。共用 Record 只保留被核心實際使用的欄位及必要 key，不複製整個共用 schema。
- rules：來源事件／位置、執行順序、精確欄位條件式與 stored value、AND／OR 與優先序、null／空白／0／日期邊界、成功與失敗結果、原始訊息、例外與資料副作用。不可只寫「依狀態判斷」「檢查有效性」。
- states：狀態欄位與所有相關 stored values、起始狀態、from→event→guard→to、寫入時點、副作用、非法轉移／復原；條件 UI 不是資料狀態機，兩者分開。如果確實無持久化狀態機，依證據說明，不自行創造。
- transactions：讀寫順序、Record.Field assignment、交易邊界、commit／rollback、鎖／競爭、重送／冪等、重試、刪除與稽核欄位、錯誤後殘留狀態。未知 runtime 行為明列待驗，不由框架常識推定。
- interfaces：只有核心實際用到的 AE／SQR／SQL／檔案／服務／排程；觸發條件、參數／Run Control、欄位順序／長度／格式／編碼／空值、回傳／拒絕格式、重送／錯誤與副作用。
- security：實際進入與操作的授權條件、Permission List／Role／row-level data scope；區分配置可見與當前使用者已授權，不宣稱有導覽入口就一定可用。
- acceptance：按主要流程、規則分支、狀態轉移及資料副作用逐項列正向／反向／邊界測例；給具體輸入欄位與值、前置資料、動作、預期畫面／資料變動／原始錯誤，讓重建者可實作測試；合成測資明標，不冒充公司真實資料。

實作所需內容不能只寫「見 NN」「依 PeopleSoft 標準」「同另一頁」；trace 可指來源，Spec 本文必須自足。

## 研究與證據

- 先用知識索引定位既有 NN／wiki，只讀 topic 相關節；索引是入口不是原始碼正確性的保證。知識不存在時可直接針對確切 Component 委派，不要求先研究整個領域。
- UI／layout 派 ps-ui-flow；欄位驅動條件派 ps-peoplecode-flow；metadata／資料／授權派 ps-metadata-flow；AE、SQR、SQL 分別派對應 flow。metadata 類先 connect；ps-security-flow 等是 skill，不是 agent。
- 關鍵條件、UI 動態變異、assignment、狀態與交易需原始來源；至少追 Activate／PostBuild／FieldChange／FieldEdit／SaveEdit／SavePreChange／SavePostChange 等實際相關事件，不能因 NN 沒提到就推論不存在。不要要求每個事件一定存在，查無也須查法收據。
- CHUNK locator 是完整 UUID，且必須已透過 PeoplecodeSource 取回精確段落；SQL locator 是已執行的 SELECT 查詢，必須保留 FROM 及限定目標，excerpt 記關鍵回傳列；NN locator 是本機研究檔與明確行段，excerpt 是實際內容。單筆 excerpt ≤5 行。
- evidence 的 ID 僅在該 packet 內使用；每筆 item 的 evidenceIds 都要可解析。NN 可作來源路標／已記錄事實，獨立覆核仍須追到決策性原始證據，不因 NN 標 AUDITED_CLEAN 就跳過。
- 不把搜尋結果、候選 ChunkId、查詢失敗、空結果或「沒在 NN 寫」當成不存在的證明。矛盾、工具中斷、無法觀察動態值、權限不足都進 gaps。

## packet.json

頂層：`schemaVersion:1`、`component`、`topic`、`coverage`、`summary`、`items`、`evidence`、`gaps`、`nextCursor`。

- coverage 僅 COMPLETE／PARTIAL／NOT_APPLICABLE。COMPLETE 是本 topic 已列完整，不是本頁剛好寫完；所有必要內容有證據且 gaps 空、nextCursor 空才可用。
- PARTIAL：有未查清的事實或還有下一頁。純續頁、沒有未知事實時 gaps 必須是空陣列，nextCursor 用可重定位的範圍／物件／事件表示尚待列舉的部分，不用「繼續」。非空 gaps 代表知識缺口，寫明缺少的欄位／條件／分支與原因；此頁只能當草稿，須補齊證據後重試本頁，不可藉後頁 COMPLETE 清除它。一頁最多 40 items，不能為塞入上限而刪掉條件或例外。
- NOT_APPLICABLE：只有 profile 明示允許時可用，而且只能是該 topic 第一頁；items 空、nextCursor 空，summary 給明確不適用理由且 evidence 非空。已有其他頁列出行為就不能在續頁把整個 topic 宣稱不適用。無證據、未查完、工具故障不是不適用。
- item：`id`（穩定 ASCII ID，同 topic 各頁不重複）、`scopeRefs`、`values`（本 topic fields 每個 key 都必填字串）、`evidenceIds`。
- acceptance 宣稱 COMPLETE 前，整個 topic 累積必須含 POSITIVE、NEGATIVE、BOUNDARY 三類情境，且覆蓋已列主要規則；三種各一筆只是最低結構條件，不是充分完整性證明。
- scope 的 item.values 用 object／type／inclusion／usedBy／condition／reason。其他 topic 的 scopeRefs 只准引用已核定 scope 中 CORE 或 DEPENDENCY 的 ID；EXCLUDED 不能出現在功能正文。
- evidence：`id`、`kind`（CHUNK／SQL／NN）、`locator`、`excerpt`。不得自己編造來源或把多頁不同證據混用同一 ID。
- 文字值缺料就 PARTIAL，不把 `UNKNOWN`／`TODO`／`UNRESOLVED` 換成模糊中文來規避缺口。`NOT_APPLICABLE` 欄位需附具體理由與證據，不能拿來填滿未查欄位。

## review.json：另一個獨立 session 覆核

先讀本次 packet、inputHash、核定 scope 與已有各段路徑；不要沿用寫作者的自評。工單 components 是本次完整清單，acceptedPacketPaths 含所有 Component 已接受內容，scopeItems 只屬於當前 Component。用定向 subagent 重取關鍵原始來源，逐筆核對可追溯性、未使用功能污染、欄位條件、例外、狀態／資料／畫面一致性，以及是否漏列。

特別檢查：UI／規則／狀態是否只出現少量範例卻宣稱 COMPLETE；所有被使用的 Page／Scroll／欄位／事件是否有處置；接受條件是否覆蓋條件分支與拒絕路徑；多頁是否重複、跳號、遺失例外；其他已完成 topic 的識別字與 stored values 是否矛盾。來源不夠判斷完整性就 BLOCKED，不能只看 JSON 能解析就 PASS。

多 Component 的 acceptance 覆核還須查所有已接受的相關技術章節，核對共享 Record.Field、狀態值、交易與介面契約。差異須有具體模式／條件解釋；無法解釋就報 TOPIC／CONTRADICTION，不能因每份各自格式正確就 PASS。已接受章節有錯且本頁不能修復時明列受影響章節，請求重新查證，不在本頁藏一個不同答案。

頂層：`schemaVersion:1`、`component`、`topic`、`inputHash`（照工單）、`verdict:PASS|FAIL|BLOCKED`、`checkedIds`、`findings`、`summary`。

- checkedIds 是確實逐筆核對的 item ID。PASS 必須正好覆蓋 packet 全部 item、findings 空，且完成上述 topic 完整性檢查；N/A 也要驗排除證據。
- findings 每筆 `{itemId,code,detail}`；code 使用 `MISSING_DETAIL`／`MISSING_BRANCH`／`EVIDENCE_MISMATCH`／`SCOPE_NOISE`／`CONTRADICTION`／`LANGUAGE`／`TOOL_BLOCKED`。detail 用繁中指出可修的具體差異；topic 層缺漏用 itemId `TOPIC`。
- PASS 不代表企業實跑或重建等價驗證已完成；未解問題不能靠 review 宣言清零。
