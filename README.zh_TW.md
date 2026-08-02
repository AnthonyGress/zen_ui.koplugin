<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./icons/zen_ui_light.svg" />
    <img width="300" src="./icons/zen_ui.svg" alt="Zen UI 標誌" />
  </picture>
</div>

<br>
<br>

<h1 align="center">Zen UI</h1>

<p align="center">適用於 KOReader 的清爽、極簡 UI。</p>

## 文件
如需最完整且最新的文件，請造訪 [https://zen-labs.org/zen-ui](https://zen-labs.org/zen-ui)

## 理念

Zen UI 以一個簡單理念打造：**少即是多。** Zen UI 中的所有設計，都是為了移除雜亂或提供明確價值。介面保持快速、輕量，並專注於讓閱讀更愉快。

在整個開發過程中，有三件事絕不妥協：**效能**、**穩定性**和**易用性**。每項功能都針對電池效率與反應速度進行調校。

## 速度與效能

Zen UI 設計得輕量且高效。即使書庫包含數千本書，速度、反應能力或資源使用量也不會有明顯變化。修補程式會策略性注入，並且只在需要時載入。無論書庫大小如何，Zen UI 都能維持一致效能，而不會過度消耗裝置的電池或記憶體。

## 功能

### 快速設定面板
可在任何地方以下滑手勢開啟的選單，包含你經常使用的所有控制項——亮度、色溫、WiFi、夜間模式、睡眠、旋轉等。完全可設定。

<img src="./images/quickstart/onboarding/quicksettings.png" width="500" alt="快速設定">

### 書庫

<img src="./images/quickstart/onboarding/library_covers_full.png" width="350" height="auto" alt="書庫封面">
      
<img src="./images/quickstart/onboarding/library_list_full.png" width="350" height="auto" alt="書庫列表">

- 簡潔的馬賽克與列表檢視選項，可盡量放大書籍封面，並提供多種選項
- 用於資料夾縮圖的書籍封面圖庫
- 可設定排序、每頁項目數，以及橫向/直向版面
- 檔案瀏覽器中的精簡內容選單。點一下並按住即可快速存取詳細資訊、全螢幕封面圖、閱讀狀態等。

<img src="./images/quickstart/onboarding/context_menu.png" width="350" height="auto" alt="內容選單">
<img src="./images/quickstart/onboarding/library_context.png" width="350" height="auto" alt="書庫內容">

### 底部導覽列
位於書庫底部的簡潔分頁式導覽列。可設定分頁（書庫、漫畫、我的最愛、作者、歷史、收藏集等），支援選用標籤文字、自訂圖示與可排序版面。

<img src="./images/quickstart/onboarding/navbar.png" width="500" alt="導覽列">

### Zen 模式

將預設 KOReader 介面精簡到最必要的部分。- 隱藏 KOReader 的所有預設選單，只保留單一統一的 Zen UI 設定分頁。

<img src="./images/quickstart/onboarding/zen_mode.png" width="175" alt="Zen 模式">

### 鎖定模式

為無干擾閱讀建立一個更受限制的沙盒。鎖定模式旨在讓裝置專注於核心流程：瀏覽書籍與閱讀書籍。對於不應被任何設定或不必要選項造成負擔的高齡或年幼讀者，這個模式非常適合。

- 限制存取設定與組態變更
- 可選擇放大 UI，取得更大、更簡單的檢視
- 保持體驗簡單，並以閱讀為優先

<img src="./images/quickstart/onboarding/lockdown_mode.png" width="175" alt="鎖定模式">


### 自訂狀態列
閱讀器中提供極簡狀態列，書庫中提供更詳細的狀態列。只顯示你想要的內容：時間、電量、磁碟空間、自訂文字——全部皆為選用，且可個別切換。

<img src="./images/quickstart/onboarding/status_bar.png" width="500" alt="狀態列">

### 閱讀器改進
- 自訂頁面瀏覽器（類似 Kindle）可用於快速瀏覽頁面、搜尋書籍、快速變更字型大小。
- 停用底部選單，避免意外變更字型大小。
- 邊緣觸控防護，可避免握住裝置觸控螢幕邊緣時誤觸手勢。
- 從少量預先設計的閱讀進度列中選擇，或建立並儲存自己的進度列。點一下即可切換預設。

<img src="./images/quickstart/onboarding/reader.png" width="500" alt="閱讀器">

### 自動燈光排程
三個獨立的排程系統取代 KOReader 有限的自動夜間模式：

- **夜間模式排程** — 每天在指定時間自動開啟/關閉夜間模式
- **亮度排程** — 為夜間/白天安排亮度等級
- **色溫排程** — 為夜間/白天安排螢幕色溫

每個排程都可單獨或搭配使用。這種細緻的方式可讓你依照偏好精準調整燈光。

### OPDS 外掛程式主題
OPDS 外掛程式會遵循你的所有 Zen UI 書庫樣式設定——在本機書庫與線上目錄之間建立一致的視覺體驗。

- 來自書庫設定的馬賽克、封面格狀與列表檢視模式
- 若已啟用，則對封面套用圓角
- 可從快速設定一鍵存取的預設目錄

使用你為本機收藏自訂的同樣清爽、一致介面，瀏覽喜愛的 OPDS 來源。

## 統一設定
- 將最重要的設定整合到單一、更精簡的設定分頁
- 設定依功能區域分組（書庫、控制、啟動器、閱讀器、附加功能、關於）。
- 大多數功能都可個別切換，並已選擇一些合理的預設值。
- 不必離開 KOReader 或連接電腦，即可直接從設定更新 Zen UI。

<img src="./images/quickstart/onboarding/zen_ui_settings.png" width="500" alt="Zen UI 設定">

## 外掛程式整合

外部外掛程式可以將小工具加入首頁：

```lua
local register = rawget(_G, "__ZEN_UI_REGISTER_HOME_ITEM")
if register then
    register("my_plugin.summary", function(ctx)
        -- Return a KOReader widget sized to ctx.width and ctx.height.
    end, {
        label = "My summary",
        size = {
            preferred_pct = 0.20,
            min_pct = 0.12,
            max_pct = 0.30,
        },
    })
end
```

建構器會接收 `width`、`height`、`is_first_row`，以及特定項目的
`module_cfg` 表。新項目預設為停用，可在 **Home > Widgets** 下啟用並
定位。在 Zen UI 之前載入的外掛程式，應在收到 `ZenUIReady` 時註冊；使用
`_G.__ZEN_UI_UNREGISTER_HOME_ITEM(id)` 取消註冊。

若引數無效或與內建 ID 衝突，註冊會回傳 `false`。
註冊既有的外部 ID 會取代其建構器與選項。

## 前置需求

- 必須先安裝 KOReader 才能使用 Zen UI。[安裝 KOReader](https://github.com/koreader/koreader#installation)
- 停用或解除安裝任何會修改 UI 的**其他外掛程式/修補程式**，例如 Simple UI、Project: Title、VOS，因為它們可能發生衝突並造成不穩定。


## 安裝

1. 前往 [Releases](https://github.com/AnthonyGress/zen_ui.koplugin/releases) 頁面，並從最新版本下載 `zen_ui.koplugin.zip`。
2. 解壓縮封存檔。你應該會得到名為 `zen_ui.koplugin` 的**資料夾**。
3. 將 `zen_ui.koplugin` **資料夾**複製到你裝置上的 KOReader 外掛程式目錄：請見下表
      - 請確認複製的是已解壓縮的**資料夾**，而**不是 .zip** 檔案本身
4. 重新啟動 KOReader。Zen UI 會自動載入
      - 如果你沒有看到 Zen UI 載入，請在 Tools > More tools > Plugin management > Zen UI 中手動啟用外掛程式
> 最終路徑應如下所示：`.../plugins/zen_ui.koplugin/main.lua`  


| 裝置 | 外掛程式目錄 |
|--------|-------------------|
| **Kobo** | `/mnt/onboard/.adds/koreader/plugins/` |
| **Kindle** | `/mnt/base-us/koreader/plugins/` |
| **PocketBook** | `/mnt/ext1/applications/koreader/plugins/` |
| **Android** | `sdcard/koreader/plugins/` |
| **桌面版 (Linux/macOS)** | `/koreader/plugins/` |

## 從 Project Title 移轉

如果你先前使用過 [Project Title](https://github.com/joshuacant/ProjectTitle)，在使用 Zen UI 前必須停用或移除它。兩個外掛程式都會修補 Cover Browser，同時啟用會造成衝突。

請選擇下列其中一種方式：

- **移除它** — 從你的 KOReader 外掛程式目錄刪除 `projecttitle.koplugin` 資料夾。
- **停用它** — 將資料夾重新命名為 `projecttitle.koplugin.disabled`。KOReader 會在下次啟動時忽略它。

停用或移除 Project Title 後，重新啟動 KOReader，Zen UI 將能乾淨載入。

## 在地化

Zen UI 目前已翻譯為：

| 地區設定 | 語言 |
|--------|----------|
| `en` | 英文 |
| `it` | 義大利文 |
| `es` | 西班牙文 |
| `fr` | 法文 |
| `nl` | 荷蘭文 |
| `de` | 德文 |
| `bg` | 保加利亞文 |
| `cs` | 捷克文 |
| `pt_BR` | 巴西葡萄牙文 |
| `pt_PT` | 歐洲葡萄牙文 |
| `ro` | 羅馬尼亞文 |
| `ru` | 俄文 |
| `uk` | 烏克蘭文 |
| `zh_CN` | 簡體中文 |
| `zh_TW` | 繁體中文 |

如果你發現翻譯中有任何問題或需要修正，歡迎貢獻。

若要貢獻翻譯或修正現有翻譯，請參閱 [locales/README.md](locales/README.md) 與 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 致謝

Zen UI 是原創作品，但如果沒有更廣大的 KOReader 社群，它不會存在。多個開放原始碼專案提供了元件、靈感、參考實作，或經改寫並延伸建構的程式碼：

- **[joshuacant/ProjectTitle](https://github.com/joshuacant/ProjectTitle)** — 對我來說，一切由這個外掛程式開始。這是我第一次接觸 KOReader 外掛程式與替代 UI。
- **[qewer33/koreader-patches](https://github.com/qewer33/koreader-patches)** — 底部導覽列與快速設定元件。也提供了額外的修補方式與想法，特別是 UI 自訂相關。
- **[sebdelsol/KOReader.patches](https://github.com/sebdelsol/KOReader.patches)** — 啟發 Zen UI 多項功能的修補程式與 UI 技術。
- **[doctorhetfield-cmd/simpleui.koplugin](https://github.com/doctorhetfield-cmd/simpleui.koplugin)** — 另一個 KOReader UI 外掛程式，既是靈感來源，也提供了如何在整個外掛程式套用語言翻譯的範例。
- **[kristianpennacchia/zzz-readermenuredesign.koplugin](https://github.com/kristianpennacchia/zzz-readermenuredesign.koplugin)** — 閱讀器搜尋選單重新設計的靈感來源

感謝所有公開發布 KOReader 作品的人。

## 貢獻

歡迎提交錯誤回報、功能請求、翻譯與程式碼貢獻。詳情請參閱 [CONTRIBUTING.md](CONTRIBUTING.md)。

請遵循以下準則：

- **每個 PR 只包含一項功能** - 讓 Pull Request 聚焦於單一功能或修正
- **PR 到 dev 分支** - 將 PR 提交到 `dev` 分支以進行測試/審查。
- **審查 AI 產生的程式碼** - 如果使用 AI 工具，所有程式碼都必須在提交前徹底審查與測試（這本來就該做，但對 AI 產生的程式碼尤其如此）
- **維持一致性** - 新程式碼必須符合專案既有的風格、主題與整體使用者體驗

## FAQ/社群

如果你想取得協助、聊天或參與貢獻，歡迎加入 [Discord Community](https://discord.gg/Tv2PhrCPQ8)

## 安全性

請參閱 [SECURITY.md](SECURITY.md) 了解如何回報弱點。

## 授權

[GPL-3.0](LICENSE.md)
