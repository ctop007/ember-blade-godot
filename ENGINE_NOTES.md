# ENGINE_NOTES：Godot 4.7.2 版

## 运行方式

- 构建：`python3 tools/sync_assets.py && godot --headless --path . --import && npm run build`
- 启动：`npm run serve`，即 `python3 -m http.server 8941 -d build/web`
- 地址：http://localhost:8941/ 。调试桥地址是 http://localhost:8941/index.html?debug
- 检查：`bash tools/check.sh`，通过时输出 CHECK_OK。验收：`npm run e2e`
- 统一口径性能：`node tools/bench_unified.mjs --url=http://127.0.0.1:8941/index.html --rig=sprite|hero --out=tools/shots/bench-unified-*.json`
- Thread Support 导出验证：预设改 `variant/thread_support=true` 导出到 `build/web-mt`，用 `python3 tools/serve_coop.py 8942 build/web-mt` 提供服务（带 COOP/COEP 头）
- APK：`_deliverables/ember-godot.apk`，打包方法见文末

## 实测数据

测试环境是 MacBook（Apple Silicon）、Chrome 搭配 Playwright 1.56.1、`isMobile` 与 `hasTouch`、DPR 2。所有输入都是 CDP 发出的真实触摸。数据来自 `tools/shots/report.json`。

| 项目 | 数据 |
|---|---|
| Web 产物 | 共 53.9 MB：`index.wasm` 37.9 MB（官方模板，未裁剪），`index.pck` 15.6 MB（含 5 个角色打图集），`index.js` 0.32 MB |
| APK | 43.8 MB（arm64-v8a，debug 签名，versionCode 2）。其中 `libgodot_android.so` 解压后 76 MB |
| 首屏加载（打开页面到主页可点） | 844×390 下 1.29 s，perf 运行 1.24 s，667×375 下 2.43 s（本地服务、无缓存） |
| 普通战斗 FPS | 844×390 整局平均 58.8，667×375 整局平均 59.2 |
| 战斗最低 FPS | 14.2 和 18。只在 Boss 登场或新敌人首次出现时掉一帧，见“已知问题” |
| 大招加 20 只以上敌人，CPU 节流 4× | 释放前 60，大招期间平均 57.1、最低 51，同屏平均 23 只 |
| 粒子峰值 | 260，达到全局上限 `combat.maxParticles` 后被限住 |
| JS 堆内存 | 41.5 MB（`performance.memory`） |
| 真机（Samsung SM-G9980，Android） | versionCode 2 安装启动正常，横屏、战斗无脚本错误。重制 HUD 与骨骼角色显示正常，HUD 尺寸与浏览器 844×390 一致（`tools/shots/device-battle-final.png`）。性能优化后的最新 APK 待设备重新连接后补装验证 |

### 统一口径性能对比（Godot / Cocos 共用脚本）

脚本：`tools/bench_unified.mjs`（同一台 MacBook、Chrome + Playwright、844×390、DPR 2）。场景：20 只敌人存活（14 imp + 4 lantern + 2 brute，低于 20 自动补 imp）、主角用真实触摸**按住**普攻持续连段、`god` 开启。每档 CPU 节流后用 CDP `Emulation.setCPUThrottlingRate` 跑 10 s，在应用自己的 `requestAnimationFrame` 回调内记录两个数：

- `busy`：主线程在 rAF 回调里实际忙碌的毫秒数（脚本 + 在回调内提交的渲染工作）。
- `gap`：相邻两次 rAF 时间戳的间隔，即实际出帧间隔。

`rig=0` 全单图（`?rig=sprite`）与 `rig=1` 全骨骼（`?rig=hero`，5 个角色全部骨骼）：

| 配置 | 节流 | busy p50 / p95 (ms) | gap p50 / p95 (ms) | FPS (gap p50) |
|---|---|---|---|---|
| rig=0 全单图 | 1× | 1.90 / 2.40 | 16.7 / 16.7 | 59.9 |
| rig=0 全单图 | 4× | 5.80 / 7.90 | 16.7 / 16.8 | 59.9 |
| rig=0 全单图 | 6× | 8.70 / 11.60 | 16.7 / 16.7 | 59.9 |
| rig=1 全骨骼 | 1× | 3.60 / 4.10 | 16.7 / 16.7 | 59.9 |
| rig=1 全骨骼 | 4× | 12.90 / 15.50 | 16.7 / 16.7 | 59.9 |
| rig=1 全骨骼 | 6× | 22.50 / 27.00 | 16.7 / 33.4 | 59.9（10 s 410 帧，平均约 41） |

