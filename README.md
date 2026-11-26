# NanoClip

轻量级 macOS 剪贴板历史工具。菜单栏常驻，无 Dock 图标；纯 AppKit + 系统 SQLite，零第三方依赖。

只保存**纯文本**和**图片**，永不记录文件。

## 特性

- **极低占用** — 无 SwiftUI、无 xib，面板关闭即释放视图与缩略图缓存。空闲内存约 16 MB（phys_footprint），CPU ≈ 0.2%。
- **双击 ⌥ 呼出** — 也可录制成任意组合键，不需要辅助功能或输入监控授权。
- **纯文本** — 富文本只取文字，写回剪贴板时只写 `public.utf8-plain-text`。
- **图片保持原格式** — PNG / JPEG / TIFF / HEIC 原样落盘，不压缩、不转码、不限大小；文件名即内容 SHA-256，天然去重。
- **不记录文件** — 含 `public.file-url` 的粘贴板内容一律跳过，连文件名也不入库。
- **分类与时间筛选** — 文本 / 链接 / 图片；今天 / 昨天 / 近 7 天 / 近 30 天。
- **隐私保护** — 默认忽略 1Password、Bitwarden、钥匙串等应用，识别 concealed / transient 类型。
- **只复制，不自动粘贴** — 不注入 ⌘V，因此不申请任何系统权限。

## 系统要求

macOS 14 Sonoma 或更高 · Xcode 命令行工具（Swift 6 工具链）

## 安装

```bash
git clone https://github.com/<owner>/NanoClip.git && cd NanoClip

./Scripts/build-app.sh   # release 构建 → 生成图标 → 打包 build/NanoClip.app → 签名
./Scripts/install.sh     # 复制到 /Applications 并启动
```

默认 ad-hoc 签名。如需稳定签名（推荐，避免每次构建后重新授权）：

```bash
SIGN_IDENTITY="NanoClip Local" ./Scripts/build-app.sh
```

> 登录项注册（`SMAppService`）要求 App 位于 `/Applications`；`swift run` 直接运行裸二进制时该功能不可用。

## 使用

```
复制内容 → 双击 ⌥ → ↑↓ 选择 → ↩（或单击行）→ ⌘V
```

| 操作 | 快捷键 |
| --- | --- |
| 呼出 / 关闭面板 | 双击 `⌥`（可改成任意组合键） |
| 选择 / 复制 | `↑` `↓` / `↩`（鼠标单击行等效） |
| 关闭 | `esc` |
| 删除当前条目 | `⌘⌫` |
| 偏好设置 | `⌘,` |
| 搜索 | 直接输入（输入法拼音阶段即可实时过滤） |

点击旧条目不会新增记录，只会把它移回列表最前。

命令行参数：

| 参数 | 作用 |
| --- | --- |
| `--show-history` | 启动即展开面板 |
| `--show-preferences` | 启动即打开偏好设置 |
| `--diagnostics` | 打印内存 / 条目数 / 登录项状态后退出 |

## 数据与隐私

```
~/Library/Application Support/NanoClip/
├─ history.sqlite3 (+ -wal / -shm)   # 元数据，WAL 模式
├─ images/<sha256>.<ext>             # 图片实体，内容寻址
└─ NanoClip.log                      # 追加式日志（>512 KB 自动截断）
```

- 数据只在本机明文保存：无云同步、无网络请求、不加密落盘。
- 日志只记录条目数量 / 类型 / 耗时，不记录剪贴板内容。

卸载：

```bash
osascript -e 'quit app "NanoClip"'
rm -rf /Applications/NanoClip.app ~/Library/Application\ Support/NanoClip
defaults delete com.jvz.nanoclip
```

## 开发

```bash
swift build                        # debug 构建
swift run NanoClip --show-history  # 直接运行，无 .app 外壳
./Scripts/build-app.sh             # release 打包 + ad-hoc 签名
```

```
Sources/
├─ NanoClipCore/   纯逻辑：Store / Capture / Paste / HotKey / Support
└─ NanoClip/       AppKit 外壳：App / UI / Support
Scripts/           构建安装脚本、Info.plist、图标生成
```

设计取舍：AppKit 而非 SwiftUI（更低的运行时基线）；`changeCount` 轮询采集（`NSPasteboard` 无变更通知）；Carbon 热键 + 修饰键状态轮询（无需任何系统权限）；内容寻址存图（无需去重表）。

## 已知限制

- 目前仅按 Apple Silicon（arm64）构建。
- 双击 ⌥ 依赖约 25 ms 的修饰键状态轮询，无法判断两次 ⌥ 之间是否按过其他键，极少数「⌥ + 字母」快速连打可能误触；可改用组合键。
- 不记录 Universal Clipboard 与 transient / auto-generated 类型内容。
- 不含 iCloud 同步、加密存储、自动更新、文件条目。

## 许可

[GNU General Public License v3.0](LICENSE)