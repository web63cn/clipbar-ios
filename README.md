# ClipBar iOS 版

桌面端 ClipBar 的 iOS 版本。**不上架，只自用。**

---

## 能做什么 / 不能做什么

iOS 有几条平台级的硬限制，不是技术问题，绕不过去：

| 桌面端能力 | iOS 上 | 说明 |
|---|---|---|
| 后台自动监听剪贴板 | ❌ | iOS 14+ 没有剪贴板变更通知，App 挂起后不会被唤醒。读取还会弹「XX 粘贴自 XX」的系统横幅 |
| 全局悬浮窗 | ❌ | 后台 App 不能盖在别的 App 上面 |
| 点记录自动粘贴到目标 App | ⚠️ 换了个方式 | iOS 没有全局钩子，改用**键盘扩展**：在输入框里从历史挑一条直接插到光标处，效果等价 |
| 历史列表 | ✅ | |
| 云端同步（与 Mac/Windows 互通） | ✅ | 协议完全一致，内容端到端加密 |
| 文本处理工具 | ✅ | 额外加的，iOS 上其实比剪贴板更实用 |

业内方案（Octoclip、UniClipboard）都撞同一面墙，只能用 PiP 小窗保持前台会话才能持续监听 —— 那个要单独做一个 target，本版没做。

### 实际形态

- **主 App**：看历史、手动读取剪贴板、云同步、文本工具
- **键盘扩展**：在任意输入框里，从历史挑一条直接插入

---

## 安装

### 前提

- 一台 iPhone，iOS 16 及以上（iOS 17 没问题）
- iPhone 开启**开发者模式**：设置 → 隐私与安全性 → 开发者模式 → 开启并重启
- 一个 Apple ID（**免费账号就行**，不用付费开发者）

### 步骤

**1. 拿到 IPA**

两个办法，选一个：

**A. GitHub Actions 远程编译（推荐，本机不用装 Xcode）**

把这个目录推到一个 GitHub 仓库，然后：

- 仓库 → **Actions** → 左侧选「构建 iOS IPA」→ 右上 **Run workflow**
- 等 2~3 分钟
- 页面底部 **Artifacts** 里下载 `clipbar-ipa`
- 解压得到 `ClipBar-unsigned.ipa`

> 公开仓库免费额度无限；私有仓库每月 2000 分钟 macOS runner，够用。

**B. 本机编译（需要完整 Xcode，10GB+）**

```bash
cd ClipBar-iOS
xcode-select -s /Applications/Xcode.app/Contents/Developer   # 指向完整 Xcode
./build.sh
```

产物在 `build/ClipBar-unsigned.ipa`。

**2. 签名安装**