优化后 4× 节流下全骨骼已经稳定 60 FPS（busy p50 12.9 ms，gap p50/p95 都 16.7 ms）；1× 只比单图多 1.7 ms。6× 节流的 p50 仍是 60 FPS，但约四成帧跨两帧，平均约 41 FPS（优化前是 20 FPS）。

骨骼性能优化（按顺序做的）：

1. **绘制批次**：`RigPlayer` 本来就是单个 `CanvasItem` 的自定义 `_draw()`，用 `draw_set_transform_matrix` 画所有部件，不是每部件一个 Sprite2D。真正的瓶颈是每个角色 7–25 张独立贴图（全屏 178 个部件 = 178 次贴图切换）。`tools/sync_assets.py` 现在额外把每个角色的全部部件（含关键帧换图用的图）打包成 `rigs/<kind>/atlas.png` + `atlas.json`，`_draw()` 改用 `draw_texture_rect_region`，一个角色的所有部件共享一张贴图，可以合批成一次绘制。
2. **每帧分配与字典遍历**：每个 clip 在 `configure()` 时预编译成扁平轨道（时间/数值用 `PackedFloat32Array`，ease 预转整数码，模式 0=相对加、1=相对乘、2=绝对、3=离散数值、4=离散换图）。每帧只重置上一帧真正写过的属性（`reset_pairs`），不再深拷贝 setup pose、不再按字符串比较 ease、不再遍历全部 31×7 个属性。骨骼顺序和静态绘制顺序也预计算；交叉淡入只处理实际发生变化的属性。
3. **弹簧与拖尾**：弹簧链的节长、轴向、刚度/阻尼/重力在 `configure()` 时预计算；弹簧子步按 `dt` 取 1–2 步（不是固定每帧重建骨骼树），只有弹簧真正转动某根骨时才重建它的子树。`SpearTrail` 从每个渲染子步都重建两次条带网格，改成子步只记录弧线采样点、每帧只重建一次网格。
4. **激活范围**：角色视图在进入 `game.enemies` 时才创建、离开时释放；本次基准里 20 只全在屏内，所以没有再加视口裁剪（以后超大地图再加）。

调试时可用桥接字段 `rigSimUs`（`advance()` 内 GDScript 耗时）、`rigDrawUs`（`_draw()` 记录命令耗时）、`rigEvalUs`/`rigWorldUs`/`rigSpringUs` 和 `rigParts`（每帧部件数）定位开销，`bench_unified.mjs --diag` 会采样这些值。

**6× 节流记录（不阻塞交付）**：全骨骼 busy p50 22.5 ms 仍超过 16.7 ms 帧预算，约四成帧跨越两帧（gap p95 33.4 ms），10 s 出 410 帧、平均约 41 FPS；p50 gap 仍是 16.7 ms。6× 是极限场景，4× 已达标。

**截图说明**：`tools/shots/all-rigs-844x390.png` 和 `all-rigs-667x375.png` 是为展示 5 个角色骨骼**用调试桥摆拍**的（`clearEnemies` 后手动 `spawn imp/lantern/brute/boss`），不是正常波次流程。正常流程第 1 波只有 imp（见 `p844-wave1.png`），`game.json` 里 Boss 只出现在第 4 波。

### 数据汇总

| 项目 | 数据 |
|---|---|
| 全骨骼 1× busy p50/p95 | 3.60 / 4.10 ms，gap 16.7/16.7（60 FPS） |
| 全骨骼 4× busy p50/p95 | 12.90 / 15.50 ms，gap 16.7/16.7（60 FPS） |
| 全骨骼 6× busy p50/p95 | 22.50 / 27.00 ms，gap 16.7/33.4（p50 60 FPS，平均约 41 FPS） |
| 全单图对照（1×/4×/6× busy p50） | 1.90 / 5.80 / 8.70 ms，均 60 FPS |
| Web 单线程产物 | 53,853,069 B（wasm 37.9 MB + pck 15.6 MB + js 0.32 MB） |
| Web Thread Support 产物 | 54,343,022 B（+0.49 MB；帧耗时无收益，不建议开线程） |
| 首屏（844×390 本地无缓存） | bench 1.9 s；e2e 1.4–1.6 s 到主页可点 |
| 真机 SM-G9980 | **HUD 与 5 角色骨骼上一版已验证**（`device-battle-final.png`）。本次性能优化版 APK（versionCode 2 / 0.2.0，43.8 MB）已就绪，等待设备重新连接后 `adb install -r` 补截图 |

### Web 单线程 vs Thread Support 导出

同一个 `tools/bench_unified.mjs`，Thread Support 版用 `tools/serve_coop.py` 加 COOP/COEP 头本地提供服务：

