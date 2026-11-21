# FileGlance · Prototype

FileGlance 是一个 macOS 菜单栏工具。在访达或桌面上，把鼠标停在文件上约半秒，即可查看文件名、大小和预览。图片、PDF 首页和纯文本有内置预览，其他类型使用系统缩略图或文件图标。

## 安装

1. 从 GitHub Releases 下载 macOS ZIP，解压后把 `FileGlance.app` 拖入“应用程序”。
2. 打开应用，按提示在“隐私与安全性 → 辅助功能”中允许 FileGlance。
3. 在访达或桌面将鼠标停在一个文件上。菜单栏的眼睛图标可暂停或退出。

原型采用临时签名，尚未经过 Apple 公证。首次打开时可能需要在“隐私与安全性”中选择“仍要打开”。[Apple 官方说明](https://support.apple.com/zh-cn/102445)

构建目标为 Intel Mac 上的 macOS 10.15 起、Apple 芯片 Mac 上的 macOS 11 起。已验证应用签名、文件元数据读取及图片、PDF、文本预览。访达里的实际悬停仍待桌面环境验证。

## 从源码构建

在装有 Xcode 命令行工具和较新 macOS SDK 的 Mac 上运行 `./build.sh`。应用输出到 `build/FileGlance.app`。
