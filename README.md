# SnapLink — 尼康相机无线互联、取景监看与水印工坊

<p align="center">
  <img src="assets/icons/snaplink_logo.svg" width="128" height="128" alt="SnapLink Logo" />
</p>

<p align="center">
  <b>专为尼康 (Nikon) Z 系列微单与 D 系列单反打造的移动端专业互联工具</b><br>
  <i>纯 Dart PTP/IP 协议栈 · 实时取景监看 · 分块高速下载 · 边拍边传 · 水印工坊与直出调色 · 浅色/深色双主题</i>
</p>

---

## 项目简介

SnapLink 是一款使用 Flutter 编写的开源摄影助手应用，解决的是一类很具体的问题：拍完照片想尽快把片子从相机传到手机、在手机上监看相机取景、并且给照片快速加上一行像样的参数水印——而不想依赖厂商 App 的账号体系、云服务和臃肿功能。

项目自带一套从零实现的 **纯 Dart PTP/IP 协议栈**，直接通过 TCP 双通道（Command + Event）与相机通信，不依赖任何原生桥接或第三方 SDK。界面提供 **深色（尼康金 + 暗黑）** 与 **浅色（暖白 + 琥珀黄）** 两套主题，并支持跟随系统自动切换；底部五个核心页面覆盖了从连接相机到出图的完整工作流：

| 页面 | 说明 |
|------|------|
| 连接 | Wi-Fi 直连（PTP/IP，已验证）/ USB OTG（浏览与下载）/ 蓝牙（规划中） |
| 监看取景 | 实时 LiveView 画面、直方图、曝光参数遥控、快门触发 |
| 相机相册 | 浏览相机存储卡，批量下载 JPG / RAW 并归档到手机相册 |
| 水印工坊 | 画廊卡片水印模板 + 品牌胶片滤镜直出调色，所见即所得 |
| 设置 | 分级设置菜单（外观、网络、传输、取景、电池、诊断、关于） |

---

## 界面预览

以下截图分别来自浅色与深色两套主题下的实际运行界面。

### 连接

加入相机释放的 Wi-Fi 热点（如 `NIKON_...`）后一键建立 PTP/IP 连接；亦支持 USB OTG 有线连接用于浏览存储卡与下载。蓝牙遥控（Nikon LSS）仍在开发中。

<p align="center"><img src="static/连接.jpg" width="280" alt="连接页面" /></p>

### 监看取景

无线实时取景画面，顶部显示帧率、时长与电量，附 RGB 直方图；下方提供快门 / 光圈 / ISO / 白平衡等参数遥控栅格，以及斑马纹、LUT、伪色彩、峰值辅助、网格线等监看辅助开关，支持远程触发快门。

<p align="center"><img src="static/查看取景.jpg" width="280" alt="监看取景页面" /></p>

### 相机相册

浏览相机存储卡内的照片（JPG 与 NEF 原始 RAW 均可），批量导出到手机相册 `/DCIM/SnapLink`，每张照片带「已导出」标记与 JPG / RAW 类型、文件大小，避免重复下载。竖拍照片自动按 EXIF 方向转正显示，缩略图完整不裁切。

<p align="center"><img src="static/相机相册.jpg" width="280" alt="相机相册页面" /></p>

### 水印工坊

内置多款画廊卡片式水印模板（纯调色无水印、参数入画、高斯虚化立牌等），可调节边框缩放、字体、边框颜色、拍摄时间等细节。预览窗口按照片比例自适应、无黑边与模糊底，并支持 **旋转 90°** 与 **水平镜像**，竖拍照片可一键转正后导出。

<p align="center"><img src="static/水印工坊.jpg" width="280" alt="水印工坊页面" /></p>

### 直出调色

「直出胶片调色」标签页把预设按品牌分组：**富士胶片、柯达胶片、理光人文、索尼大师**，每组再分「胶片模拟」与「经典胶卷」两类，点选卡片即可套用（如 PROVIA 标准、Velvia 鲜艳、ASTIA 柔和、经典正片、Classic Neg、Nostalgic Neg），并可继续微调曝光、对比、色温等参数，与水印模板组合导出。

<p align="center"><img src="static/直出调色.jpg" width="280" alt="直出调色页面" /></p>

### 设置