| 构建 | wasm | index.js | pck | 目录总计 | 增量 |
|---|---|---|---|---|---|
| 单线程（默认，当前交付） | 37,902,138 B | 315,645 B | 15,580,476 B | 53,853,069 B | — |
| Thread Support | 38,349,395 B | 358,342 B | 15,580,476 B | 54,343,022 B | +489,953 B（+0.9%） |

帧耗时（rig=1 全骨骼，两边都已含上面的骨骼优化）：

| 节流 | 单线程 busy p50/p95 | 单线程 gap p50/p95 | 多线程 busy p50/p95 | 多线程 gap p50/p95 |
|---|---|---|---|---|
| 1× | 3.60 / 4.10 | 16.7 / 16.7 | 3.75 / 4.28 | 16.7 / 16.7 |
| 4× | 12.90 / 15.50 | 16.7 / 16.7 | 13.89 / 16.11 | 16.7 / 16.7 |
| 6× | 22.50 / 27.00 | 16.7 / 33.4 | 23.73 / 29.27 | 33.3 / 33.3 |

结论：Godot Web 的主循环仍然在浏览器主线程上跑，Thread Support 只把音频、加载等挪到 worker，**主线程 busy 基本不变（6× 还略差）**。产物多 0.47 MB，还要服务器加 COOP/COEP 头（否则 SharedArrayBuffer 不可用）。因此在当前架构下 Web 端**不建议开线程**，保持默认单线程交付；如果以后把渲染或逻辑搬到 worker 再重新评估。

（历史数据：旧脚本用的是“点按”而非按住普攻、且包含调试桥轮询，数字与新口径不可横向比较。）

优化前的瓶颈是每帧对 20 个 `RigPlayer` 重复深拷贝 setup pose、按全部属性遍历、以及弹簧每帧重建整棵骨骼树。改成原地重置 pose、预先缓存每个 clip 实际有键的属性列表、预建 `children_of` 索引后，旧脚本下 4× 从 145.7 ms 降到 27.2 ms、6× 从 243.8 ms 降到 51.5 ms；统一口径下当前版本 1× 稳定 60 FPS。

e2e 结果（全部通过，控制台错误为 0；`--rig=hero`，5 个角色全部骨骼）：

- 844×390 整局：胜利，3 次三选一。三选一动画期间点击都被拦下。Boss 登场卡出现，结算后“再来一局”生效，用时约 124 s，平均 58.9 FPS（优化过程中另有一轮同构建未开 `god` 也通关，用时 102 s）。
- 844×390 单项：摇杆、普攻三段、蓄力突刺、闪避、跳跃、下劈、月牙斩、天坠、流星枪、自然攒满怒气、大招，全部通过；多点触控（第二指不抢占）和暂停恢复也都通过。每项都有截图。
- 667×375 整局：胜利，3 次三选一，结算后再来一局生效，布局检查没有越界或重叠，平均 59.2 FPS，用时约 127 s。
- 脚本 bot 走位躲不开 Boss 横扫，Boss 阶段血量低时会开 `god`；这是测试脚本的走位问题。无头模拟 `tools/sim.gd` 里 bot 5 局全胜。

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

### 骨骼动画（ANIMATION.md §4 / §4.1）

