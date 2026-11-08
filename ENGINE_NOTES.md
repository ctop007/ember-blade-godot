# ENGINE_NOTES：Godot 4.7.2 版

## 运行方式

- 构建：`python3 tools/sync_assets.py && godot --headless --path . --import && npm run build`
- 启动：`npm run serve`，即 `python3 -m http.server 8941 -d build/web`
- 地址：http://localhost:8941/ 。调试桥地址是 http://localhost:8941/index.html?debug
- 检查：`bash tools/check.sh`，通过时输出 CHECK_OK。验收：`npm run e2e`
- APK：`_deliverables/ember-godot.apk`，打包方法见文末

## 实测数据

测试环境是 MacBook（Apple Silicon）、Chrome 搭配 Playwright 1.56.1、`isMobile` 与 `hasTouch`、DPR 2。所有输入都是 CDP 发出的真实触摸。数据来自 `tools/shots/report.json`。

| 项目 | 数据 |
|---|---|
| Web 产物 | 共 49 MB：`index.wasm` 39.5 MB（官方模板，未裁剪），`index.pck` 11.7 MB，`index.js` 0.28 MB |
| APK | 40.8 MB（arm64-v8a，debug 签名）。其中 `libgodot_android.so` 解压后 76 MB |
| 首屏加载（打开页面到主页可点） | 844×390 下 1.29 s，perf 运行 1.24 s，667×375 下 2.43 s（本地服务、无缓存） |
| 普通战斗 FPS | 844×390 整局平均 58.8，667×375 整局平均 59.2 |
| 战斗最低 FPS | 14.2 和 18。只在 Boss 登场或新敌人首次出现时掉一帧，见“已知问题” |
| 大招加 20 只以上敌人，CPU 节流 4× | 释放前 60，大招期间平均 57.1、最低 51，同屏平均 23 只 |
| 粒子峰值 | 260，达到全局上限 `combat.maxParticles` 后被限住 |
| JS 堆内存 | 41.5 MB（`performance.memory`） |
| 真机（Samsung SM-G9980，Android） | 启动后横屏、战斗正常，无脚本错误，PSS 约 470 MB |

e2e 结果（全部通过，控制台错误为 0）：

- 844×390 整局：胜利，3 次三选一。三选一动画期间点击都被拦下。Boss 登场卡出现，结算后“再来一局”生效，用时约 138 s。
- 844×390 单项：摇杆、普攻三段、蓄力突刺、闪避、跳跃、下劈（`slam > slam_end > idle`）、月牙斩、天坠、流星枪、自然攒满怒气、大招，全部通过。每项都有截图。
- 667×375 整局：胜利，3 次三选一，结算后再来一局生效，布局检查没有越界或重叠。
- 两个视口的整局都是 bot 在 Boss 阶段血量低于 20% 后开了 `god`。主要原因是脚本走位躲不开 Boss 的横扫。无头模拟 `tools/sim.gd` 里 bot 5 局赢 4 局。

## 实现差异

### 输入与多点触控

- `Controls` 直接处理 `InputEventScreenTouch` 和 `InputEventScreenDrag`。按手指 index 把每根手指绑定到一个控件（摇杆或某个按钮），手指抬起前不会被其他区域抢走。同时开启了 `emulate_mouse_from_touch`，主页和弹窗按钮走 `_gui_input` 的鼠标事件。
- 打开三选一或暂停时，`set_enabled(false)` 会清空所有手指。玩家需要重新按摇杆，e2e 也照这个流程做。
- 坑：CDP 的 `Input.dispatchTouchEvent` 每个事件只应列出发生变化的手指，和 Puppeteer 一致。如果在 touchEnd 时把仍按着的手指也列进去，Godot 会收到这些手指的抬起，摇杆随之松开。另外 touch id 必须小于 16，否则报错 "Exceeded maximum touch points limit of 16"，所以 id 要复用。

### 粒子与特效