设置页已重构为 **一级分类菜单 → 二级详情页**：外观与显示（跟随系统 / 浅色 / 深色）、相机连接（默认 IP、PTP/IP 端口、快捷预设、网卡绑定）、无线与传输（后台保活、边拍边传 RAW）、取景与拍摄（默认帧率、取景协议、变焦手势）、电池与传输保护（低电量阈值与恢复）、诊断与日志、关于与更新。所有选项即时生效并持久化，重启后保留。

<p align="center"><img src="static/设置.jpg" width="280" alt="设置页面" /></p>

---

## 核心功能

### 连接与协议

- 纯 Dart 实现的 PTP/IP 客户端，管理 Command / Event 双 TCP 套接字与心跳保活，无需原生桥接。
- 支持 Wi-Fi 直连（相机热点，PTP/IP）与 USB OTG（PTP over USB，首期支持连接、浏览与下载）两种接入方式；设置页内置尼康默认热点（`192.168.0.1`）与局域网 / WT 发射器（`192.168.1.1`）快捷预设。
- 蓝牙（Nikon LSS）遥控规划中：官方链路加密库为闭源实现，项目正以纯 Dart 复刻，待逐字节验证通过后开放（详见 `reverse_analysis/BLE_LSS_RE.md`）。
- 可配置 PTP/IP 通信端口（默认 `15740`）、心跳间隔（默认 15 秒，防止相机自动休眠）、Android 进程网卡强绑定等底层网络选项。
- 内置协议诊断模块，记录握手与通信日志，便于排查机型兼容问题。

### 实时取景 (LiveView)

- 通过尼康私有扩展操作码 `0x9201` 开启取景、`0x9428` 高速拉取 JPEG 帧，对旧机型自动回退 `0x9203` 协议。
- 监看 HUD：RGB 直方图、三分构图网格、中央对焦准心、安全框、斑马纹过曝预警、峰值辅助对焦、伪色彩与 LUT 预览。
- 遥控曝光参数：拍摄模式、快门、光圈、ISO、白平衡、曝光补偿、对焦模式、测光方式，并支持远程触发快门与数字变焦（1x / 2x / 4x）。
- 实时显示帧率、连接时长与相机电量。

### 传输

- 分块流式下载：调用 PTP `GetPartialObject (0x101B)` 按 4MB 分块拉取，高像素大图与 NEF 原始文件均可断点续传式下载。
- 边拍边传：监听相机 `ObjectAdded (0x4002)` 事件，拍摄后自动同步到手机相册，可选是否同步 RAW 格式。
- 导出历史管理：记录每张已导出文件与目标路径，相册页直接展示 JPG / RAW 标记与文件大小。

### 水印与调色

- 十余种画廊卡片式水印模板：电影宽幅遮幅、米白卡纸、圆角白卡、玻璃铭牌、背景高斯虚化立牌、沉浸单行参数等，支持边框缩放、字体（默认 / 衬线 / 等宽 / 窄体）、边框配色与拍摄时间展示开关。
- 参数自动填充：从 EXIF 提取机身型号、镜头、光圈、快门、ISO，一键排入水印。
- 直出调色引擎：基于 Adobe Lightroom 核心算法计算 4x5 色彩矩阵，胶片预设按品牌分组（富士胶片、柯达胶片、理光人文、索尼大师，含胶片模拟与经典胶卷两类），叠加曝光、对比、高光、阴影、色温、色调、饱和度、锐化、暗角、颗粒等完整参数微调，可组合水印模板一并导出。
- 导出时完整回写 EXIF 元数据并修正方向，画质无损。

---

## 技术实现

