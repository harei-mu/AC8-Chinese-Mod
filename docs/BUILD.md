# 开发构建说明

普通玩家使用 Releases 的完整安装包，无需安装开发工具。以下仅适用于从源码构建或维护译文。

## 固定目标

- 游戏 1.1.2.0 / Steam build 25201480 / UE 5.4。
- `Game/Binaries/Win64/AceCombat8.exe` SHA-256：`51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F`。
- 文字键表：`Live/Content/Localization/GameData/CP_Cmn.dat`；英文为 `CP_B.dat`，简体中文为 `CP_M.dat`。文字表原生索引有 46584 项。
- HUD 字体虚拟路径：`/Game/UI/Font/AcesSleipnir-Regular_HUD_OFFLINE`。当前原 351 字形保留，新增 882 个字形。
- 新汉字来源为本地游戏资源中的 `NotoSansSC-SemiBold`，SIL OFL 1.1；版权声明和许可证见 `LICENSE-Noto.txt`。

不修改原游戏 EXE 或原始资源容器。运行时只在匹配版本的两份原生文字表中修改现有字符串缓冲区，拒绝原文不符或容量不足的词条；HUD 字体作为独立资源容器加载。

## 开发依赖与目录

Windows x64、Node.js（本次使用 24）、Python 3、Pillow、fontTools、Windows PowerShell 5.1。安装器通过系统内置 CSharpCodeProvider 编译为 x64 Windows 子系统 EXE；玩家不需要编译器或独立 .NET SDK。

| 依赖 | 放置位置 | 版本 / 校验 |
| --- | --- | --- |
| [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) | `tools/ue4ss-package/dwmapi.dll` 与 `tools/ue4ss-package/ue4ss/` | v3.0.1-1164-g5e627997，保留 LICENSE |
| [AC8OverrideLoader](https://github.com/JustMonika24769/AC8OverrideLoader) | `tools/ac8-override-loader/main.dll` 和 LICENSE | 0.2.0，SHA-256 `225c8d6c3fbf5e8882cb8e334dbd3426cb24a1415b3585073cc4264ae834f851` |
| [retoc](https://github.com/trumank/retoc) | `tools/retoc/retoc.exe` | 本次 0.1.5，支持 UE5_4 |
| 上游 AC8OverrideToolkit 与 Mappings.usmap | `tools/ac8-override-toolkit/` | 工具 EXE SHA-256 `2a5677032f31fa4437f3ad401007a42c2d9ac070faab5628610a3b715df466ff` |

工具与原始游戏资源不入 Git。提取游戏资源需要你合法取得的游戏与相应解压依赖；本仓库不分发原始游戏文件、Oodle 或扫描工具。具体提取步骤可参考上游 Toolkit 文档。其独立 Loader 当前只有二进制和文档，不宣称已审阅其实现源码。

## 准备本地资源

1. 将上述三份原始 DAT 提取到 `work/extracted/Live/Content/Localization/GameData/`。不要将该目录提交 Git。
2. 将 HUD 离线字体和 `NotoSansSC-SemiBold` 字体资源以 Legacy `.uasset/.uexp` 形式导出，保留资源路径。可使用 retoc 的 `to-legacy --filter /UI/Font/ --no-shaders --no-script-objects`，并依上游文档配置合法取得的解压依赖。
3. 运行 `python scripts/extract-asset-api.py`，从固定 Toolkit 包提取 UAssetAPI、Newtonsoft.Json 和 ZstdSharp 到 `tools/asset-api/`。
4. 使用 `scripts/asset-json.ps1 export` 将两份原始字体导出为 `work/offline-font.json` 和 `work/noto-font.json`。映射固定使用 `tools/ac8-override-toolkit/Mappings.usmap`。

## 构建顺序

以下示例在项目根目录执行，游戏路径按自己的安装位置填写。Python 的 Pillow、fontTools 放在 Python 环境或 `tools/python-native/`。

```powershell
node scripts/audit-text.mjs
node scripts/build-mod.mjs
python scripts/audit-simplified.py
python scripts/build-hud-font.py

$fontAsset = 'dist/hud-font-staging/Live/Content/UI/Font/AcesSleipnir-Regular_HUD_OFFLINE.uasset'
./scripts/asset-json.ps1 import work/offline-font-zh.json $fontAsset
./scripts/asset-json.ps1 export $fontAsset work/offline-font-zh-readback.json
node scripts/package-hud-font.mjs '你的游戏根目录'
node scripts/build-installer.mjs
```

输出为 `dist/AC8简体汉化/`，含 EXE、后台脚本、预编译文字表辅助 DLL、字体容器、加载运行时、使用说明与许可证。`package-manifest.json` 记录每个分发文件的大小及 SHA-256。所有 `.ps1` 带 UTF-8 BOM，以兼容系统 PowerShell 5.1 中的中文字符串。

## 测试与发布

```powershell
./scripts/test-installer.ps1 -GameDir '你的游戏根目录'
./scripts/test-updater.ps1
./scripts/package-release.ps1
```

安装测试将受支持 EXE 作为不执行的版本校验样本复制到独立 `work/` 夹具，模拟 Steam 配置，仅测试安装和卸载；不会启动复制的游戏或修改真实 Steam 配置。更新测试同样只操作独立夹具。

实机测试须另行进行，并记录文字表回读与目视检查。最新词条未目视确认前，不将其标为完整覆盖。发布 ZIP 的根目录应直接包含安装器；不要再套一层目录。发布正式 `vX.Y.Z` 标签，同时上传 `AC8-Chinese-Mod-vX.Y.Z.zip` 与 `.zip.sha256`，供安装器校验 GitHub 返回的 asset digest。

版本升级需同步 Setup.cs 的程序集 / 界面版本、build-installer.mjs 的 manifest 版本、使用说明和更新日志。启动入口、安装器与对应源码应作为同一版本发布。

旧 `Launch-Offline-Test.ps1` 和 Lua 诊断保留为开发历史，不用于玩家安装。当前发行版停用 Lua 文本轮询与 Frida。
