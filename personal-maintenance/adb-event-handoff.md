# UniClip Android：ADB 事件后台复制不同步的修复交接

日期：2026-10-31。面向 UniClip 维护者，以及在移动端源码仓库中执行修复的 Codex。

## 1. 结论与使用方式

本次修复保留了原有 ADB 事件方案，修复的是**日志监听失效后无法恢复、状态显示失真，以及停止/启动交错**，并禁止 ADB 模式在失败时静默退回每秒轮询。

修改后的测试 APK 已完成构建、自动化测试和签名检查。交付后用户反馈“可以了”；这是用户使用反馈，本次没有另行采集修复后的完整真机日志，也没有完成重启、长时间待机及跨网络的系统性验收。

开发者可以阅读全文理解改动；也可以把全文交给拥有移动端源码工作区的 Codex，并要求：**“按本文第 4—8 节修复当前仓库，先验证并交付测试包，暂不安装手机。”**

配套文件 `UniClip-ADB-listener-fix.patch` 是本次实际实现，包含代码和回归测试。有补丁时优先检查其适用性；只有本文、没有补丁时，也可以按下述实现约束和验收标准重新实现。本文所有源码路径均相对于移动端仓库根目录，不依赖修复者的本地绝对路径。

开发者交接压缩包包含本文、补丁及构建校验记录；约 101 MB 的 APK 为单独交付，不在交接包内。

## 2. 版本、症状与证据边界

| 项目 | 本次环境／基线 |
| --- | --- |
| 移动端仓库 | https://github.com/UniClipboard/UniClip |
| 移动端版本 | `v2.3.0.195` |
| 起始提交 | `fcf68bfe917fc7a12a3c0696ac90b5463ae0b724` |
| 手机 | HONOR Magic8 Pro（BKQ-AN90），Android 17 / API 37 |
| 桌面端 | Mac UniClipboard 1.5.0 |
| 读取方式 | `overlay-event`，界面名称“ADB 事件” |
| 同步引擎 | 沿用原有固定提交 `f44ae136f76a05e642fc22e32b823161f0716cef` |

用户可观察到的症状：

1. 打开 UniClip 时能够读取并同步剪贴板。
2. 只按 Home 或切换到微信后复制普通文字，Mac 不自动收到。
3. 再打开一次 UniClip，才出现读取提示并完成同步。
4. 部分阶段“后台自动同步”显示临时停止；另一些阶段总开关仍开启，但复制事件不工作。两者不能当成同一个已完全解释的问题。

现场与源码确认的事实：

- 原版 `READ_LOGS` 已授予；存在后台服务运行但 `logcat` 子进程已不存在的现场。重新开启总开关没有恢复读取器。
- 同一轮测试的启动阶段，出现了 `logcat_trigger → 获得焦点 → triggered_read → emit`，证明原有事件链路能够执行。
- 随后的后台复制，ADB 能看见系统 `ClipboardService` 对该包的拒绝读取日志，但应用没有相应触发／读取记录。
- 有一轮后台检查中，服务和子进程仍存在但没有处理事件；随后前台对照时该子进程已经消失。因此不能把“进程存在”当成日志可读的充分证明，也不能把系统前后台策略断言为唯一根因。
- 原实现吞掉日志读取异常，结束时没有正确反映监听健康状态，也没有恢复机制。

**没有捕获到本机第一次日志读取器失效的退出原因。** 本次确认并修复了失效后的应用级处理缺陷，不宣称已经证明某一荣耀系统策略、网络中继或电池设置就是最初退出的唯一原因。

## 3. 原有机制为什么会出现这个症状

Android 10+ 上，该实现有两条采集路径：

```text
前台：系统剪贴板监听 → 直接读取 → onClipboardChange → JS 去重／上传

后台：系统复制相关日志 → 应用内 logcat 读取器匹配本包
    → 原有悬浮窗焦点读取 → onClipboardChange → JS 去重／上传
```

