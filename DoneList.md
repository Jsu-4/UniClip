# UniClip 个人 ADB 修复维护记录

更新：2026-11-01（Asia/Shanghai）。本文件在个人分支，未放入上游 PR。

## 仓库、提交与唯一源码目录

- 移动端上游：https://github.com/UniClipboard/UniClip ，目标 `main`。
- 我的 Fork：https://github.com/Jsu-4/UniClip 。桌面端 UniClipboard 不在本次修改范围。
- 本机源码：`/Users/jw/Code/tools/UniClip`。`upstream` 指向作者，`origin` 指向个人 Fork。
- PR：https://github.com/UniClipboard/UniClip/pull/109 。提交 PR 不等于作者已接受。
- 最新移植基线：`168972ae0f35755e89e3e7dc8889297aace13f06`，版本 `2.4.0.198-alpha.1`。
- PR 分支：`fix/android-adb-monitor-recovery`；修复提交：`b7fab3c585cd29d0daa7d3f5acff3c67b2010493`。
- 日常个人分支：`personal/android-adb-fix`，在修复上增加本记录和构建入口。
- 历史 APK 基线：`fcf68bfe917fc7a12a3c0696ac90b5463ae0b724`，`2.3.0.195`。
  历史源码分支 `personal/adb-fix-2.3.0.195`，修复提交 `6caf3655`，标签 `personal-adb-fix-2.3.0.195`。
  已逐字节确认其所有改动的产品和测试文件与原 APK 构建源码一致。

## 相对上游修复了什么

| 问题及根因 | 改动位置与行为 | 回归保护 |
| --- | --- | --- |
| logcat 退出后仍用布尔值报告监听中，无法重新启动 | `modules/clipboard-overlay/android/src/main/java/expo/modules/clipboardoverlay/ClipboardLogMonitor.kt`：按 generation 管理进程和线程；真实健康状态；故障后仅重试 1/5/15 秒；明确拒绝访问立即停止；取消和迟到旧进程不能影响新监听 | `ClipboardLogMonitorTest.kt` 六项原生测试 |
| 旧 stop、新 start、前台恢复交错 | `src/utils/androidBackgroundClipboardAccess.ts`：串行化操作、订阅归属和前台恢复 | `androidBackgroundClipboardModes.test.ts` |
| 监听失败静默转为每秒轮询 | `src/features/clipboard/internal/clipboardMonitor.ts`：ADB 事件模式保持事件策略，停止后的迟到启动清理订阅 | `ClipboardMonitor.adbRecovery.test.ts` |
| 重新开启或恢复后台同步后未重建监听 | `src/screens/settings/android/BackgroundSection.tsx`：明确恢复监听 | `BackgroundSection.adbHealth.test.tsx` |
| 权限就绪误当监听健康，读取失败难诊断 | 原生模块、TS 接口、适配器和设置页：区分权限/等待事件/实际读取/失败，复用整行重启控件，四种已有语言同步更新 | 设置页回归测试和验收文档 |

未改同步协议、持久化格式、Mac 端、默认中继或前台服务临时暂停触发逻辑；不增加 Root/Shizuku 要求。
诊断不保留剪贴板载荷；stderr 最多 512 字符。健康监听阻塞等待事件，故障重试不是剪贴板轮询。

## 验证与边界

- 最新移植工作区：237 个 Jest 套件、1,968 项测试通过；类型检查、改动文件 ESLint、`git diff --check` 通过。
- 原生目标：`:clipboard-overlay:testDebugUnitTest --rerun-tasks --no-build-cache --no-daemon`，6 项通过，73 项构建任务实际执行。
  Gradle 配置使用历史 Engine AAR；仅验证 clipboard-overlay 编译和测试，不证明新 Engine 或完整 APK 构建成功。
- 历史 `2.3.0.195` Release ARM64 APK 已构建且签名、内置 bundle、Engine 载荷检查通过；证据在本机 `.personal/history/验证记录.json`。
- 当前最新 main 的 Engine pin 是 `357d7f64006789285fe5bfc4f025992bc9b84e5f`；尚未完成它的完整 APK 构建。
  历史 Engine pin 是 `f44ae136f76a05e642fc22e32b823161f0716cef`，不能偷换给新版使用。
- 荣耀真机后台复制至 Mac、锁屏、长时间待机、两端重启尚未验收。自动“临时停止”仍未完成根因定位，不得宣传为已修复。
- Android 一次性日志访问同意、厂商杀后台和重启通知恢复机制仍存在，不能保证永久免操作。

