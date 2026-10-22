# PeopleSoft 畫面元件代碼確認：工作報告（2026-10-14～10-21）

## 摘要

- **目的**：讓 AI 寫的研究文件（NN）與重建用的 Spec，能正確說出畫面上每個欄位「是什麼元件、唯讀還是可改、必不必填、
  輸入值去哪裡查、相關顯示對應哪個代碼欄、這個 Component 能不能新增或更正」。
- **難點**：這些設定在 PeopleTools 的表裡全是**數字代碼**，很多還是好幾個勾選加總成一個數字；公開文件沒有完整對照，
  網路上只有零散、年代久遠、多半互相轉抄的社群整理，有些代碼各家寫法不一。每個代碼都要在公司環境實際確認，確認過的才能讓 AI 拿來翻譯。
- **做法**：分 **7 輪**、寫了 **39 段 SQL**（驗證、授權檢查、App Designer 對照用，含沒用上的備案）。SQL 盡量設計成自己判斷對錯，
  回報時每段一行、只有代碼與數字，不帶任何公司資料；需要時再到 App Designer 拿已知的頁面、欄位、Component 逐一核對。
- **結果**：頁面元件 22 種代碼、元件屬性 4 個位元、Record 欄位設定 10 個位元、Component 動作 4 個位元、相關顯示的對應規則全部定案，
  寫進框架的 2 段正式查詢，研究文件新增「## 畫面元件」一節。過程中推翻或修正了 4 個判斷，第 7 輪才定案。

---

## 1. 為什麼要做

研究文件原本只知道欄位的資料型別（字元、數字、日期），寫不出畫面長什麼樣子、哪些欄位不能改、哪些必填、下拉選單的值從哪裡來。
拿這樣的文件去重建功能，畫面與檢核規則會缺一大塊。

這些資訊都存在 PeopleTools 的定義表裡（頁面欄位表、Record 欄位表、Component 定義表），但存的是數字：

| 想知道的事 | 存在哪裡 | 怎麼存 |
|---|---|---|
| 這個欄位是什麼元件（輸入框、下拉選單、按鈕、Grid…） | 頁面欄位表的元件代碼 | 一個數字（0～32 之間），公開文件查不到對照 |
| 唯讀、隱藏、是不是相關顯示 | 頁面欄位表的使用旗標 | 多個勾選**加總**成一個數字 |
| 相關顯示（代碼旁的說明欄）對應哪個代碼欄 | 頁面欄位表的關聯欄號 | 一個編號，起算方式沒有文件 |
| 鍵、必填、Translate 檢核、Y/N、Prompt 檢核、自動押時間 | Record 欄位表的設定旗標 | 多個勾選加總成一個數字 |
| Component 能新增、修改、看歷史、更正 | Component 定義表的動作旗標 | 多個勾選加總成一個數字 |

只要有一個代碼翻錯，AI 就會很有自信地寫錯（例如把唯讀欄位寫成可改），而且讀的人很難發現。所以先確認、再使用。

---

## 2. 難在哪裡

1. **公開文件沒有完整的對照表**。Oracle 只在 PeopleCode API 的 Query 類別（Flag 屬性）列了 Record 欄位設定的位元，名稱還和 App Designer 不同；
   頁面元件代碼、使用旗標、關聯欄號、Component 動作的數值，公開文件都查不到（Component 動作另有需要登入的 Oracle Support 文件；
   相關顯示 Oracle 只用文字說明怎麼設定）。社群整理以 2008～2012 年的部落格為主、後來多半互相轉抄：元件代碼的名稱與缺漏各版不一
   （例如代碼 18 有人寫次頁、有人寫次頁按鈕），使用旗標只有一份完整整理，關聯欄號幾乎沒人寫——只能當線索。
2. **一個數字裡藏好幾個勾選**。例如使用旗標 17＝唯讀（1）＋相關顯示（16）。要先猜出每個位元的意思，再設計能把它們分開驗證的查法。
3. **假設會錯，而且錯得很像對**。這次推翻或修正了 4 個判斷：
   - 位元 16 一開始看起來像「唯讀」，拿已知欄位核對才發現唯讀是 1，16 是「相關顯示」。
   - 相關顯示的關聯欄號，先後比過 6 種對應：控制欄的 tab order 等於關聯欄號、等於關聯欄號＋1、等於關聯欄號−1、相關顯示的前一個欄位、
     控制欄的 Field ID 等於關聯欄號、等於關聯欄號＋1。第四輪其實已經一起算了正確的「tab order＝關聯欄號＋1」，但結果靠人工抄回來，
     對照第六輪重算，最可能是少抄一行、標籤錯位，看起來變成「tab order＝關聯欄號」成立；第五輪又懷疑是 Field ID。第六輪重算才確定這兩種都不對，
     第七輪由公司機的 Claude 用更強的依據比對並抽查實例，才定案是「tab order＝關聯欄號＋1」（從 0 起算）。
   - 第三到第六輪用「關聯欄號大於 0」挑相關顯示，漏掉了指到第 1 個欄位的那批（它們的關聯欄號剛好是 0）；第七輪改看位元 16。
   - 「控制欄」的位元第三輪沒找到，框架先改用反查關聯欄號判斷；第七輪才確認位元 8 就是控制欄。