这里的 ADB 主要用于授予 `READ_LOGS`。运行时的 `logcat` 是手机应用自己启动的子进程，不是由 Mac 持续远程监听。因此修复不需要常驻 Mac ADB 连接，也不需要开启固定调试端口；网络传输继续由现有同步引擎负责。

原有缺口及其后果：

| 原有缺口 | 后果 | 本次处理 |
| --- | --- | --- |
| `startMonitorInternal()` 仅凭 `isMonitoring` 提前返回 | 读取器已退出，布尔值仍为真，再次启动也无法修复 | 按线程、进程和生命周期判断健康；健康时幂等，失效时允许重新启动 |
| 读取线程捕获异常后忽略；结束时只销毁子进程 | 故障没有退出诊断、状态通知或恢复动作 | 独立读取器负责人管理失败、有限重试和取消 |
| `startClipboardMonitor()` 原先无条件 resolve `true` | 内部没有实际启动时，JS 仍可能认为请求成功 | 返回实际启动入口的布尔结果；仍不把请求接受等同于后台读取成功 |
| 权限“已就绪”被当作监听正常 | 权限保留时，界面掩盖运行故障 | 分离权限、监听生命周期和实际读取结果 |
| 总开关不保证重建事件读取器 | 开关恢复了，采集端仍然失效 | 开启和恢复分支显式重启所选 ADB 监听 |
| 原生停止是异步的，JS 随即启动下一次监听 | 旧停止请求可能破坏新监听 | JS 串行化原生转换，原生用 generation 隔离会话 |
| 事件监听失败后走通用轮询回退 | 用户选 ADB 事件却可能产生 1000ms 剪贴板计时器 | 在轮询入口统一禁止 `overlay-event` 的静默回退 |

## 4. 给 Codex 的执行入口

请在当前 UniClip 移动端仓库实施上述修复，保留现有架构及数据、协议兼容性。

### 4.1 确定适用范围

1. 读取当前仓库的 `AGENTS.md`、相关说明和实际依赖版本。此基线使用 Expo 57、Node `>=22.22.1 <23`；较新分支按其自身配置和对应版本文档执行。
2. 保存当前提交和用户已有修改。先检查下面的缺陷是否仍存在；已经实现并通过相应测试的部分复用即可。
3. 有附件补丁时，在仓库根目录运行：

   ```sh
   git apply --check /path/to/UniClip-ADB-listener-fix.patch
   ```

   只有检查通过、且不会混入或覆盖用户修改时，才用 `git apply` 应用。较新分支出现冲突时按本文语义移植，不强行重置分支或覆盖文件。

4. 实施前先按第 7 节建立失败回归，至少证明“死读取器回前台不恢复”和“ADB 启动失败却创建轮询计时器”能被捕获。新增类尚不存在导致的导入失败不算真实故障复现；当前分支已经修复的行为可直接记录通过。

完成条件：明确当前版本受影响的入口、保留已有修改，具备有效回归用例，并选定直接应用或语义移植路径。

### 4.2 实现边界

- 继续使用事件驱动，正常运行时阻塞等待日志输入；用户选定 ADB 事件后，故障也不改成周期性读取剪贴板。
- 沿用原有悬浮窗读取、内容分类、去重、持久化和上传链路。
- 使用现有后台服务及设置组件；不引入第二套常驻服务或日志“探测器”。
- 保留现有轮询模式、Shizuku 模式、iOS 行为和 Android 10 以下的系统监听路径。
- 本次不修改同步引擎、网络中继、数据格式、配对协议、前台服务类型或开机接收器。
- 保留系统授权与日志访问确认；不引入 Root、Shizuku 依赖或持续无线 ADB。

## 5. 原生层：让日志读取器拥有完整生命周期

### 5.1 新增负责人 `ClipboardLogMonitor`

位置：`modules/clipboard-overlay/android/src/main/java/expo/modules/clipboardoverlay/ClipboardLogMonitor.kt`。

