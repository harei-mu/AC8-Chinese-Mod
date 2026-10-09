# 第三方依赖与资源归属

本项目原创的安装器、脚本与译文贡献使用 GPL-3.0-only，全文见根目录 `LICENSE`。GPLv3 不改变游戏、商标、截图或第三方作品的原有权利。

| 依赖 | 使用方式 | 原许可证 / 来源 |
| --- | --- | --- |
| UE4SS v3.0.1-1164-g5e627997 | HUD 字体资源加载运行时 | MIT，[UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)，安装包含原许可证 |
| AC8OverrideLoader 0.2.0 | 挂载字体容器，作为独立模块使用 | MIT，[上游](https://github.com/JustMonika24769/AC8OverrideLoader)，固定二进制哈希，安装包含原许可证 |
| Noto Sans SC | 新增汉字的字形来源 | SIL Open Font License 1.1，[Noto CJK 许可证](https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE)，安装包附带 `Licenses/NotoSansSC.txt`；字形统计见 `reports/hud-font.json` |
| retoc、资源解析工具、Pillow、fontTools | 本地构建工具，不是本项目原创代码 | 各自上游许可证；工具二进制不提交源码仓库 |

AC8OverrideLoader 上游当前提供二进制与文档，没有可审阅的实现源码。本仓库开源本项目自身的安装、翻译和构建代码，不将该独立依赖冒充为已做源码审计。

原始游戏程序、原始 DAT、提取的原始字体和原始资源容器不包含在源码仓库。字体补丁是针对已购买游戏的修改资源，依赖游戏类型信息；不能把游戏原有字形或资源归入 GPL。截图来自实际测试，仅用于说明汉化效果，游戏画面权利归原权利人。
