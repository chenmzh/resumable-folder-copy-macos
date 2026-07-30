# Resumable Folder Copy for macOS

一个原生 macOS 文件夹复制工具，适合服务器挂载盘、外接硬盘和包含大量小文件的数据集。

## 功能

- 原生 AppKit GUI，无第三方 GUI 依赖
- 一次选择多个源文件夹，也可以分批追加或移除
- 每个源文件夹复制到目标目录下的同名子目录
- rsync 断点续传，未完成文件保存在目标端
- 显示当前任务、百分比、速度和预计剩余时间
- 支持暂停、继续、日志查看和逐内容 checksum 校验
- 自动记住上次选择的源目录和目标目录
- 防止同名目标冲突和递归复制
- Universal Binary：支持 Apple Silicon 与 Intel Mac

## 下载与安装

从 [Releases](https://github.com/chenmzh/resumable-folder-copy-macos/releases/latest) 下载最新的 `Resumable-Folder-Copy-*.zip`，解压后打开 `断点续传复制.app`。

这是一个开源、adhoc 签名但未经过 Apple 公证的 app。首次打开时如被 Gatekeeper 阻止，请在 Finder 中右键 app，选择“打开”。

为了获得总体进度和 ETA，建议安装 rsync 3：

```bash
brew install rsync
```

如果没有 rsync 3，app 会回退到 macOS 自带 rsync，复制与断点续传仍可使用，但总体 ETA 不可用。

## 使用

1. 点击“选择源文件夹…”；文件选择器支持多选。
2. 点击“选择目标…”，选择一个目标目录。
3. 点击“开始 / 继续”。
4. 暂停、断网、关闭 app 或重启后，再次点击“开始 / 继续”即可补齐。
5. 复制结束后可运行“慢速校验”，逐文件读取两端内容并比较 checksum。

app 不会删除目标目录中的额外文件，也不会使用破坏性的同步选项。

## 从源码构建

需要 macOS Command Line Tools：

```bash
./scripts/build.sh
```

产物位于 `build/断点续传复制.app`，同时生成 Universal ZIP。

## License

MIT