---

## 3. 七輪驗證的經過

| 輪次 | 日期 | 重點 | 結果 |
|---|---|---|---|
| 第一輪 | 10-14～10-19 | 環境前提、資料型別、Record 欄位設定位元、元件代碼 0～11 | 版本 8.59；Record 欄位設定位元成立；元件代碼 0～11 成立；第一版太慢改輕量版 |
| 第二輪 | 10-19 | 頁面欄位表有哪些欄、找一個頁面到 App Designer 核對 | 找到關聯欄號與按鈕目標欄；Grid 確認 |
| 第三輪 | 10-19 | 其餘元件代碼依特徵判斷、唯讀位元、必填旁證、唯讀帳號測試 | 6 種按鈕／版面代碼成立；4 種判不出；唯讀帳號查不到 → 框架改寫表名 |
| 第四輪 | 10-20 | 改用唯讀帳號；拿 App Designer 已知欄位核對必填、唯讀、隱藏、Component 動作 | 必填、唯讀、隱藏、Component 動作確認；框架加入「畫面元件」查詢 |
| （對照） | 10-20 | 與 Oracle 文件、社群整理比對 | Record 欄位設定與官方一致；4 個元件代碼第三輪判不出、無法印證社群說法；位元 8 和當時的結果對不上 |
| 第五輪 | 10-21 | 4 個不一致的代碼拿到 App Designer 看 | 4 個都確認（捲軸、外部連結按鈕、分隔線、Grid 分頁） |
| 第六輪 | 10-21 | 相關顯示的對應：tab order 或 Field ID | 兩種都不對；發現關聯欄號為 0 的一批 |
| 第七輪 | 10-21 | 「從 0 起算」的假設；交給公司內可查 DB 的 Claude 抽查 | 確認：控制欄 tab order＝關聯欄號＋1；位元 8＝控制欄 |

---

## 4. 下了哪些 SQL、各自的用途

> SQL 名稱前的字母是輪次（V＝第一輪，R2～R7＝第二到第七輪）。每段的原文與「怎麼看」都在 repo 的 `docs/design/ui-metadata-check-r1.md`～`r7.md`。

### 第一輪：先確認環境，再驗最基本的代碼

| SQL | 用途 | 對盤點的幫助 |
|---|---|---|
| V0（2 段） | 設定 schema、確認擁有者 | 讓後面的查詢找得到表 |
| V1 | 確認 AI 要用的定義表都看得到 | 排除權限問題，免得結果是空的被誤判 |
| V2 | 查 PeopleTools 版本 | 代碼可能隨版本不同，結論要標版本（8.59） |
| V3、V3b、V3c（共 4 段） | 確認後面要用的欄位都存在、找相關欄位的候選欄名 | 免得查詢在公司環境報錯；找出「關聯欄號」等候選欄 |
| V4a～V4d（4 段） | 欄位資料型別、Record 種類的代碼：拿已知欄位與 Record 比 | 確認字元／數字／日期、實體表／Derived 的代碼，Prompt 表種類要用到 |
| V5 | Record 欄位設定 10 個位元：用旁證自我核對（例：有 Prompt 檢核的欄位一定有 Prompt 表、Y/N 欄位一定是 1 碼） | 確認鍵、Translate、Y/N、Prompt 檢核、自動押時間等位元的意思 |
| V6 | 元件代碼 0～11：用特徵自我核對（例：核取方塊綁 1 碼欄位、子頁面有子頁名）；列出其他待確認的代碼 | 確認輸入框、下拉選單、核取方塊、選項按鈕、子頁面等；第一版在 PROD 太慢，改成只看客製頁面 |
| G1 | 代碼 2 是不是 Group Box：看框裡有沒有其他元件 | V6 的判斷條件對 Group Box 不準，改用形狀確認 |
| V7 | Prompt 的種類分布（view、有效日期、SetID） | 了解查值邏輯多半在 view 裡，決定研究要怎麼追 |
| 權限（3 段） | 給 AI 唯讀帳號的授權清單、授權後的檢查、同義字備案 | 讓 AI 自己能查這些表 |

### 第二輪：找到關鍵欄位、開始用 App Designer 核對