将进程、读取线程、失败预算、取消及状态统一放在这个内部类中。使用可注入的 `spawn: () -> Process`、重试延迟、触发和状态回调，以便通过真实线程与假进程构造确定性测试。

对外保持小接口：`start()`、`stop()`、`isActive()`、`getStatus()`。

状态及转换：

```text
stopped → starting → listening
                    └─ EOF／启动或读取异常 → retrying → starting
                       └─ 明确拒绝访问／预算耗尽 → failed
任意活动状态 ─ stop／替换会话 → 取消旧会话
failed／stopped ─ 显式启动 → 新 generation
```

必须实现的语义：

1. 每次新会话增加 `generation`，保存该会话的 worker、process 和取消标记；旧会话不能发布新会话的状态、触发新会话读取或销毁新进程。
2. `isActive()` 检查实际 worker。`listening` 还要检查子进程确实存活；`starting/retrying` 表示活跃的启动／恢复过程，不能冒充已经读到内容。
3. 健康会话的 `start()` 幂等；已结束的会话必须可以重新启动。保持 minSdk 兼容，不能无条件调用高于 minSdk 的进程 API。
4. 正常读循环用阻塞 `readLine()`。延续现有按时间启动的 `ClipboardService:E` 过滤与包名匹配，沿用去抖行为。
5. 初始启动之外，同一会话累计最多重试三次，延迟分别为 **1、5、15 秒**。仅在失败后等待；明确的 permission/access denied 直接进入 `failed`。成功读到一条事件不应把同一会话的故障预算无限重置。
6. EOF 也视为读取器结束，即使进程仍未退出；清理该进程、收集退出码及有界 stderr，再决定恢复或失败。
7. stderr 独立排空，最多保留 512 字符；系统日志正文和剪贴板载荷不保留。启动／读取异常应区分，禁止重新退化成静默吞错。
8. `stop()` 取消会话、销毁进程、打断 worker 并唤醒重试等待。停止期间退出的旧线程不能再次安排恢复；异步创建晚到的旧进程只能销毁自身。
9. 状态回调保持非阻塞。本次回调只投递到主线程，不在锁内执行耗时工作。

这里的 1000ms 去抖作用于已经收到的日志事件；1 秒恢复延迟仅发生在故障后。两者都不是每秒轮询剪贴板。

### 5.2 接入 `ClipboardOverlayModule`

文件：同目录下的 `ClipboardOverlayModule.kt`。

- 移除散落的旧 `logcatThread/logcatProcess/stopLogcat` 生命周期逻辑，改由 `ClipboardLogMonitor` 管理；系统剪贴板 listener 保持单次注册。
- `isMonitoring` 表达监听意图，不再直接作为读取器存活证明。Android 10+ 的 `isClipboardMonitoring()` 结合实际读取器健康；旧 Android 保留系统 listener 路径。
- `startMonitorInternal()` 返回布尔值，检查上下文、销毁状态及所需权限。入口接受启动请求不意味着已获得系统日志确认或成功后台读取。
- 导出 `getClipboardMonitorStatus()`，新增事件 `onClipboardMonitorStateChange`，原有 `onClipboardChange` 载荷契约保持不变。
- 状态包含 `state/generation/attempt/lastEventAtMs/reason/exitCode/detail/retryInMs`；模块补充 `readFailure/lastReadAtMs`。
- 新建读取器会话时清除上次读取成功／失败记录，避免用旧成功记录显示本次“正常”。
- 将 generation 带入主线程任务及 `triggerOverlayReadAndEmit()`。排队后执行、获得焦点后的读取回调、真正 emit 前均检查会话仍有效。
- `readClipWithRetry()` 增加错误回调；悬浮窗获取焦点失败、读取异常和空／不可读结果应可诊断。错误、取消和成功都必须释放焦点。
- `OnDestroy` 先标记 disposed，再安排停止；销毁后的排队任务不能重新激活监听。