```
snaplink/
├── assets/icons/                  # 应用图标（SVG / PNG）
├── static/                        # README 使用的界面截图
├── lib/
│   ├── main.dart                  # 入口与全局配置
│   ├── core/
│   │   ├── constants/             # 色彩常量、网络配置、PTP 操作码（含尼康私有码）
│   │   ├── theme/                 # 深色/浅色双主题与语义色调色板
│   │   └── utils/                 # 小端字节流读写、EXIF 解析、日志管理
│   ├── protocol/                  # 协议层
│   │   ├── ptp_packet.dart        # PTP/IP 封包拆包
│   │   ├── ptp_ip_client.dart     # 双 Socket 客户端与心跳保活
│   │   ├── camera_driver.dart     # 相机驱动抽象接口
│   │   ├── nikon_driver.dart      # 尼康专属驱动（LiveView / 调参 / 下载）
│   │   ├── nikon_ble_lss.dart     # 蓝牙 LSS（规划中）
│   │   ├── nikon_liveview_parser.dart  # LiveView 帧解析
│   │   ├── usb_ptp_transport.dart # USB (PTP over OTG) 传输层
│   │   └── camera_native_bridge.dart    # 平台通道桥接（USB / 蓝牙 / 电量等）
│   ├── engine/                    # 业务引擎
│   │   ├── liveview/              # 拉流循环、帧率调节、监看叠加层
│   │   ├── transfer/              # 分块下载、边拍边传、导出历史
│   │   ├── watermark/             # 模板定义、Canvas 排版、高清导出与 EXIF 回写
│   │   └── filter/                # 4x5 色彩矩阵调色引擎与胶片预设
│   └── ui/                        # 界面层
│       ├── screens/               # 连接 / 取景 / 相册 / 水印 / 设置 五个页面
│       ├── widgets/               # 通用组件、状态栏、直方图
│       └── root_scaffold.dart     # 底部导航容器
└── test/                          # 协议、水印、布局等单元测试
```

分层思路：`protocol` 只负责字节与连接，`engine` 只负责业务流程，`ui` 只负责展示与交互，三者通过相机驱动接口解耦，方便后续扩展新机型或新传输通道。

---

## 运行与构建

环境要求：Flutter 3.10+ / Dart 3.0+

```bash
cd snaplink
flutter pub get
flutter run          # 连接 Android / iOS 设备运行
```

构建 Android Release APK：

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

需要更小的安装包时，可只构建 ARM64 架构；功能不变，但不适用于 32 位 ARM 或 x86 设备：

```bash
flutter build apk --release --split-per-abi --target-platform android-arm64 --split-debug-info=build/symbols/1.3.0-arm64
# 产物：build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
# 发布时命名为 SnapLink-release-<版本号>-arm64-v8a.apk
```

`--split-debug-info` 将 Dart 调试符号保留在构建目录而非安装包内；该目录需与对应 APK 一起归档，用于之后解析崩溃堆栈，不随应用安装。

调试包包含调试引擎与调试代码，不作为日常安装包。Flutter 的正式构建已启用代码、资源及图标裁剪，无需重复配置。
Gradle 已配置 `force-version-code-ignoring-abi=true`，单架构包继续使用 `1.3.0+4` 的 versionCode，不会跳到 2004 而破坏后续覆盖升级。真正的 ABI 拆分会过滤依赖携带的其他架构库，避免单架构包在不支持的手机上被误安装。目前应用内更新选择发行页的首个 APK，尚未按设备架构筛选，因此更新源仅上传原文件名的通用包及 SHA-256 校验文件；ARM64 包作为独立的手动下载选项，不混放在同一发行页的 APK 资产中。

当前发布版本 **v1.3.0（versionCode 4）** 的产物命名约定：

```text
SnapLink-release-1.3.0.apk
SnapLink-release-1.3.0.apk.sha256   # 内容：<sha256>  SnapLink-release-1.3.0.apk
```

Windows 非 ASCII 路径（如 `D:\\程序\\...`）会导致 release AOT 失败，推荐复制到纯 ASCII 目录后构建：

```powershell
robocopy . D:\snaplink_ascii /E /XD build .dart_tool .git
cd D:\snaplink_ascii
flutter build apk --release
```

### Release 签名配置

默认情况下会回退到 debug 签名（仅供本地调试）。正式发布前请生成自己的 keystore：

```bash
keytool -genkey -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp android/key.properties.example android/key.properties   # 再填入真实密码与路径
```

`android/key.properties` 与 `*.jks` 已被 `.gitignore` 忽略，切勿提交。

### 应用内更新校验

发布新版本时，请一并上传 `SnapLink-release-<版本号>.apk.sha256`（内容为 APK 的 SHA-256）。
应用内更新会读取该文件并在安装前校验安装包完整性，校验失败将拒绝安装。

运行单元测试：

```bash
flutter test
```

使用步骤：

1. 打开相机的 Wi-Fi（网络菜单 → 启动无线连接），手机加入相机释放的热点。
2. 打开 SnapLink，在「连接」页点击「连接相机」。
3. 连接成功后即可使用取景监看、相册下载、水印导出等功能。

---

## 兼容性说明