| SQL | 用途 | 對盤點的幫助 |
|---|---|---|
| R2A | 頁面欄位表有沒有「顯示控制」「關聯欄號」「按鈕目標」這類欄（一串 Y／N） | 找到關聯欄號與 7 個按鈕目標欄，之後判斷相關顯示與連結都靠它們 |
| R2B | 找一個有待確認代碼的客製頁面 | 讓管理者拿到 App Designer 逐一對照 |
| R2C | 列出那一頁的元件，對 App Designer 的類型 | 確認 Grid 的代碼 |

### 第三輪：依特徵判斷其餘代碼

| SQL | 用途 | 對盤點的幫助 |
|---|---|---|
| R3A | 其餘元件代碼：看有沒有子頁名、轉頁目標、綁欄位、長字元、框內有沒有元件 | 確認 3 種按鈕、次頁、HTML 區、捲動區；另 4 種判不出，留給第五輪 |
| R3B | 從相關顯示共有的位元找「唯讀」與「控制欄」的位元 | 找到 16（後來證明是相關顯示的旗標，不是唯讀） |
| R3C | 鍵欄位會不會自動算必填 | 證明不會，必填要另外核對 |
| 唯讀帳號測試 | AI 的唯讀帳號查不查得到 | 查不到 → 框架全面改寫表名（61 段樣板） |

### 第四輪：改用唯讀帳號，拿已知物件核對

| SQL | 用途 | 對盤點的幫助 |
|---|---|---|
| R4A | 相關顯示指到哪一欄：同時比 4 種對應 | 當時選出一種（後來第六、七輪修正） |
| R4B | 必填位元：拿 App Designer 勾了／沒勾 Required 的欄位比 | 確認 256＝必填 |
| R4C | 唯讀、隱藏位元：拿 App Designer 勾了 Display Only／Invisible 的欄位比 | 確認 1＝唯讀、2＝隱藏，並推翻「16＝唯讀」 |
| R4D（2 段） | Component 動作：拿已知 Component 比 | 確認 Add／Update/Display／Update/Display All／Correction 四個位元 |
| R4E | 唯讀帳號還缺哪些表的權限（32 張） | 確認 AI 用得到的表全部有權限 |

### 第五輪：第三輪判不出、無法印證社群說法的代碼

| SQL | 用途 | 對盤點的幫助 |
|---|---|---|
| R5A | 4 個代碼的特徵，加一個樣本頁讓管理者在 App Designer 找到那個元件 | 確認舊式捲軸、外部連結按鈕、分隔線、Grid 分頁 |
| R5B | 位元 8 是不是「控制欄」 | 和當時的相關顯示對應對不上 → 發現對應有問題 |

### 第六、七輪：把相關顯示的對應找出來

| SQL | 用途 | 對盤點的幫助 |
|---|---|---|
| R6 | 同時比「tab order」與「Field ID」兩種對應 | 兩種都不對；發現關聯欄號為 0 的相關顯示 |
| R6B | App Designer 對一個例子（備用） | — |
| R7 | 同時比「tab order＋1」與「Field ID＋1」 | 備案；最後改用依據更強的 R7K |
| R7B | App Designer 對一個例子（備用） | — |
| R7K | 用更強的依據比 5 種對應：真正的控制欄，欄位名通常是相關顯示那張表的鍵，而且帶控制欄位元 | 公司內的 Claude 跑完再抽查實例：**控制欄 tab order＝關聯欄號＋1、位元 8＝控制欄**，定案 |

### 正式查詢（框架在用，研究時每個頁面跑一次）

| SQL | 用途 |
|---|---|
| 畫面元件查詢（查詢手冊 §2l） | 一個頁面一次：每個元件的種類、唯讀／隱藏、相關顯示與控制欄、鍵、必填、Translate／Y/N、Prompt 表與檢核方式、轉頁目標、子頁面；解碼全在 SQL 裡 |
| Component 動作查詢（查詢手冊 §2m） | 一個 Component 一次：允許的動作、搜尋用的 Record |

---

## 5. 盤點成果：代碼一覽

> 只列「代碼＝什麼」與「怎麼確認的」，不列公司系統裡各有幾個。「位元」的意思是：一個欄位同時有好幾個勾選時，存的是各勾選代表數字的和，
> 例如使用旗標 17＝1（唯讀）＋16（相關顯示）。表名、欄位名是 PeopleTools 的產品名稱。

### 5.1 頁面元件代碼（PSPNLFIELD.FIELDTYPE）——22 種

