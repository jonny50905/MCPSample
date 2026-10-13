# transfer — 搬運包（一版收成幾份文字檔）

公司機不能 git 下載時，用搬運包把**一個版本要搬的檔一次搬完**：把幾份文字檔複製到同一個資料夾，在公司機執行一個指令解開。
每份不超過約 500 KB（只在檔與檔之間切開），GitHub 網頁開得了、複製貼上不吃力。兩版分開，只拿你在用的那一版的**全部各份**（兩版放同一個資料夾時見表下說明）：

| 檔 | 版本 | 內容 |
|---|---|---|
| `ps-bundle-opencode-01ofNN.txt` … `NNofNN.txt` | OpenCode 版 | `scripts/**`＋`.opencode/**`＋`AGENTS.md`＋搬運 manifest |
| `ps-bundle-claude-01ofNN.txt` … `NNofNN.txt` | Claude Code 版 | `scripts/**`＋`.claude/**`＋`CLAUDE.md`＋搬運 manifest（`claude-code/` 前綴已去掉） |

`NN` 是總份數（例：`ps-bundle-claude-01of06.txt` 到 `ps-bundle-claude-06of06.txt`）。各份由維護端 `ps-fs-doctor -WriteManifest`
自動重生（與 manifest 同一個 commit），不要手改；每次都要拿同一次打包的全部各份。

兩版放在同一個專案資料夾時（OpenCode 版的 Spec 文件流程當 Claude Code 版的備案，SOP-29），兩版的全部各份都要拿（同一次交接），
各放一個空資料夾、各解一次；只解一版的話，另一版的 manifest 跟不上共用的 `scripts/**`，ps-fs-doctor 會報「版本不符」。

## 公司機怎麼用

1. **第一次**：先照舊手動搬 `scripts/ps-bundle.ps1` 這一個檔（存 UTF-8 with BOM）。之後每個搬運包都帶新版的它。
   （本機的 `ps-bundle.ps1` 還是只認單一檔的舊版時，也要先手動換成新版；或把各份依序貼進同一個檔，舊版也解得開。）
2. 開一個**空資料夾**（例如 `D:\搬運\這次`）。在 GitHub 逐份開 Raw，全選複製，貼到記事本，另存成 UTF-8 的 `.txt` 放進這個資料夾
   （檔名不拘，例如 `1.txt`、`2.txt`…）。有「Download raw file」按鈕能用的話，直接下載也可以。
3. 在專案資料夾執行，先看計畫、再真的解開：

   ```powershell
   powershell -NoProfile -File .\scripts\ps-bundle.ps1 -Bundle D:\搬運\這次 -DryRun
   powershell -NoProfile -File .\scripts\ps-bundle.ps1 -Bundle D:\搬運\這次
   ```

   `-Bundle` 也可以給其中任一份的檔名（同資料夾的其他份會自動找齊）。
4. 跑 `ps-fs-doctor`（Claude Code 版再跑 `ps-claude-doctor`），回報結論代號。

## 解開時會做什麼

- **先逐份驗**：每一份都要在、都要完整（每份最後一行是 `@@@PSBUNDLE-PART-END`），內容雜湊要對，各份要是同一次打包的。
  缺哪一份、哪一份被截斷或被改，訊息會指出第幾份（代號 T／H）；資料夾裡混了別次打包的份也會停下來列出各組（代號 T）——
  只留這次的，或換一個空資料夾。
- **再驗整包**：開頭、結尾、檔數、每個檔的雜湊都要對；存成非 UTF-8、路徑不合法 → 一個檔都不寫（代號 T／H／P）。
  記事本另存的 CRLF、BOM 不影響；另存成「Unicode」也讀得懂。
- **逐檔三方比對**（本機現況／上次搬入時的 manifest 記錄／搬運包）：
  - 本機沒有 → 新增；本機已一致 → 跳過。
  - 本機沒改過 → 更新（舊檔先備份）。
  - 本機改過、這次搬運包沒動它 → **保留本機**（例：已回填的 profile、`/ps-lesson` 改過的規則檔）。
  - 本機改過、搬運包也改了 → **衝突**：本機不動，新版另存 `<檔>.incoming`，人工合併後刪掉 `.incoming`（代號 C）。
  - `scripts/**` 不在本機改，內容不同一律更新（舊檔照樣備份）。
- 必刪舊檔（manifest 的 removed）移到備份。備份在 `auto-loop-logs\ps-bundle-backup\<時間>\`。
- 研究產出、`.ps-private`、`.ps-runtime` 不在搬運包裡，永遠不會被動到。
