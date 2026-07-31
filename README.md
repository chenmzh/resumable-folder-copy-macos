# Resumable Folder Copy for macOS

一个原生 macOS 文件夹复制工具，适合服务器挂载盘、外接硬盘和包含大量小文件的数据集。

## 功能

- 原生 AppKit GUI，无第三方 GUI 依赖
- 一次选择多个源文件夹，也可以分批追加或移除
- 每个源文件夹复制到目标目录下的同名子目录
- rsync 断点续传，未完成文件保存在目标端
- 显示当前任务、百分比、速度和预计剩余时间
- 复制前精确扫描待复制文件，显示“需要 / 可用 / 安全余量”红黄绿容量条；空间不足时阻止启动
- 支持暂停、继续、日志查看和逐内容 checksum 校验
- “记住上次任务”开关；默认关闭，因此每次启动时源目录和目标目录为空
- 默认英文，并可在运行时切换中文、德语、法语、意大利语、西班牙语、葡萄牙语、日语、韩语和阿拉伯语
- 防止同名目标冲突和递归复制
- Universal Binary：支持 Apple Silicon 与 Intel Mac

## 下载与安装

从 [Releases](https://github.com/chenmzh/resumable-folder-copy-macos/releases/latest) 下载最新的 `Resumable-Folder-Copy-*.zip`，解压后打开 `Resumable Folder Copy.app`。

这是一个开源、adhoc 签名但未经过 Apple 公证的 app。首次打开时如被 Gatekeeper 阻止，请在 Finder 中右键 app，选择“打开”。

为了获得总体进度和 ETA，建议安装 rsync 3：

```bash
brew install rsync
```

如果没有 rsync 3，app 会回退到 macOS 自带 rsync，复制与断点续传仍可使用，但总体 ETA 不可用。

## 使用

1. 点击“选择源文件夹…”；文件选择器支持多选。
2. 点击“选择目标…”，选择一个目标目录。
3. 可先点击“检查空间”查看容量图；直接点击“开始 / 继续”也会自动检查。
4. 暂停、断网、关闭 app 或重启后，再次点击“开始 / 继续”即可补齐。
5. 复制结束后可运行“慢速校验”，逐文件读取两端内容并比较 checksum。

app 不会删除目标目录中的额外文件，也不会使用破坏性的同步选项。

空间预检使用与正式复制相同的 rsync 快速判断来建立待复制清单，并按文件替换期间临时文件所需的峰值空间计算。安全余量为所需空间的 5%，最低 5 GB；绿色表示连同余量都足够，黄色表示数据放得下但余量较小，红色表示空间不足且不会开始复制。

## 从源码构建

需要 macOS Command Line Tools：

```bash
./scripts/build.sh
```

产物位于 `build/Resumable Folder Copy.app`，同时生成 Universal ZIP。

## License

MIT