| 代碼 | 元件（App Designer 名稱） | 中文說明 | 研究文件 | 怎麼確認的 |
|---|---|---|---|---|
| 0 | Static Text | 靜態文字 | 不列（版面） | 第一輪 V6 |
| 1 | Frame | 框 | 不列（版面） | 第一輪 V6 |
| 2 | Group Box | 群組框 | 不列（版面） | 第一輪 G1 |
| 3 | Static Image | 靜態圖 | 不列（版面） | 第一輪 V6 |
| 4 | Edit Box | 輸入框 | 列出 | 第一輪 V6 |
| 5 | Drop-Down List Box | 下拉選單 | 列出 | 第一輪 V6 |
| 6 | Long Edit Box | 長文字框 | 列出 | 第一輪 V6 |
| 7 | Check Box | 核取方塊 | 列出 | 第一輪 V6 |
| 8 | Radio Button | 選項按鈕 | 列出 | 第一輪 V6 |
| 9 | Image | 圖片（綁欄位） | 列出 | 第一輪 V6 |
| 10 | Scroll Bar | 舊式的層級捲軸 | 列出 | 第五輪 R5A＋App Designer |
| 11 | Subpage | 子頁面（再展開裡面的元件） | 列出 | 第一輪 V6 |
| 12 | Push Button/Hyperlink：PeopleCode Command | 按鈕：按下去執行 PeopleCode | 列出 | 第三輪 R3A |
| 15 | Push Button/Hyperlink：External Link | 按鈕：開外部網址 | 列出 | 第五輪 R5A＋App Designer |
| 16 | Push Button/Hyperlink：Internal Link | 按鈕：轉到別的 Component | 列出 | 第三輪 R3A |
| 18 | Secondary Page | 次頁 | 列出 | 第三輪 R3A |
| 19 | Grid | 表格 | 列出 | 第二輪 R2C＋App Designer |
| 21 | Push Button/Hyperlink：Secondary Page | 按鈕：開次頁 | 列出 | 第三輪 R3A |
| 23 | Horizontal Rule | 分隔線 | 不列（裝飾） | 第五輪 R5A＋App Designer |
| 24 | Tab Separator | 把 Grid 欄位分成分頁 | 列出 | 第五輪 R5A＋App Designer |
| 25 | HTML Area | HTML 區 | 列出 | 第三輪 R3A |
| 27 | Scroll Area | 捲動區 | 列出 | 第三輪 R3A |
| 其他 | （公司的客製頁面沒有用到） | — | 照原代碼寫 OTHER，不猜 | — |

**例**（下面的頁面、欄位名都是合成的）：一個申請單頁面上有一個「申請類別」欄位，元件代碼是 5，研究文件就寫 Drop-Down List Box；
一個「核准」按鈕的代碼是 12，寫成 Push Button/Hyperlink: PeopleCode Command，按下去做什麼另外寫在「行為邏輯」；
頁面上框住幾個欄位的 Group Box（代碼 2）不寫進表。

### 5.2 元件屬性（PSPNLFIELD.FIELDUSE，位元）——4 個

| 位元 | 意思 | 研究文件寫法 | 怎麼確認的 |
|---|---|---|---|
| 1 | Display Only（唯讀） | DISPLAY_ONLY | 第四輪 R4C（App Designer 已知欄位） |
| 2 | Invisible（隱藏） | INVISIBLE | 第四輪 R4C（App Designer 已知欄位） |
| 8 | Display Control（相關顯示的控制欄） | DISPLAY_CONTROL | 第七輪 R7K＋抽查 |
| 16 | Related Field（相關顯示；勾它會自動勾唯讀，所以相關顯示是 1＋16） | RELATED_TO=控制欄的 tab order | 第四輪 R4C、第六輪 R6 |

**例**：使用旗標存的是加總，拆開就知道勾了哪些。

| 存的數字 | 拆成 | 意思 |
|---|---|---|
| 0 | — | 一般可以輸入的欄位 |
| 1 | 1 | 唯讀 |
| 3 | 1＋2 | 唯讀，而且隱藏 |
| 8 | 8 | 相關顯示的控制欄（例如「部門代碼」） |
| 17 | 1＋16 | 相關顯示（例如「部門代碼」旁邊顯示的部門名稱），一定唯讀 |

### 5.3 相關顯示的對應（PSPNLFIELD.ASSOCFIELDNUM）

| 規則 | 怎麼確認的 |
|---|---|
| 關聯欄號從 0 起算：控制欄的 tab order（FIELDNUM）＝關聯欄號＋1；指到第 1 個欄位的相關顯示存 0 | 第六輪 R6 排除兩種對應；第七輪 R7K＋抽查定案 |
| 判斷是不是相關顯示看位元 16，不看關聯欄號有沒有大於 0 | 第六輪 R6 |
| tab order（FIELDNUM）就是 App Designer Order 頁籤的順序 | 第五輪 R5A |