- 没有用 GPUParticles2D 或 CPUParticles2D。`view/particles.gd` 是自己写的批量粒子层，每层一次绘制，全局共享 260 的上限。这样上限精确可控，Web（gl_compatibility）上也不会有 GPU 粒子首帧编译的卡顿。
- 技能贴图用的是 assets 代理提供的 21 张 fx 贴图，都是白色加 alpha。代码里着色后用 additive 混合。meteor、smoke、rock_debris 三张带明暗，用普通混合。光柱贴图横向放大 1.75 倍。
- 各技能的区分：月牙斩是贴身旋转的弧光加火星；天坠先出地面预警圈，再落光柱，然后爆炸、溅碎石；流星枪是横向飞行的长枪，留下余烬拖尾；大招是立绘切入、技能名、多点陨石轰炸，并且全场冻结。e2e 截图确认技能特效没有挡住敌人。

### 补间

三选一（遮罩淡入、卡背依次飞入、按顺序翻面、稀有和史诗停顿）、结算弹窗、大招切入、受击闪白都用 `create_tween()` 链式实现，写起来很顺。有一个坑：结算面板在缩放补间过程中，读到的按钮坐标会过期。调试桥改为用 `get_global_transform()` 计算按钮中心，测试脚本在补间结束后重新读一次。

### y 排序

角色放在 `y_sort_enabled` 的 Node2D 下，每个角色节点的原点放在脚底。跳跃高度 z 只偏移角色的子精灵，不改变节点的 y，所以跳起来时排序不会乱。地面效果（预警圈、影子）用 `z_index = -1` 放在角色下面。

### 音频

- 27 个真实音效 ogg 加 1 首循环 BGM（`AudioStreamOggVorbis` 设为 `loop`）。音效走一个 14 路 `AudioStreamPlayer` 轮转池，带最小间隔和随机音高。如果某个 ogg 还没交付，就用 `AudioStreamWAV` 现场合成的占位音。
- 按用户要求，游戏里没有任何人物语音：`ult_voice` 的播放、合成配方和预加载都删除了。`tools/sync_assets.py` 不复制这个文件，写入 `assets/manifest.json` 时也会把它过滤掉。也没有用 TTS 兜底。大招保留技能名文字、立绘、非人声的起手音（`ult_start`）和爆炸音（`ult_impact`）。
- 核对结果：Web 的 `index.pck` 里，`ult_voice`、`voice`、`tingting` 出现 0 次。APK 里文件名或内容包含这些词的也是 0 个，共 28 个 ogg 流（27 个音效加 BGM）。
- 普通落地没有单独的音效，复用 `land_slam`，音高 ×1.35、音量 −12 dB。
- Web 端浏览器要求先有用户手势才能出声。主页“开始战斗”那一下点击就是这个手势，所以不需要额外处理。

### Web 导出时的坑

1. Godot 遇到脚本错误时，命令行退出码仍是 0。`tools/check.sh` 改成在输出里 grep `SCRIPT ERROR` 和 `Parse Error` 来判断。另外每次加新的 `class_name` 后要先跑 `--import`，否则会报类找不到。
2. 导出预设排除了 `tools/*`，于是 bot 原本放在 tools 下、导出后报 "Bot not declared"。现在 bot 移到 `core/bot.gd`。
3. Label 的 autowrap 在 Web 导出里不会给中文断行（编辑器里正常），文字直接出界。改为 `UiDraw.wrap_text`：手动测量宽度后插入换行，并且不让“，。！？”这类标点出现在行首。
4. CanvasLayer 下 full-rect 的 Control，在第一帧 `_draw` 时 `size` 不对，HUD 元素因此错位。改为用 `get_viewport_rect().size`。
5. 圆角矩形的点里有重复点时，`draw_polygon` 会刷几百条 "Invalid polygon data, triangulation failed"。生成点时去掉重复点即可。
6. 中文字体用 pyftsubset 只保留代码和配置里出现过的字，`tools/make_font.sh` 生成后只有 89 KB。缺点是新增文案后必须重新跑一次，否则会出现方块字。
7. wasm 用的是官方模板，有 39.5 MB，是产物里最大的部分。要缩小只能自己编译裁剪过的模板，这次没有做。
8. 调试桥用 `JavaScriptBridge.eval`。状态每 0.1 s 写入 `window.__jr`，命令通过队列传进来，只在 `?debug` 下暴露 `__AI_BRIDGE__`。

## AI 开发体验