完成条件：读取器死亡可见、可以恢复，停止有效，晚到的旧任务不会污染下一会话；原有前台读取和旧 Android 路径仍成立。

## 6. JS 与设置层：连接恢复动作，并保证模式真实

### 6.1 原生接口与 adapter

相关文件：

- `modules/clipboard-overlay/src/index.ts`
- `src/utils/backgroundClipboardAccess.ts`
- `src/utils/androidBackgroundClipboardAccess.ts`

具体要求：

1. 定义 `ClipboardMonitorStatus`，封装状态查询和订阅。旧原生二进制没有新接口时返回 `null/不可用`，而不是根据权限猜测监听正常。
2. 在 `OverlayClipboardAdapter` 内用 Promise 队列串行化原生 stop/start；旧 stop 未完成，新 start 不得越过它。
3. 用 adapter epoch 与本次订阅的 active 标记忽略过期异步结果和事件。`remove()` 幂等，释放事件、健康状态和 AppState 订阅；旧订阅的 remove 不能停止新的读取器。
4. 原生启动失败、拒绝或异步完成时已过期，清理已创建的订阅。
5. `AppState` 回到 `active` 时，如果当前订阅有效、权限存在且原生报告不健康，合并重复恢复请求并重新启动。健康读取器保持不动；移除后的订阅不再恢复。
6. 前台恢复是权限确认等情况下的补充入口；**后台故障自恢复由原生有限重试负责**。只增加“回前台重启”不能满足本任务。
7. 健康状态与授权状态分开订阅；健康事件不经过会触发重启的授权监听器，否则会形成状态更新→重启→状态更新的循环。
8. 将 failed/retrying/readFailure 及有界退出诊断送入现有应用日志，使用既有 logger；不记录复制内容。

### 6.2 禁止 ADB 模式的隐式轮询

文件：`src/features/clipboard/internal/clipboardMonitor.ts`。

在统一的 `startPolling()` 入口检查 Android 的 `clipboardAccessMethod === 'overlay-event'`，清理已有轮询后直接返回，并记录准确的不可用状态。不能只在首次启动的某一个调用点加判断，因为 `resumePolling()` 等入口也能重新创建计时器。

同时处理启动过程中的 await：加载持久化 hash 后、等待事件监听创建后，若监听已停止就不再继续；晚到的订阅必须释放。日志区分事件监听、实际轮询和等待事件监听恢复，避免宣称已启动轮询。

完成条件：原生启动返回失败或抛错、恢复入口被调用时，ADB 模式均不创建 `clipboard_monitor` 的周期计时器；其他模式保留原策略。

### 6.3 后台设置页

文件：`src/screens/settings/android/BackgroundSection.tsx`。

- “权限已就绪”只表达 ADB/悬浮窗权限；另设“事件监听状态”行。
- 展示 stopped、starting、listening、retrying、failed、接口不可用及事件读取失败；只有实际读取结果更新后才能展示已通过事件读取。
- `listening` 只说明监听入口正在等待事件，不证明已经获得其他进程日志访问；读取成功也不证明 Mac 已收到。
- 使用现有 `SettingsListRow`，整行可点击“重新启用”。成功提示仅说已请求启动，不说后台已验证成功。
- **正常开启总开关**：保存设置、完成权限引导后，重启所选 ADB 监听。
- **恢复临时暂停分支**：解除暂停后，也重启所选 ADB 监听。两个分支均要覆盖。
- 更新 `en/zh/ru/pt-BR` 的 `settingsBackground.json`；健康状态变化不触发授权恢复循环。

## 7. 回归测试与验证命令

优先补能在旧实现失败的测试，再完成修复。测试应覆盖真实的失败模式，而不是只检查函数被调用或组件能挂载。

### 7.1 原生确定性测试

新增 `modules/clipboard-overlay/android/src/test/java/expo/modules/clipboardoverlay/ClipboardLogMonitorTest.kt`，并在该模块 `build.gradle` 加入 JUnit 测试依赖。本次使用 `junit:junit:4.13.2`，仅为 testImplementation。