**例**：部門代碼在 tab order 4（使用旗標 8），旁邊的部門名稱在 tab order 5（使用旗標 17、關聯欄號 3）。3＋1＝4，
所以部門名稱是部門代碼的說明，研究文件在部門名稱那一列寫 RELATED_TO=4。
另一個例子：員工編號放在頁面第 1 欄，旁邊的姓名關聯欄號是 0，0＋1＝1，指的就是員工編號。前幾輪用「關聯欄號大於 0」挑相關顯示，漏掉的就是這種。

### 5.4 Record 欄位設定（PSRECFIELDDB.USEEDIT，位元）——10 個

| 位元 | 意思（App Designer Record Field 屬性） | 研究文件寫法 | 怎麼確認的 |
|---|---|---|---|
| 1 | Key（鍵） | KEY | 第一輪 V5 |
| 32 | List Box Item（搜尋結果清單的欄位） | — | 第一輪 V5 |
| 64 | Descending Key（遞減鍵） | — | 第一輪 V5 |
| 256 | Required（必填） | REQUIRED | 第四輪 R4B（App Designer 已知欄位） |
| 512 | Translate Table Edit（值要在 Translate 清單內） | XLAT | 第一輪 V5 |
| 2048 | Search Key（搜尋鍵） | — | 第一輪 V5 |
| 4096 | Reasonable Date Test（合理日期檢查） | REASONABLE_DATE | 第一輪 V5 |
| 8192 | Yes/No Table Edit（只收 Y／N） | YES_NO | 第一輪 V5 |
| 16384 | Prompt Table Edit（輸入值必須在 Prompt 清單內） | PROMPT … EDIT | 第一輪 V5 |
| 32768 | Auto-Update（存檔時系統自動押時間） | AUTO_UPDATE | 第一輪 V5 |

這組和 Oracle PeopleCode API 文件列的位元一致。鍵欄位不會自動算必填（第三輪 R3C），必填一律看 256。

**例**：

| 存的數字 | 拆成 | 研究文件寫法 |
|---|---|---|
| 257 | 1＋256 | KEY REQUIRED（鍵，必填） |
| 2049 | 1＋2048 | KEY（同時是搜尋鍵） |
| 16640 | 256＋16384 | REQUIRED，查值寫 PROMPT <表> EDIT（必填，輸入值要在 Prompt 清單內） |
| 512 | 512 | 查值寫 XLAT（值要在 Translate 清單內） |
| 8192 | 8192 | 查值寫 YES_NO |
| 32768 | 32768 | AUTO_UPDATE（存檔時系統押時間，使用者不填） |

### 5.5 查值（Prompt）

| 代碼 | 意思 | 研究文件寫法 | 怎麼確認的 |
|---|---|---|---|
| EDITTABLE 有值 | 這個欄位有 Prompt 表（查值按鈕） | PROMPT <表> | 第一輪 V5 |
| EDITTABLE 以 `%` 開頭 | 動態 Prompt：Prompt 表在執行期由另一個欄位決定 | DYNAMIC | 第一輪 V5 |
| USEEDIT 帶 16384 | 輸入值會被檢核；沒帶＝只給查詢、不檢核 | EDIT／NO_EDIT | 第一輪 V5 |
| Prompt 表的 RECTYPE 0 | 實體表 | TABLE | 第一輪 V4 |
| Prompt 表的 RECTYPE 2 | Derived／Work（只在畫面上，不存資料庫） | DERIVED | 第一輪 V4 |
| Prompt 表的 RECTYPE 1、5、6 | 三種 View（SQL、Dynamic、Query View） | VIEW | PeopleTools 定義 |

**例**：部門代碼的 Prompt 表是一個部門 view、USEEDIT 帶 16384 → 研究文件寫 `PROMPT <部門 view> EDIT（VIEW；鍵 SETID,DEPTID,EFFDT）`：
輸入的部門要在 view 查得到，而且查值會看 SetID 與有效日期。另一個欄位的 Prompt 表寫成 `%EDITTABLE` → 動態 Prompt，研究文件寫 DYNAMIC，
再去追 PeopleCode 在執行期指定哪張表。

### 5.6 欄位資料型別（PSDBFIELD.FIELDTYPE）

| 代碼 | 意思 | 怎麼確認的 |
|---|---|---|
| 0 | 字元 | 第一輪 V4 |
| 1 | 長字元 | 第一輪 V4 |
| 2 | 數字 | 第一輪 V4 |
| 4 | 日期 | 第一輪 V4 |
| 6 | 日期時間 | 第一輪 V4 |

**例**：一個欄位資料型別是 4（日期），Record 欄位設定又帶 4096 → 這是日期欄位，而且輸入時會做合理日期檢查。

### 5.7 Component 動作（PSPNLGRPDEFN.ACTIONS，位元）——4 個

