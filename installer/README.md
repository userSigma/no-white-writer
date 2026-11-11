# Windows 安装包（Inno Setup）

## 前置条件

- Windows x64、项目使用的 Flutter SDK、Visual Studio 的 Desktop development with C++ 工具链。
- Inno Setup 6.3 或更新的 6.x（需要 `x64compatible` 支持）。按用户安装的编译器也可发现，不必加入 PATH。
- Visual Studio Redistributable 目录中的 **x64** `Microsoft.VC*.CRT` DLL。打包命令自动发现，或用 `--runtime-dir` 指定；不要使用 System32 中的 DLL，不需要安装会请求管理员权限的 VC++ 运行库安装程序。

不新增 Flutter 运行时依赖。默认编译器搜索顺序：`--iscc` / `INNO_SETUP_COMPILER` → 当前用户安装目录 → Program Files → PATH。当前向导采用 Inno 默认英文，产品名称及关键安全提示含中文；不下载第三方语言包。

## 一条命令构建

在仓库根目录执行：

```powershell
dart run tool/build_windows_installer.dart
```

默认先运行 `flutter build windows --release`，再验证 x64 可执行文件、Flutter DLL、Dart 的 x64 ELF AOT 快照、ICU 和资源清单；将完整 Release 文件及应用本地 VC++ DLL 复制到新的构建暂存目录，再调用 ISCC。**不会向原始 Release 目录写入运行库，也不会更改脚本执行策略。**

版本只读取 [pubspec](<../pubspec.yaml>)：例如 `0.4.1+5` 显示为完整版本、Windows 资源版本为 `0.4.1.5`。安装脚本会核对主程序的资源版本，拒绝混入其他版本的构建。

默认输出：

```text
build/packages/no-white-writer-<版本（不含 +N）>-windows-x64-setup.exe
build/packages/no-white-writer-<版本（不含 +N）>-windows-x64-setup.exe.sha256
```

已有任一个同名文件就报错，不覆盖旧交付。可使用新的 `--output-dir`，正式新版本按项目发布规范更新版本号。

已经明确完成 Release 构建时（如 CI）可复用：

```powershell
dart run tool/build_windows_installer.dart --skip-build
# 自定义工具及输出路径：
dart run tool/build_windows_installer.dart --skip-build --iscc "C:\Tools\Inno Setup 6\ISCC.exe" --runtime-dir "C:\VS\VC\Redist\MSVC\14.xx.x\x64\Microsoft.VC143.CRT" --output-dir "D:\packages"
dart run tool/build_windows_installer.dart --help
```

`--source-dir` 用于显式复用其他 Release 目录，必须同时使用 `--skip-build`。只支持预先构建好的 Release，不支持 Profile。缺少资产/AOT 的 Debug、ARM64 或损坏输入会被拒绝；显式复用输入时仍须由调用者保证它来自 Release 构建。现有 ZIP 分发方式保留；安装包内额外包含本地 VC++ 运行库。

## 安装、升级与卸载

- 默认安装至 `%LOCALAPPDATA%\Programs\不白写作`；`PrivilegesRequired=lowest`，不请求 UAC。
- 创建当前用户的开始菜单入口；桌面快捷方式默认不勾选。安装后启动也需用户显式选择，静默安装绝不自动启动写作程序。
- 固定 AppId：`ce99ca45-fdcf-4d6f-8f1c-74f7dd3b086b`。后续版本复用原安装位置及同一卸载记录，不要更换此标识。
- 覆盖安装或卸载时，若已安装程序正运行或不可替换，安装器停止并要求用户**先保存、正常退出后重试**。不强杀进程，不自动重启应用，不干预运行期实例锁。
- 卸载只移除安装器登记的程序文件、快捷方式和卸载登记。**始终保留作品、设置、备份及导出文件，没有“删除我的作品”选项。** 数据默认位于 `%APPDATA%\不白写作`，自定义数据/导出目录同样不属于安装器清理范围。
- 文件保留不替代备份：升级前仍建议另行备份重要作品。

## 校验与分发

安装包未签名，首次运行可能有 SmartScreen 提示；这不是 UAC，也不代表已建立签名信誉。使用同一发布渠道的 `.sha256` 侧文件核对下载结果：

```powershell
Get-FileHash .\no-white-writer-0.4.1-windows-x64-setup.exe -Algorithm SHA256
Get-Content .\no-white-writer-0.4.1-windows-x64-setup.exe.sha256
```

不要直接分发本机带 Low integrity 标签的旧沙箱构建文件。将完成的安装包写入新的普通下载目录后校验哈希；不需更改 ACL 或降低数据目录权限。安装包本身是单个 EXE，安装后的应用仍需要整个安装目录中的 DLL 和 data 文件。

## CI 与验证边界

[CI](<../.github/workflows/ci.yml>) 的 Windows job 编译安装器并保存 setup/hash 供排查；[Release](<../.github/workflows/release.yml>) 在既有 `v*` 标签发布中额外上传安装器和校验文件，保留 ZIP。托管 runner 缺少编译器时用 Chocolatey 安装 Inno Setup。

本地配置/保留策略回归测试不依赖 Windows 编译器；真实安装测试必须使用另一个测试 AppId、临时安装目录并禁用快捷方式和自动启动，不得卸载已有正式安装。测试 AppId 的预处理器覆盖仅用于这种隔离验收；正常打包入口固定使用正式 AppId。

未执行的远端 Actions、干净机器/全 Windows 版本矩阵、签名和 SmartScreen 信誉，不应描述为已验证。实现入口见 [打包命令](<../tool/build_windows_installer.dart>)、[配置验证](<../tool/installer_config.dart>) 和 [Inno 脚本](<no_white_writer.iss>)。
