<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./icons/zen_ui_light.svg" />
    <img width="300" src="./icons/zen_ui.svg" alt="Zen UI 标志" />
  </picture>
</div>

<br>
<br>

<h1 align="center">Zen UI</h1>

<p align="center">适用于 KOReader 的清爽、极简 UI。</p>

## 文档
如需最完整且最新的文档，请访问 [https://zen-labs.org/zen-ui](https://zen-labs.org/zen-ui)

## 理念

Zen UI 基于一个简单的理念构建：**少即是多。** Zen UI 中的一切设计，都是为了减少杂乱或提供明确价值。界面始终保持快速、轻量，并专注于让阅读更愉悦。

在整个开发过程中，有三件事绝不妥协：**性能**、**稳定性**和**易用性**。每项功能都针对电池效率和响应速度进行了调校。

## 速度与性能

Zen UI 设计得轻量且高效。即使书库包含数千本图书，速度、响应能力或资源占用也不会出现明显变化。补丁会策略性注入，并且仅在需要时加载。无论书库规模如何，Zen UI 都能保持稳定性能，而不会过度消耗设备的电池或内存。

## 功能

### 快速设置面板
可在任意位置通过下滑打开的菜单，包含你经常使用的所有控制项——亮度、色温、WiFi、夜间模式、睡眠、旋转等。完全可配置。

<img src="./images/quickstart/onboarding/quicksettings.png" width="500" alt="快速设置">

### 书库

<img src="./images/quickstart/onboarding/library_covers_full.png" width="350" height="auto" alt="书库封面">
      
<img src="./images/quickstart/onboarding/library_list_full.png" width="350" height="auto" alt="书库列表">

- 简洁的马赛克视图和列表视图选项，可最大化显示书籍封面，并提供多种选项
- 用于文件夹缩略图的书籍封面图库
- 可配置排序、每页项目数以及横屏/竖屏布局
- 文件浏览器中的精简上下文菜单。点按并按住即可快速访问详情、全屏封面图、阅读状态等。

<img src="./images/quickstart/onboarding/context_menu.png" width="350" height="auto" alt="上下文菜单">
<img src="./images/quickstart/onboarding/library_context.png" width="350" height="auto" alt="书库上下文">

### 底部导航栏
位于书库底部的简洁标签式导航栏。可配置标签页（书库、漫画、收藏、作者、历史、合集等），支持可选标签文字、自定义图标和可排序布局。

<img src="./images/quickstart/onboarding/navbar.png" width="500" alt="导航栏">

### Zen 模式

将默认 KOReader 界面精简到最必要的部分。- 隐藏 KOReader 的所有默认菜单，只保留一个统一的 Zen UI 设置标签页。

<img src="./images/quickstart/onboarding/zen_mode.png" width="175" alt="Zen 模式">

### 锁定模式

为无干扰阅读创建一个更受限制的沙盒。锁定模式旨在让设备专注于核心流程：浏览图书和阅读图书。对于不应被任何设置或不必要选项干扰的年长或年幼读者来说，此模式非常适合。

- 限制访问设置和配置更改
- 可选择放大 UI，以获得更大、更简单的视图
- 保持体验简单，并以阅读为优先

<img src="./images/quickstart/onboarding/lockdown_mode.png" width="175" alt="锁定模式">


### 自定义状态栏
阅读器中提供极简状态栏，书库中提供更详细的状态栏。只显示你想要的内容：时间、电量、磁盘空间、自定义文字——全部可选，并可单独开关。

<img src="./images/quickstart/onboarding/status_bar.png" width="500" alt="状态栏">

### 阅读器改进
- 自定义页面浏览器（类似 Kindle）用于快速浏览页面、搜索书籍、快速更改字体大小。
- 禁用底部菜单，防止意外更改字体大小。
- 边缘触控防护，可避免握住设备边缘触摸屏时误触手势。
- 从少量预设计的阅读进度条中选择，或创建并保存你自己的进度条。只需点按一次即可切换预设。

<img src="./images/quickstart/onboarding/reader.png" width="500" alt="阅读器">

### 自动灯光计划
三个独立的计划系统取代 KOReader 有限的自动夜间模式：

- **夜间模式计划** — 每天在指定时间自动开启/关闭夜间模式
- **亮度计划** — 为夜间/白天安排亮度级别
- **色温计划** — 为夜间/白天安排屏幕色温

每个计划都可以单独或组合使用。这种细粒度方式让你能根据偏好精确调整灯光。

### OPDS 插件主题
OPDS 插件会遵循你的所有 Zen UI 书库样式设置——在本地书库和在线目录之间创建统一的视觉体验。

- 来自书库设置的马赛克、封面网格和列表视图模式
- 如果已启用，则对封面应用圆角
- 可从快速设置一键访问的默认目录

使用与你为本地收藏自定义的同样清爽、一致的界面浏览你喜爱的 OPDS 来源。

## 统一设置
- 将最重要的设置整合到单个更精简的设置标签页中
- 设置按功能区域分组（书库、控制、启动器、阅读器、附加功能、关于）。
- 大多数功能都可以独立开关，并已选择一些合理的默认值。
- 无需离开 KOReader 或连接电脑，即可直接从设置中更新 Zen UI。

<img src="./images/quickstart/onboarding/zen_ui_settings.png" width="500" alt="Zen UI 设置">

## 插件集成

外部插件可以向主页添加小组件：

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

构建器会接收 `width`、`height`、`is_first_row` 以及特定项目的
`module_cfg` 表。新项目默认处于禁用状态，可在 **Home > Widgets** 下启用并
定位。应在 Zen UI 之前加载的插件收到 `ZenUIReady` 时进行注册；使用
`_G.__ZEN_UI_UNREGISTER_HOME_ITEM(id)` 取消注册。

如果参数无效或与内置 ID 冲突，注册会返回 `false`。
注册已有的外部 ID 会替换其构建器和选项。

## 前置要求

- 必须先安装 KOReader 才能使用 Zen UI。[安装 KOReader](https://github.com/koreader/koreader#installation)
- 禁用或卸载任何会修改 UI 的**其他插件/补丁**，例如 Simple UI、Project: Title、VOS，因为它们可能产生冲突并导致不稳定。


## 安装

1. 前往 [Releases](https://github.com/AnthonyGress/zen_ui.koplugin/releases) 页面，并从最新版本下载 `zen_ui.koplugin.zip`。
2. 解压归档文件。你应该会得到一个名为 `zen_ui.koplugin` 的**文件夹**。
3. 将 `zen_ui.koplugin` **文件夹**复制到你设备上的 KOReader 插件目录：见下表
      - 确保复制的是已解压的**文件夹**，而**不是 .zip** 文件本身
4. 重启 KOReader。Zen UI 将自动加载
      - 如果你没有看到 Zen UI 加载，请在 Tools > More tools > Plugin management > Zen UI 中手动启用插件
> 最终路径应类似于：`.../plugins/zen_ui.koplugin/main.lua`  


| 设备 | 插件目录 |
|--------|-------------------|
| **Kobo** | `/mnt/onboard/.adds/koreader/plugins/` |
| **Kindle** | `/mnt/base-us/koreader/plugins/` |
| **PocketBook** | `/mnt/ext1/applications/koreader/plugins/` |
| **Android** | `sdcard/koreader/plugins/` |
| **桌面端 (Linux/macOS)** | `/koreader/plugins/` |

## 从 Project Title 迁移

如果你之前使用过 [Project Title](https://github.com/joshuacant/ProjectTitle)，在使用 Zen UI 前必须禁用或移除它。两个插件都会修补 Cover Browser，同时启用会导致冲突。

选择以下一种方式：

- **移除它** — 从你的 KOReader 插件目录中删除 `projecttitle.koplugin` 文件夹。
- **禁用它** — 将文件夹重命名为 `projecttitle.koplugin.disabled`。KOReader 会在下次启动时忽略它。

禁用或移除 Project Title 后，重启 KOReader，Zen UI 将干净地加载。

## 本地化

Zen UI 当前已翻译为：

| 区域设置 | 语言 |
|--------|----------|
| `en` | 英语 |
| `it` | 意大利语 |
| `es` | 西班牙语 |
| `fr` | 法语 |
| `nl` | 荷兰语 |
| `de` | 德语 |
| `bg` | 保加利亚语 |
| `cs` | 捷克语 |
| `pt_BR` | 巴西葡萄牙语 |
| `pt_PT` | 欧洲葡萄牙语 |
| `ro` | 罗马尼亚语 |
| `ru` | 俄语 |
| `uk` | 乌克兰语 |
| `zh_CN` | 简体中文 |
| `zh_TW` | 繁体中文 |

如果你发现翻译中有任何问题或需要修正，欢迎贡献。

要贡献翻译或修复现有翻译，请参阅 [locales/README.md](locales/README.md) 和 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 致谢

Zen UI 是原创作品，但如果没有更广泛的 KOReader 社区，它不会存在。多个开源项目提供了组件、灵感、参考实现或代码，并在此基础上进行了改造与构建：

- **[joshuacant/ProjectTitle](https://github.com/joshuacant/ProjectTitle)** — 对我来说，一切由这个插件开始。这是我第一次接触 KOReader 插件和替代 UI。
- **[qewer33/koreader-patches](https://github.com/qewer33/koreader-patches)** — 底部导航栏和快速设置组件。还提供了额外的补丁方法和想法，尤其是围绕 UI 自定义方面。
- **[sebdelsol/KOReader.patches](https://github.com/sebdelsol/KOReader.patches)** — 为 Zen UI 多项功能提供参考的补丁和 UI 技术。
- **[doctorhetfield-cmd/simpleui.koplugin](https://github.com/doctorhetfield-cmd/simpleui.koplugin)** — 另一个 KOReader UI 插件，既提供了灵感，也展示了如何在整个插件中应用语言翻译。
- **[kristianpennacchia/zzz-readermenuredesign.koplugin](https://github.com/kristianpennacchia/zzz-readermenuredesign.koplugin)** — 阅读器搜索菜单重新设计的灵感来源

感谢所有公开发布 KOReader 作品的人。

## 贡献

欢迎提交错误报告、功能请求、翻译和代码贡献。详情请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。

请遵循以下指南：

- **每个 PR 只包含一个功能** - 保持拉取请求聚焦于单个功能或修复
- **向 dev 分支提交 PR** - 将 PR 提交到 `dev` 分支以进行测试/审核。
- **审核 AI 生成的代码** - 如果使用 AI 工具，所有代码都必须在提交前经过彻底审核和测试（这本来就应该做，但对 AI 生成的代码尤其如此）
- **保持一致性** - 新代码必须与项目现有的风格、主题和整体用户体验保持一致

## FAQ/社区

如果你想获得帮助、聊天或参与贡献，欢迎加入 [Discord Community](https://discord.gg/Tv2PhrCPQ8)

## 安全

有关如何报告漏洞，请参阅 [SECURITY.md](SECURITY.md)。

## 许可证

[GPL-3.0](LICENSE.md)