| 位元 | 動作（Component Properties → Use → Actions） | 意思 | 研究文件寫法 | 怎麼確認的 |
|---|---|---|---|---|
| 1 | Add | 新增一筆新鍵值 | ADD | 第四輪 R4D＋管理者確認順序 |
| 2 | Update/Display | 修改現行資料（有效日期只看得到目前與未來） | UPDATE_DISPLAY | 第四輪 R4D（App Designer 已知 Component） |
| 4 | Update/Display All | 看得到歷史列，只能改目前與未來 | UPDATE_DISPLAY_ALL | 第四輪 R4D＋管理者確認順序 |
| 8 | Correction | 連歷史列都能改 | CORRECTION | 第四輪 R4D＋管理者確認順序 |

**例**：

| 存的數字 | 拆成 | 意思 |
|---|---|---|
| 2 | 2 | 只能修改現行資料（第四輪核對的那個 Component 就是這樣） |
| 3 | 1＋2 | 可以新增，也可以修改 |
| 10 | 2＋8 | 可以修改、可以更正歷史，但不能新增 |
| 15 | 1＋2＋4＋8 | 四個動作都有 |

研究文件把 Component 本身寫成「## 畫面元件」的第一列，例如 `| TW_DEMO_REQ | 0 |  | Component | ADD UPDATE_DISPLAY | SEARCH TW_DEMO_REQSRCH |`
（ACTIONS＝3，搜尋頁查 TW_DEMO_REQSRCH）。

### 5.8 完整例子：從原始數字到研究文件

一個合成的申請單頁面，查詢手冊 §2l 讀到的原始數字：

| tab order | 綁的欄位 | 元件代碼 | 使用旗標 | 關聯欄號 | Record 欄位設定 | Prompt 表 |
|---|---|---|---|---|---|---|
| 3 | TW_DEMO_REQHDR.REQ_ID | 4 | 1 | 0 | 257 | — |
| 4 | TW_DEMO_REQHDR.DEPTID | 4 | 8 | 0 | 16640 | TW_DEMO_DEPTVW（view） |
| 5 | TW_DEMO_DEPTVW.DESCR | 4 | 17 | 3 | 0 | — |
| 6 | TW_DEMO_REQHDR.REQ_TYPE | 5 | 0 | 0 | 512 | — |
| 11 | TW_DEMO_WRK.APPROVE_PB | 12 | 0 | 0 | 0 | — |

照上面各節的對照翻譯後，研究文件「## 畫面元件」寫成：

| 頁面 | # | 欄位 | 元件 | 屬性 | 查值 |
|---|---|---|---|---|---|
| TW_DEMO_PG | 3 | TW_DEMO_REQHDR.REQ_ID | Edit Box | DISPLAY_ONLY KEY REQUIRED |  |
| TW_DEMO_PG | 4 | TW_DEMO_REQHDR.DEPTID | Edit Box | DISPLAY_CONTROL REQUIRED | PROMPT TW_DEMO_DEPTVW EDIT（VIEW；鍵 SETID,DEPTID,EFFDT） |
| TW_DEMO_PG | 5 | TW_DEMO_DEPTVW.DESCR | Edit Box | DISPLAY_ONLY RELATED_TO=4 |  |
| TW_DEMO_PG | 6 | TW_DEMO_REQHDR.REQ_TYPE | Drop-Down List Box |  | XLAT |
| TW_DEMO_PG | 11 | TW_DEMO_WRK.APPROVE_PB | Push Button/Hyperlink: PeopleCode Command |  |  |

讀起來就是：申請單號是鍵，畫面上唯讀、不能改；部門代碼必填、要從部門 view 選，輸入值會被檢核；旁邊的部門名稱唯讀、是部門代碼的說明；
申請類別是下拉選單、值來自 Translate 清單；「核准」按鈕按下去執行 PeopleCode。只要其中一個代碼翻錯——例如把使用旗標 16 當成唯讀、
或把關聯欄號當成 tab order——這張表就會寫錯，重建出來的畫面也會跟著錯。

每一項的細節與 SQL 輸出怎麼讀，見 `docs/design/ui-control-sql-record.md`。

---

## 6. 怎麼確保是對的

- **自我核對**：每段 SQL 用旁證判斷 OK／CHECK（例：標成核取方塊的元件，綁的應該都是 1 碼欄位），不靠人看大量資料。
- **已知物件對照**：在 App Designer 打開已知的頁面、欄位、Component，看勾選與 SQL 解出來的是否一致。
- **官方與社群文件比對**：和 Oracle 文件一致的直接採用；只有社群說法、或和我們結果對不上的，再拿到 App Designer 或資料確認。
- **假設互相比較**：同一段 SQL 同時算多種可能的對應，用「控制欄有沒有 Prompt」「控制欄是不是相關顯示那張表的鍵」這類可以分出高下的指標選出對的。
- **先在本機用假資料測過**：每段 SQL 送出前，都先在本機用合成資料（假名稱）跑過，確認語法正確、分得出對錯，才交給管理者執行。
- **第二雙眼睛**：最後一輪交給公司內可以查 DB 的 Claude 獨立執行並抽查實例。
- **只確認意思、不盤點數量**：比例只當判斷依據，紀錄不寫公司系統裡各有幾個。