下载 [Sideloadly](https://sideloadly.io)（macOS / Windows 都有，免费）：

1. 把 `ClipBar-unsigned.ipa` 拖进 Sideloadly 窗口
2. 左侧选你的 iPhone
3. 填 Apple ID（免费账号即可；开了双因素的会要验证码）
4. 点 **Start**
5. 等进度条走完

**3. 信任证书**

iPhone 上：**设置 → 通用 → VPN与设备管理** → 找到你的 Apple ID → **信任**

**4. 启用键盘扩展**

**设置 → 通用 → 键盘 → 键盘** → 右上「添加新键盘…」→ 选 **ClipBar**

回到任意输入框，长按左下角地球图标 → 选 ClipBar 键盘。

**5. 消除粘贴提示（可选）**

**设置 → 隐私与安全性 → 粘贴板** → 选 ClipBar → **完全允许**

否则每次读剪贴板都会弹「ClipBar 粘贴自 ClipBar」。

---

## 免费账号的三个限制

| 限制 | 影响 | 怎么办 |
|---|---|---|
| **7 天过期** | App 停止启动，要重装 | Sideloadly 有自动刷新守护进程，能在过期前自动重签 |
| **不支持 App Groups** | 主 App 和键盘扩展不能直接共享沙盒 | 已在代码里自动降级到「剪贴板桥」：两边通过系统剪贴板的自定义 UTI 中转数据。设置页会显示当前用的是哪种 |
| **同时最多 3 个 App** | 免费账号侧载数量限制 | 只装一个 ClipBar 没问题 |

**如果愿意花 99$/年**（Apple Developer Program）：

- 签名有效期 1 年，不用每周重装
- **App Groups 可用** → 共享机制自动切到 App Group，更干净（代码会自动检测）
- 其它限制也放宽

---

## 云同步

跟 Mac / Windows 端**同一套协议**，直接互通：

- 内容在**客户端加密**（AES-256-GCM）后才上传，服务器只存密文
- 群组密钥由服务端从主密钥派生，鉴权通过后下发，所有设备共用
- 密文格式 `nonce(12) || tag(16) || ciphertext`，与桌面端完全一致

在 iOS 端「设置 → 互联网同步」里填服务器地址（默认就是 `http://web63.cn/clip/clip.php`），打开开关。

**注意**：iOS 没有后台常驻能力，同步只在**切回 App 时**触发。要实时同步就手动点同步按钮。

---

## 工程结构

```
ClipBar-iOS/
├── ClipBar/                      主 App
│   ├── ClipBarApp.swift          入口 + TabView
│   ├── Core/
│   │   ├── ClipStore.swift       本地存储（50 条上限，fp 去重）
│   │   └── CloudSync.swift       云同步（群组密钥协议）
│   ├── Views/
│   │   ├── HistoryView.swift     历史列表
│   │   ├── TextToolsView.swift   文本工具
│   │   └── SettingsView.swift    设置
│   ├── Info.plist
│   └── ClipBar.entitlements      App Group（付费账号才生效）
│
├── ClipBarKeyboard/              键盘扩展
│   ├── KeyboardController.swift
│   └── Info.plist
│
├── Shared/                       两个 target 共用
│   ├── AES.swift                 AES-256-GCM（密文格式与桌面端一致）
│   ├── ClipItem.swift            数据模型 + 指纹算法
│   └── SharedStore.swift         共享机制（App Group / 剪贴板桥自动切换）
│
├── ClipBar.xcodeproj/            Xcode 工程
├── gen_xcodeproj.py              工程生成脚本（改文件名后重跑）
├── verify_pbxproj.py             工程完整性校验（不需要 Xcode）
├── build.sh                      一键编译
└── .github/workflows/ios-build.yml   远程编译
```

### 为什么工程文件是脚本生成的

手写 `project.pbxproj` 很容易把 ID 引用错，整个工程就打不开。
所以用 `gen_xcodeproj.py` 生成 —— 加文件、改名字只要重跑一次：

```bash
python3 gen_xcodeproj.py
python3 verify_pbxproj.py   # 校验引用完整性
```

---

## 常见问题

**Q：编译报「Signing for ClipBar requires a development team」**
A：命令行编译时脚本已关掉签名（`CODE_SIGNING_ALLOWED=NO`）。
如果在 Xcode 里手动编译，Xcode → Settings → Accounts 登录 Apple ID，
然后在 target 的 Signing 里选你的 Personal Team。

**Q：键盘里看不到历史**
A：两个可能 ——
① 主 App 还没打开过（历史是空的）；
② 免费账号下走剪贴板桥，主 App 打开时会发布历史，键盘再读。
切回主 App 一下再回键盘。

**Q：App 打开就闪退**
A：大概率是 7 天签名过期了，用 Sideloadly 重装。

**Q：能加回后台监听剪贴板吗**
A：能做，但要引入 PiP 监控小窗（Octoclip 的方案）——
用户手动开启一个 PiP 窗口保持 App 在前台，才能持续监听。
代价是 App 会在屏幕上留一个小窗，且读取仍有系统横幅提示。
需要的话可以另开一个 target 做。