- 顺畅的地方：整个项目没打开过编辑器。场景只有一个很小的 `Main.tscn`，其余节点全部在代码里创建。导入、检查、Web 导出、APK 导出都能无头完成。GDScript 的 tween 和 `_draw` 写 UI 很快。纯逻辑的 core 可以用 `tools/sim.gd` 无头跑上百局来调数值。
- 需要绕路的地方：报错不影响退出码（见上一节第 1 条）。Web 和编辑器的行为有差异（autowrap、`size`），只能靠截图发现。e2e 的触摸语义也调了几轮才对。
- 报错定位：解析错误会带文件和行号，比较好定位。运行时错误在 Web 上只出现在浏览器控制台，要靠 Playwright 收集。
- 需要人工的地方：这次没有。

## 未完成项和已知问题

- UI 资源有 22 项还是 pending（按钮、摇杆、技能图标、头像、血条、卡牌、面板、Boss 标题等），目前用代码绘制的占位。资源到了以后跑一次 `sync_assets.py` 就会自动替换，因为代码会优先加载真实贴图。
- 大招立绘和横幅还没交付，暂时用主角施法图代替。
- 主页的月亮和 logo 有部分重叠，要等 UI 资源到位后再调。
- Boss 登场或新敌人首次出现时会掉到 14–18 FPS，只掉一帧。推测是贴图第一次上传到 GPU 或着色器第一次编译造成的。可以在加载阶段把这些贴图预先画一帧来解决，这次没有做。
- bot 打 Boss 需要开 god（见“实测数据”）。这是测试脚本的问题，游戏本身没有问题。
- APK 是 debug 签名，`debuggable=true`，只用于试玩。

## APK 打包体验

**配置**

- 编辑器设置：在 `~/Library/Application Support/Godot/editor_settings-4.7.tres` 里写入 `export/android/android_sdk_path = ~/Library/Android/sdk` 和 `export/android/java_sdk_path = jbr-17.0.14`。可以无头写入，这台机器上本来就配好了。
- 导出模板：使用已安装的 4.7.2.stable 模板 `android_debug.apk`。
- `export_presets.cfg` 里的 `[preset.1] "Android"`：
  - `gradle_build/use_gradle_build=false`，只勾选 `arm64-v8a`
  - `package/unique_name=com.yuen7.ember.godot`，`package/name=烬刃·Godot版`
  - `keystore/debug=~/.android/debug.keystore`，用户 `androiddebugkey`，密码 `android`
  - 图标：`launcher_icons/main_192x192` 用 `ui/app-icon.png`。自适应图标的背景层用它缩放到 432×432 的版本（`assets/icon/adaptive_bg.png`），前景层是一张全透明的 432×432 图。原图是满幅插画，没有可以单独拆出来的前景。启动器裁切后保留中间约 66% 的区域，脸部在这个范围里。
- `project.godot` 里设置 `window/handheld/orientation=4`，即 sensor_landscape。
- 命令：`godot --headless --path . --export-debug "Android" build/android/ember-godot.apk`，约 8 s 完成。完成后复制到 `_deliverables/ember-godot.apk`。

**`aapt2 dump badging` 核对**

- `package: name='com.yuen7.ember.godot' versionCode='1' versionName='0.1.0'`
- `application-label:'烬刃·Godot版'`
- `minSdkVersion:'24'`，`targetSdkVersion:'36'`，`native-code: 'arm64-v8a'`
- Manifest 里 `screenOrientation=11`，即 userLandscape。Godot 把 sensor_landscape 映射成这个值：两个横屏方向都可以转，同时尊重系统的方向锁。
- `apksigner verify` 显示证书 `CN=Android Debug`。

**坑**

- 导出时把 `build/` 也当成了项目资源扫描，还会生成 `.import` 文件。加 `build/.gdignore` 后解决。
- 资源在 APK 里放在 `assets/` 下，形式是 sparse pck，不是单个 `.pck` 文件。所以核对语音时要先解压 APK，再在整个目录里 grep。
- aapt2 会报 `themed_icon.xml` 缺失的警告（Android 13 的单色主题图标）。这个警告不影响安装和显示，没有处理。
- 不用 gradle 打包时，改不了 AndroidManifest 里的大部分内容，也加不了插件。对这个 Demo 来说够用。

**体积**：APK 40.8 MB。主要是引擎 so，解压后 76 MB。资源大约 11 MB。

**真机冒烟**：用 adb 只安装和启动 `com.yuen7.ember.godot`，没有动设备上的其他 App。设备 SM-G9980 上启动后进入横屏，能进入战斗，HUD 和按钮布局正确，logcat 里没有脚本错误。