---

## 7. 成果用在哪裡

- 兩版框架（OpenCode、Claude Code）的查詢手冊加了 2 段正式查詢；研究文件範本新增「## 畫面元件」一節，AI 研究有畫面的功能時會照表寫出每個元件。
- 已經寫好的研究文件可以用「補研究」補上這一節；重建用的 Spec 引擎也會讀這一節。
- 子代理回報格式、問答時要讀哪一節、搬運包、自動測試（含 Windows PowerShell 5.1 CI）都同步更新並通過。
- 每一步的原因與結果都記在框架的教訓帳本（L150～L157），之後接手的人可以重查。

## 8. 還沒做的事

- 外部連結按鈕的網址存在哪一欄（沒查）。
- 權限表的動作代碼（和 Component 動作同一組位元；多出來的 128 社群寫 Data Entry，沒在公司環境確認，還沒解碼）。
- 搜尋 Record 的搜尋條件欄位。
- 用新版框架實際研究一個有畫面的功能，確認「## 畫面元件」照表寫出（等公司機搬新版）。

---

## 附錄 A：代表性 SQL（看得出複雜度）

**A1 正式查詢：一個頁面的所有元件與屬性（查詢手冊 §2l）**——一段 SQL 同時解出元件種類、5 種屬性、相關顯示對應、
4 種 Record 設定、Prompt 表種類與鍵；`<schema>` 執行時換成擁有者名稱。

```sql
SELECT P.FIELDNUM, P.OCCURSLEVEL AS LVL, P.FIELDTYPE AS CODE,
       CASE P.FIELDTYPE WHEN 4 THEN 'Edit Box' WHEN 5 THEN 'Drop-Down List Box' WHEN 6 THEN 'Long Edit Box'
                        WHEN 7 THEN 'Check Box' WHEN 8 THEN 'Radio Button' WHEN 9 THEN 'Image'
                        WHEN 10 THEN 'Scroll Bar' WHEN 11 THEN 'Subpage'
                        WHEN 12 THEN 'Push Button/Hyperlink: PeopleCode Command'
                        WHEN 15 THEN 'Push Button/Hyperlink: External Link'
                        WHEN 16 THEN 'Push Button/Hyperlink: Internal Link' WHEN 18 THEN 'Secondary Page'
                        WHEN 19 THEN 'Grid' WHEN 21 THEN 'Push Button/Hyperlink: Secondary Page'
                        WHEN 24 THEN 'Tab Separator' WHEN 25 THEN 'HTML Area' WHEN 27 THEN 'Scroll Area'
                        ELSE 'OTHER' END AS CONTROL,
       TRIM(P.RECNAME) AS RECNAME, TRIM(P.FIELDNAME) AS FIELDNAME, TRIM(P.LBLTEXT) AS LBLTEXT,
       CASE WHEN BITAND(P.FIELDUSE, 1) > 0 THEN 'DISPLAY_ONLY' END AS DO,
       CASE WHEN BITAND(P.FIELDUSE, 2) > 0 THEN 'INVISIBLE' END AS INV,
       CASE WHEN BITAND(P.FIELDUSE, 16) > 0 THEN P.ASSOCFIELDNUM + 1 END AS RELATED_TO,
       CASE WHEN BITAND(P.FIELDUSE, 8) > 0 THEN 'DISPLAY_CONTROL' END AS DC,
       CASE WHEN BITAND(F.USEEDIT, 1) > 0 THEN 'KEY' END AS KEY_FLAG,
       CASE WHEN BITAND(F.USEEDIT, 256) > 0 THEN 'REQUIRED' END AS REQ,
       CASE WHEN BITAND(F.USEEDIT, 4096) > 0 THEN 'REASONABLE_DATE' END AS RDATE,
       CASE WHEN BITAND(F.USEEDIT, 32768) > 0 THEN 'AUTO_UPDATE' END AS AUPD,
       CASE WHEN BITAND(F.USEEDIT, 512) > 0 THEN 'XLAT' WHEN BITAND(F.USEEDIT, 8192) > 0 THEN 'YES_NO' END AS VALUES_EDIT,
       TRIM(F.EDITTABLE) AS PROMPT_REC,
       CASE WHEN TRIM(F.EDITTABLE) IS NULL THEN NULL
            WHEN SUBSTR(TRIM(F.EDITTABLE), 1, 1) = '%' THEN 'DYNAMIC'
            WHEN BITAND(F.USEEDIT, 16384) > 0 THEN 'EDIT' ELSE 'NO_EDIT' END AS PROMPT_EDIT,
       (SELECT CASE WHEN R.RECTYPE = 0 THEN 'TABLE' WHEN R.RECTYPE IN (1, 5, 6) THEN 'VIEW'
                    WHEN R.RECTYPE = 2 THEN 'DERIVED' ELSE 'OTHER' END
          FROM <schema>.PSRECDEFN R WHERE R.RECNAME = TRIM(F.EDITTABLE)) AS PROMPT_KIND,
       (SELECT LISTAGG(TRIM(K.FIELDNAME), ',') WITHIN GROUP (ORDER BY K.FIELDNUM)
          FROM <schema>.PSRECFIELDDB K
         WHERE K.RECNAME = TRIM(F.EDITTABLE) AND BITAND(K.USEEDIT, 1) > 0) AS PROMPT_KEYS,
       TRIM(P.GOTOPNLGRPNAME) AS GOTO_COMPONENT, TRIM(P.SUBPNLNAME) AS SUBPAGE
  FROM <schema>.PSPNLFIELD P
  LEFT JOIN <schema>.PSRECFIELDDB F ON F.RECNAME = P.RECNAME AND F.FIELDNAME = P.FIELDNAME
 WHERE P.PNLNAME = :pageName
   AND P.FIELDTYPE NOT IN (0, 1, 2, 3, 23)
   AND P.FIELDNUM > :afterFieldNum
 ORDER BY P.FIELDNUM
FETCH FIRST 40 ROWS ONLY
```