用假 `Process`、阻塞日志输入、退出码和 latch 验证：

| 用例 | 必须证明 |
| --- | --- |
| 读取器退出后显式启动 | 不再健康，退出码可见，新读取器能收到事件；健康时重复启动不新增进程 |
| 意外 EOF | 不要求切回前台，也能在失败后恢复日志读取 |
| 连续失败 | 重试次数有上限，耗尽后为 failed |
| 明确拒绝日志访问 | 不重试，诊断保留且有长度上限 |
| 重试等待期间 stop，再 start | 旧等待被取消，新会话正常，不受旧 finally 干扰 |
| 停止后旧 spawn 才返回 | 只销毁旧进程，新进程和新状态不受影响 |

使用 latch 等同步原语控制顺序；测试等待时间上限只用于防止挂死，不依赖随意 sleep 碰运气。

### 7.2 JS／UI 回归

本次对应文件：

- `src/__tests__/androidBackgroundClipboardModes.test.ts`：死读取器回前台恢复；健康／移除后的监听不重启；异步旧 stop 完成后新 start 才执行，重复 remove 不停止新会话。
- `src/__tests__/ClipboardMonitor.adbRecovery.test.ts`：ADB 原生启动抛错及调用 `resumePolling()` 时，均不产生剪贴板轮询计时器。
- `src/__tests__/BackgroundSection.adbHealth.test.tsx`：权限与健康区分；失败通知不触发重启循环；整行重启只报告请求；正常开启、恢复暂停都启动读取器。

基线上的针对性命令：

```sh
npx jest --runInBand src/__tests__/androidBackgroundClipboardModes.test.ts src/__tests__/ClipboardMonitor.adbRecovery.test.ts src/__tests__/BackgroundSection.adbHealth.test.tsx
npm run type-check
```

在已按项目流程生成 Android 工程后运行：

```sh
cd android
./gradlew :clipboard-overlay:testDebugUnitTest --no-daemon --console=plain
```

再运行项目要求的相关 lint、全量测试和 Release 构建。`docs/tests/android-background-sync-acceptance.md` 中记录新增行为与实际验证边界。

较新分支测试命名可适配，但以上行为断言应保留。环境依赖未正确构建导致失败时，先修复环境；不能删除测试、放宽断言或拿不相关的绿色检查代替目标行为。

## 8. 构建、人工验收与交付条件

### 8.1 构建要求

- 按项目已有依赖准备和 Engine 固定版本流程构建，保持 `modules/uc-engine/core-source.json` 不变。
- 新增原生类和方法后需要重新构建 Android APK，单独替换 JS bundle 不足以交付本修复。
- 使用现有 `APP_VARIANT=test` 机制构建独立测试包，不把临时测试包名写死进生产源码。
- 本次使用的生成和构建入口如下；先完成依赖、模块构建和固定 Engine 产物准备，再执行：

  ```sh
  APP_VARIANT=test npx expo prebuild --platform android --no-install
  cd android
  APP_VARIANT=test ./gradlew :app:assembleRelease -PreactNativeArchitectures=arm64-v8a --max-workers=2 --no-daemon --console=plain
  ```

- 验证最终包的包名、ABI、签名和内置 bundle。测试版应能独立启动，无需 Metro。官方合入仍沿用维护者自己的生产签名与发布流程。
- 先交付可审查的补丁、测试结果和测试 APK；手机安装、卸载或覆盖现有应用须在实际获得用户安装授权后进行。

### 8.2 真机验收清单

