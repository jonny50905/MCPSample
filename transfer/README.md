# transfer — 搬運包（一版一個文字檔）

公司機不能 git 下載時，用搬運包把**一個版本要搬的檔一次搬完**：複製一個文字檔，在公司機執行一個指令解開。
兩版分開，只拿你在用的那一個：

| 檔 | 版本 | 內容 |
|---|---|---|
| `ps-bundle-opencode.txt` | OpenCode 版 | `scripts/**`＋`.opencode/**`＋`AGENTS.md`＋搬運 manifest |
| `ps-bundle-claude.txt` | Claude Code 版 | `scripts/**`＋`.claude/**`＋`CLAUDE.md`＋搬運 manifest（`claude-code/` 前綴已去掉） |

搬運包由維護端 `ps-fs-doctor -WriteManifest` 自動重生（與 manifest 同一個 commit），不要手改。

## 公司機怎麼用

1. **第一次**：先照舊手動搬 `scripts/ps-bundle.ps1` 這一個檔（存 UTF-8 with BOM）。之後每個搬運包都帶新版的它。
2. 在 GitHub 開對應搬運包的 Raw，全選複製，貼到記事本，另存成 UTF-8 文字檔（放哪裡都可以，例如 `D:\搬運\ps-bundle-claude.txt`）。
   有「Download raw file」按鈕能用的話，直接下載也可以。
3. 在專案資料夾執行，先看計畫、再真的解開：

   ```powershell
   powershell -NoProfile -File .\scripts\ps-bundle.ps1 -Bundle D:\搬運\ps-bundle-claude.txt -DryRun
   powershell -NoProfile -File .\scripts\ps-bundle.ps1 -Bundle D:\搬運\ps-bundle-claude.txt
   ```

4. 跑 `ps-fs-doctor`（Claude Code 版再跑 `ps-claude-doctor`），回報結論代號。

## 解開時會做什麼

- **先驗整包**：開頭、結尾、檔數、每個檔的雜湊都要對；貼上被截斷、存成非 UTF-8、路徑不合法 → 一個檔都不寫（代號 T／H／P）。
- **逐檔三方比對**（本機現況／上次搬入時的 manifest 記錄／搬運包）：
  - 本機沒有 → 新增；本機已一致 → 跳過。
  - 本機沒改過 → 更新（舊檔先備份）。
  - 本機改過、這次搬運包沒動它 → **保留本機**（例：已回填的 profile、`/ps-lesson` 改過的規則檔）。
  - 本機改過、搬運包也改了 → **衝突**：本機不動，新版另存 `<檔>.incoming`，人工合併後刪掉 `.incoming`（代號 C）。
  - `scripts/**` 不在本機改，內容不同一律更新（舊檔照樣備份）。
- 必刪舊檔（manifest 的 removed）移到備份。備份在 `auto-loop-logs\ps-bundle-backup\<時間>\`。
- 研究產出、`.ps-private`、`.ps-runtime` 不在搬運包裡，永遠不會被動到。