- `view/rig_player.gd` 是纯代码播放器：读 `rig.json` + `anims.json`，用 `Transform2D(rot, scale, skew, pos * unitsPerPixel)` 手工算骨骼世界矩阵，`_draw()` 里按 `slot.z + bone.z` 排序后用 `draw_set_transform_matrix` 画部件。没有用 `Skeleton2D` / `Bone2D` / `AnimationPlayer`，所以时间完全由 gameplay 时钟驱动，顿帧时传 `dt=0` 动画、弹簧、拖尾一起停。
- 关键帧默认是相对 setup pose 的增量：`rot/x/y` 相加，`sx/sy` 相乘；`"keyMode": "absolute"` 直接用绝对值。每个属性单独插值，ease 取目标帧上的字段（`linear/quadIn/Out/InOut/cubicIn/Out/expoOut/backOut/sineInOut/step`）。`image`、`z` 是离散键。slot 的 alpha 乘骨骼 alpha；pivot 以部件图左上角归一化。
- `phases` 时间重映射：source 时间轴的 `active` 对应 gameplay 的 `hitAt`，`recovery` 对应 `duration`，`0 → active` 的 windup 按比例缩放；`duration` 之后多出来的收招帧顺延。事件（`trail_on/trail_off/hit/sfx`）在跨越时触发，loop 回到 0 时也会重发 t=0 事件。
- 弹簧骨按节取到下一节的 setup 距离作长度，120 Hz 子步阻尼弹簧驱动，调整后的父骨会递归重建子树。`sockets`（hero 的 `spearTip/gripFront/gripBack`，敌人各自的爪尖/枪尖等）用于拖尾和投射物起点。
- `view/rig_actor.gd` 继承 `ActorView`：`res://rigs/<kind>/rig.json` 存在就用骨骼（主角和 imp/lantern/brute/boss 都是），否则回退单图。`?rig=sprite|test|hero` 可切换；`test` 是方块拼的测试骨骼（`view/rig_fixture.gd`）。
- 手感层：状态切换交叉淡入 0.06–0.12 s（受击/闪避/普攻 0.06，默认 0.08，idle/run 0.12）；输入缓冲 0.15 s；普攻后摇在 `feel.attackCancelAt` 之后可被下一段普攻/跳跃/技能取消，闪避随时可取消；前冲和蓄力突刺用 `Ease.delta` 的非匀位移曲线。
- `view/spear_trail.gd` 是跟随 `spearTip` 的条带网格：每个渲染子步沿弧线采样插槽世界坐标，双层 additive 三角带，显式时钟让顿帧时拖尾不继续老化。`gl_compatibility`（WebGL2）下 `ArrayMesh` 必须给 `PackedVector3Array` 顶点、`ARRAY_TEX_UV`、双面索引和非 null 贴图，否则什么都不画。
- 测试：`godot --headless -s tools/test_animation.gd` 覆盖相对/绝对键、属性级插值、目标帧 ease、离散 slot/z 键、phases 重映射、顿帧冻结、交叉淡入、弹簧、输入缓冲/取消窗口，并遍历 5 个角色的全部 clip 和 socket（输出 `ANIMATION_TEST_OK`）。

### 重制 HUD（UI_LAYOUT.md）

- 一律按 720 设计坐标绘制：`HudScale.K = 720 / 390 ≈ 1.846`，布局表里的 CSS 数值全部乘 K。逻辑视口高度固定是 720（`canvas_items` + `expand`），所以 K 是常量。**不要用运行时窗口或物理像素高度做分母**——真机 SM-G9980 的窗口是 3200×1440 物理像素，之前按 `720/高度` 计算会把 HUD 缩小 3–4 倍（用户真机截图确认过），改成常量后真机与浏览器 844×390 完全一致。
- 真机实测（`adb logcat`，`ANDROID_LAYOUT` 日志）：Android 上 `get_viewport().get_visible_rect().size` 是 stretch 后的设计尺寸 `(1600, 720)`，不是物理像素；`DisplayServer.screen_get_size()` 才是 `(3200, 1440)`，`screen_get_scale()` 为 2.40。因此 K 固定 1.846、安全区按 CSS×K 换算都是正确的。头像直径 81.2÷1600 ≈ 5.1% 屏宽，按钮为正常拇指尺寸。
- 右侧按键严格按表：`attack(R-40,B-40) r34/36`、`dodge(R-122,B-27) r21/23`、`jump(R-28,B-119) r21/23`、`skill1..3` 紧凑扇形 `r22/23`、`ult(R-176,B-95) r25/26`、`pause(R-22,T+22) r16/22`，摇杆 `r44/46`。每根手指按下时绑定一个控件，已按住按钮上的第二根手指被忽略；所有触摸直径换算成 CSS px 都 ≥ 44。
- 单图按钮（`btn_attack/btn_jump/btn_dodge/btn_pause`）只画一张图；技能按钮是 `icon_skill1..3 + btn_frame`、`icon_ult + btn_ult_frame` 分层，不再重复加框。
- 左上 `ui/avatar.png` 44×44 圆心在 `(L+22, T+22)`，HP 125×12、MP 110×10 用 `bar_frame.png` + 着色 `bar_fill.png`。右上暂停按钮 `(R-22, T+22)`，固定文案「乃秀游戏 Demo」右对齐在 `(R-46, T+22)`，字号 12（乘 K）、深色描边。暂停弹窗只有继续/重新开始/回主页，不额外加会重置战斗的开始键。



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

- 125/125 项正式 UI/角色/音效资源已全部 ready 并合入（重制 HUD、完整圆形胸像、锻铁暖金按钮、5 个角色的骨骼拆件）。`tools/sync_assets.py` 会按 mtime 增量复制，删掉的部件也会同步删除。
- 大招立绘和横幅资源已就位；如果某项素材临时缺失，代码仍会回退到代码绘制的占位。
- Boss 登场或新敌人首次出现时会掉到 14–18 FPS，只掉一帧。加载阶段现在会预加载 5 个角色的全部部件贴图，剩下主要是首帧着色器编译，这次没有进一步处理。
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

- `package: name='com.yuen7.ember.godot' versionCode='2' versionName='0.2.0'`
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
