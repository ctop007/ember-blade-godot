# 烬刃

横屏手机动作 Demo。拿起长枪，在余烬森林里打完四波魔物。

这是 **Godot 4.7.2** 版，下载就能玩：[Android 安装包](https://github.com/ctop007/ember-blade-godot/releases/download/v0.3.0/ember-blade-godot-android.apk) · [浏览器压缩包](https://github.com/ctop007/ember-blade-godot/releases/download/v0.3.0/ember-blade-godot-web.zip) · [v0.3.0 Release](https://github.com/ctop007/ember-blade-godot/releases/tag/v0.3.0)。同一套玩法还有 [Cocos Creator 版](https://github.com/ctop007/ember-blade-cocos)。两个仓库都开源，用来看看 AI 能不能把游戏写到能上手。试玩录像会另外放出。

<p align="center">
  <img src="assets/ui/home_bg.png" alt="余烬森林：主角站在月光下的林间高处，手里握着燃烧的长枪" width="720">
</p>

<p align="center">
  <sub>主页画面。实机试玩录像会随后补上。</sub>
</p>

## 试玩

不用安装 Godot。手机横过来，或把浏览器窗口拉宽。

| 在哪玩 | 文件 | 怎么打开 |
| --- | --- | --- |
| 安卓手机 | [`ember-blade-godot-android.apk`](https://github.com/ctop007/ember-blade-godot/releases/download/v0.3.0/ember-blade-godot-android.apk)（约 44 MB） | 安装后打开。仅 arm64。调试签名，只适合试玩 |
| 浏览器 | [`ember-blade-godot-web.zip`](https://github.com/ctop007/ember-blade-godot/releases/download/v0.3.0/ember-blade-godot-web.zip) | 解压后在该目录起一个静态服务器，打开 `index.html` |

浏览器版第一次加载要稍等，里面的引擎文件大约 38 MB。用文件协议直接打开时，浏览器会拦住 wasm，所以需要静态服务器：

```bash
python3 -m http.server 8080
```

然后打开 http://localhost:8080/ 。

## 操作

左手摇杆移动，右手是按钮。桌面浏览器可以用鼠标点按，也可以用键盘。

| 动作 | 屏幕 | 键盘 |
| --- | --- | --- |
| 移动 | 左侧摇杆 | `W` `A` `S` `D` |
| 普攻 | 攻击键，连点打出三段 | `J`，按住蓄力，松开是突刺 |
| 跳跃 | 跳跃键 | `K` |
| 下砸 | 在空中再按攻击 | 起跳后按 `J` |
| 闪避 | 闪避键，带短暂无敌 | `L` |
| 炎月斩 / 天穹落光 / 流星枪 | 三个技能键，消耗法力 | `U` / `I` / `O` |
| 烬灭·星陨 | 怒气攒满后的大招 | `P` |
| 暂停 | 右上角 | `Esc` |

每一波结束会翻出三张强化卡，选一张。第四波是 Boss「灰烬骑士」。

## 这局里有什么

- 主角是「烬刃·灯」，场景在余烬森林
- 四种敌人：余烬小鬼、投石灯笼怪、树皮重甲、灰烬骑士
- 按手机横屏做的，设计分辨率 1280×720
- 数值在 [`config/game.json`](config/game.json)，和 Cocos 版是同一套

## 自己构建

需要本机有 **Godot 4.7.2**，并且终端里能运行 `godot`。画面、音效和骨骼已经在仓库里。`tools/sync_assets.py` 只在旁边还有一份 `_shared` 资源目录时，用来把更新同步进来。

### 浏览器版

```bash
godot --headless --path . --import
npm run build    # 导出到 build/web/
npm run serve    # http://localhost:8941/
```

地址后面加上 `?debug`，会打开给自动化用的调试接口 `window.__AI_BRIDGE__`。

### 安卓包

```bash
godot --headless --path . --export-debug "Android" build/android/ember-godot.apk
```

先在 Godot 里配好 Android SDK 和 JDK 17。步骤记在 [ENGINE_NOTES.md](ENGINE_NOTES.md) 文末的「APK 打包体验」。

### 检查

```bash
bash tools/check.sh                  # 通过时输出 CHECK_OK
npm i && npx playwright install chrome
npm run serve                        # 先保持这个进程
npm run e2e                          # 可加 --only=full|small|perf
```

## 目录

| 路径 | 内容 |
| --- | --- |
| `core/` | 战斗、波次、三选一，不依赖画面节点 |
| `view/` | 画面、触控、界面、音效 |
| `config/game.json` | 数值 |
| `tools/` | 检查和测试，不会打进发布包 |

实现细节、性能数据和导出时踩过的坑在 [ENGINE_NOTES.md](ENGINE_NOTES.md)。

## 说明

- 安卓包是调试签名，只适合试玩。
- 游戏里没有人物配音。
- 另一条引擎实现：[ember-blade-cocos](https://github.com/ctop007/ember-blade-cocos)。