**A2 第七輪：一次比較 5 種相關顯示的對應**——每種對應算「控制欄是不是相關顯示那張表的鍵」與「控制欄有沒有帶控制欄位元」兩個比例。

```sql
WITH P AS (
  SELECT PNLNAME, FIELDNUM, TRIM(TO_CHAR(PNLFLDID)) AS FLDID, RECNAME, FIELDNAME, FIELDUSE, ASSOCFIELDNUM
    FROM <schema>.PSPNLFIELD
   WHERE PNLNAME LIKE 'TW\_%' ESCAPE '\'
),
REL AS (SELECT * FROM P WHERE BITAND(FIELDUSE, 16) > 0),
H AS (
  SELECT 'H0' AS HYP, R.RECNAME AS RREC, C.FIELDNAME AS CFLD, C.FIELDUSE AS CUSE
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FIELDNUM = R.ASSOCFIELDNUM
  UNION ALL
  SELECT 'H1', R.RECNAME, C.FIELDNAME, C.FIELDUSE
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FIELDNUM = R.ASSOCFIELDNUM + 1
  UNION ALL
  SELECT 'H3', R.RECNAME, C.FIELDNAME, C.FIELDUSE
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FLDID = TO_CHAR(R.ASSOCFIELDNUM)
  UNION ALL
  SELECT 'H4', R.RECNAME, C.FIELDNAME, C.FIELDUSE
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FLDID = TO_CHAR(R.ASSOCFIELDNUM + 1)
  UNION ALL
  SELECT 'NB', R.RECNAME, C.FIELDNAME, C.FIELDUSE
    FROM REL R JOIN P C ON C.PNLNAME = R.PNLNAME AND C.FIELDNUM = R.FIELDNUM - 1
),
HK AS (
  SELECT H.HYP, H.CUSE,
         CASE WHEN EXISTS (SELECT 1 FROM <schema>.PSRECFIELDDB K
                            WHERE K.RECNAME = H.RREC AND K.FIELDNAME = H.CFLD AND BITAND(K.USEEDIT, 1) > 0)
              THEN 1 ELSE 0 END AS ISKEY
    FROM H
)
SELECT HYP, COUNT(*) AS N, ROUND(100 * AVG(ISKEY)) AS KEY_PCT, ROUND(100 * AVG(SIGN(BITAND(CUSE, 8)))) AS B8_PCT
  FROM HK
 GROUP BY HYP
 ORDER BY HYP;
```

## 附錄 B：詳細文件

| 文件 | 內容 |
|---|---|
| `docs/design/ui-control-sql-record.md` | 代碼確認紀錄：每個代碼是什麼、怎麼確認、輸出怎麼讀 |
| `docs/design/ui-metadata-check-r1.md`～`r7.md` | 七輪驗證 SQL 原文、怎麼看、各輪結果 |
| `docs/design/ui-control-lookup-dependency-memo.md` | 起始的缺口盤點與規劃（§7） |
| `.opencode/peoplesoft/lessons/applied.md` | 框架教訓帳本（L150～L157） |