- 机型：面向尼康 Z 系列微单与 D 系列单反，协议层对新旧 LiveView 操作码做了自动回退，具体机型欢迎实测反馈。
- 平台：以 Android 为主要目标平台（已验证），iOS / 桌面端理论可编译但未完整验证。
- 当前版本：**v1.3.0**（versionCode 4）。
- v1.3.0 更新要点：新增全屏“图像编辑”能力（旋转、水平/垂直翻转、透视校正、扭曲四角拖拽、自由变换、自由裁切 + 1:1/4:3/3:2/16:9 预设），导出图片查看器新增「编辑」按钮，水印工坊新增「图像编辑」Tab；保存时可选「覆盖」或「另存」，已导出分类用角标区分。
- 相机相册多选模式新增删除功能，可选“仅删除本地”或“本地 + 相机一起删除”，执行前二次确认并支持“不再提示”；相机删除走标准 PTP `DeleteObject (0x100B)`，Wi-Fi 与 USB 通道共用；本地删除优先走 Android MediaStore，删除失败会汇总提示并保留未完成的多选项。
- v1.3.0 修复：连接、相册筛选、同步操作、高清加载和更新界面适配浅色主题；已同步照片通过 MediaStore 优先读取本地原图。工坊图像编辑只使用上方预览，编辑参数自动参与水印、调色与导出；预览最长边 1024 像素，解码、几何变换和全尺寸编码在后台执行。覆盖原图前先备份，写入校验失败会恢复原图，安全恢复后才能回退另存。
- 编辑布局：工具栏固定在参数区上方，照片横竖变化或切换工具不改变下方面板高度；仅参数区可滚动，裁切比例等宽排列。透视校正采用当前显示方向，旋转、镜像后的水平/垂直轴保持一致，辅助网格仅用于预览、不写入成片。直方图去除顶部标题、拍摄参数与总重置按钮，仅保留图表及下方横轴、曝光分区。
- v1.2.0 更新要点：设置页改为一级分类菜单 + 二级详情页；新增跟随系统 / 浅色 / 深色外观（修复深色下部分控件残留浅色的问题）；水印与调色预览按照片比例自适应、支持旋转 90° 与水平镜像；相机相册竖拍照片按 EXIF 方向自动转正、缩略图填满不裁切；大图预览增加“前 35% 字节容错解码”的渐进首帧，缩短等待。
- 本项目为独立开发的第三方工具，与 Nikon 官方无关联、未使用其专有 SDK；「Nikon」「Z SERIES」等名称仅用于标识兼容机型。

---

## 1.3.0 回归验证

自动检查：`dart analyze`、`flutter test --no-pub`、`flutter build apk --debug --no-pub`。

以下项目仍为 **pending real-device verification**，自动化使用 fake driver / 原生桥接 mock，不代表相机或 Android 实机已通过：

1. 浅色主题：连接相机后检查连接卡片、相册筛选、照片详情与同步底栏、高清加载及更新弹窗，再切换深色和跟随系统。通过判据：普通页面背景、正文及按钮文字随主题变化，无白底白字或无关黑色面板。
2. 本地复用：同步 JPG 后重启应用、断开相机，再从已导出分类打开照片并进入调色、编辑。通过判据：能够读取本地高清照片，不要求重新连接相机或重新下载；RAW+JPG 不误取 RAW 作为 JPG。
3. 编辑：使用一张带 EXIF 方向的竖图，逐项检查旋转、翻转、透视、四角拖拽、缩放平移、裁切和撤销重做，再切换工坊 Tab 并导出。通过判据：仅一个编辑预览、固定裁切比例保持、操作结果实际改变画面，成片方向与最后一次预览一致；大尺寸 JPG 不阻塞主界面。
4. 保存：测试覆盖和另存，重启后确认相册条目及角标；对不可覆盖的来源测试回退另存。通过判据：另存保留原文件，覆盖失败有明确提示，安全恢复失败不得报告成功。恢复失败的原图备份保留在应用内部 `photo_backups` 目录。

## 开源许可

本项目采用 [MIT License](LICENSE) 开源，欢迎提交 Issue 与 Pull Request。
> [!NOTE]
> Windows 下若项目位于含中文等非 ASCII 字符的路径，`flutter build apk --release` 的 AOT
> `gen_snapshot` 步骤可能因路径编码问题失败（`Unable to read file: ...app.dill`）。
> 这是工具链限制，与本项目代码无关；请将项目放在纯 ASCII 路径（如 `D:\projects\snaplink`）后构建。