## 本机历史产物与签名

`.personal/` 由 `.git/info/exclude` 排除，不上传。新克隆要主动恢复这些本机资产。

- `.personal/history/UniClip-2.3.0.195-ADB-Fix-Test-arm64.apk`，SHA256：
  `ed32ce3f486526401269124769a47c739d8ce882ed5ea844bbb57d8da8ceec1b`。
- `.personal/history/engine-dist/` 是历史 Engine AAR、源码提交、checksum 和绑定，限历史基线重建使用。
- `.personal/signing/adb-fix-test.keystore` 是旧测试 APK 使用的签名，已独立于生成的 android 目录保存，权限 600。
  这是测试签名（alias `androiddebugkey`，密码 `android`），不是正式发布密钥；私钥不能上传。
  请将此文件另做私人备份，否则换电脑后无法保证同一测试 App 覆盖升级。
- 个人 APK 身份：`UniClip Test`，`app.uniclipboard.android.test`，ARM64；不覆盖官方应用。
  新版必须沿用同一签名和包名，versionCode 不降低；不能靠卸载解决签名问题，以免丢数据。

## 构建与安装

当前分支提供 `bash personal-maintenance/build-apk.sh`。它没有在本次完成端到端运行，不能把脚本存在视为构建成功。
前置：Node >=22.22.1 <23、JDK 17、Android SDK（platform 36/build tools、NDK 27.1.12297006）、
可联网的 Cargo/rustup/Engine 构建工具链；更精确要求以当前上游 Engine 构建脚本为准。
本机现有 Node 位于 `/Users/jw/.hermes/node/bin`，SDK 位于 `/opt/homebrew/share/android-commandlinetools`，
JDK 位于 `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`。

脚本会安装锁定依赖、构建 workspace 模块、准备并验证当前 Engine pin、以 `APP_VARIANT=test` 生成 Android 工程，
恢复原测试签名并构建 ARM64 Release。不要在新版跳过 Engine pin 校验，也不要使用旧 native 工程覆盖新工程。
产物在 `.personal/apk/`；交付前用 SDK `apksigner verify --print-certs` 和 `aapt dump badging` 检查签名、包名、版本、ABI。

安装属于后续真机验收：先确认正确手机，再用 `adb -s <device> install -r <apk>`，不卸载、不清数据。
测试版需单独授予 `android.permission.READ_LOGS`，允许悬浮窗/通知，并与 Mac 配对。
荣耀允许自启动、关联启动和后台活动，关闭针对该测试版的电池优化。只按 Home 后复制普通测试文字，
不打开 UniClip、不点手动同步，确认 Mac 自动收到；再测锁屏、切网、长待机、重启。
授权后关闭无线调试，正常同步不依赖持续 ADB 连接。

## 作者升级后如何继续（给以后接手的人或 AI）

1. 先检查当前目录、Git 状态和本文件，不覆盖用户未提交修改；只在此目录管理分支，不复制新源码树。
2. `git fetch upstream --tags`，记录当时 `upstream/main` SHA 和 release 版本，读取当时 AGENTS、构建说明和 Engine pin。
3. 检查 PR 是否合并，再检查代码和测试是否已覆盖上述问题；不能仅依据版本号、PR 标题或 DoneList 判定。
4. 从最新 main 创建新的个人升级分支。对照 `git show b7fab3c5` 与测试逐项迁移仍缺失的行为；若已由上游解决则不重复套补丁。
   结构变化时重新实现同等行为，不能直接拿旧文件覆盖新版。个人构建入口和记录按需从个人分支迁入。
5. 使用新版自己的 Engine pin 和依赖，修复真实冲突；跑 Jest、类型检查、lint、原生回归及完整 ARM64 APK 构建。
6. 沿用本机签名和 test 包名，确认 versionCode、安装升级和用户数据兼容，再在同一荣耀手机完成上述验收。
7. 更新本文件的基线、修复提交、Engine、APK checksum、验证结果与未完成项，提交推送 Fork；个人记录不混入上游 PR。

未来接手请求示例：“请读取 /Users/jw/Code/tools/UniClip/DoneList.md 和 Git 修复提交，在作者最新代码上检查哪些修复仍需要，适配并构建同一签名、同一测试包名的 ARM64 APK，保留手机数据；通过真实验证后再交付。”