| 场景 | 验收条件 |
| --- | --- |
| 普通后台复制 | 服务及授权就绪后只按 Home，在微信等其他 App 复制新普通文字；不重新打开 UniClip、不点手动同步，Mac 自动收到 |
| 读取器异常退出 | 测试环境终止应用自己的读取器，状态反映中断；系统允许日志读取时有限恢复，后续真实复制可同步 |
| 日志访问被拒绝 | 状态可见、不无限重启、不退回轮询；系统需要确认时由用户在前台确认 |
| 开启／恢复总开关 | 两个入口均重建监听，而非只改变常驻服务或界面开关 |
| 快速开关／停止重启 | 新监听不被旧停止请求或旧排队事件破坏；无停止后的旧会话 emit |
| 锁屏、网络变化 | 分别记录采集、上传、Mac 收到三个阶段，避免把网络问题误判为监听失效 |
| 两端重启、长时间待机 | 单独执行并记录恢复通知、日志确认和后台限制；未执行就标未验证 |

ADB 权限命令中的包名应来自实际构建的 applicationId；本次测试版是：

```sh
adb shell pm grant app.uniclipboard.android.test android.permission.READ_LOGS
```

一次授予权限不等于系统永久允许读取所有日志。确认访问后关闭无线调试，再进行正常复制测试，不把 ADB 连接常驻当作验收前提。[Android 官方设备日志访问说明](https://support.google.com/android/answer/12986432?hl=en)。

完成条件：上述自动化断言通过、生成有效测试 APK，并分别报告构建结果、用户反馈和实际执行的真机项目。没有真机条件时交付待实测版本，不宣称 OEM 后台或重启行为已经全部通过。

## 9. 本次交付的实际结果与可核对标识

| 检查 | 结果 |
| --- | --- |
| Jest | 237 个套件、1,968 项测试通过，0 失败 |
| 原生监听测试 | 6 项通过，0 失败；原生模块编译通过 |
| 类型检查／相关 ESLint／补丁检查 | 通过 |
| 最终构建源码 | 与已测试补丁逐字节一致 |
| ARM64 Release APK | 构建通过，约 101 MB；有效 v2 签名；非 debuggable；内置 bundle |
| 交付时安装行为 | 未向手机安装或覆盖应用 |
| 交付后用户反馈 | 用户回复“可以了”；未另外采集完整的修复后真机验收记录 |
| 重启、长时待机、跨网完整矩阵 | 未完成系统性验证 |

本次补丁改动 17 个文件，覆盖原生读取器与模块、TS 接口和 adapter、统一轮询入口、Android 后台设置、四种语言、回归测试及验收说明。没有修改 Rust Engine、Mac 端或正式包名。

标识：

```text
补丁：UniClip-ADB-listener-fix.patch
SHA-256：c6255012a6595e12a4923572f8c1c0b840962890392ba8326b0e69d4d74294cd

APK：UniClip-2.3.0.195-ADB-Fix-Test-arm64.apk
包名：app.uniclipboard.android.test
SHA-256：ed32ce3f486526401269124769a47c739d8ce882ed5ea844bbb57d8da8ceec1b
```

配套 `验证记录.json` 记录的是构建交付时状态，“真机未验证”与后来用户的简短正向反馈属于不同时间、不同证据层级，不应改写为一套已经执行过的完整真机测试。

本机曾因 iCloud 云端占位文件阻塞构建，之后改用普通本地构建目录，并复用已成功编译的固定版本引擎产物完成封装与校验。这是构建环境处置，不是应用问题的修复，不应作为产品代码改动复制到上游。

## 10. 合入时保留的限制

- 此补丁不把日志进程存活等同于拥有全系统日志访问，也无法单凭“没有事件”区分用户没复制、系统未输出日志和平台限制。缺少事件时应保留真实的等待／失败状态，并补采诊断，不能显示虚假的成功。
- 它没有改变系统的一次性日志访问确认、OEM 杀后台策略、原有 `onTaskRemoved` 行为或开机恢复流程；不能承诺所有“后台自动关闭”和重启免操作问题已经解决。
- 它不以更换中继解决采集问题，也不因采集失败更改用户选定的读取模式。采集、读取和网络送达应分阶段验证。
- 开发者转发本交接包即可定位本次实现；包内不包含原始手机诊断压缩包、用户剪贴板内容、配对码、邀请或密钥。
