# 烬刃 Demo（Godot 4.7.2）

横屏移动端动作 Demo。玩法见 `../_shared/DESIGN.md`，数值配置见 `config/game.json`（与 `../_shared/config/game.json` 保持一致）。

## 本地运行 Web 版（固定端口 8941）

```bash
npm run serve        # 等同于 python3 -m http.server 8941 -d build/web
```

然后打开 http://localhost:8941/ 。加上 `?debug` 会开启 AI 调试桥（`window.__AI_BRIDGE__`），例如 http://localhost:8941/index.html?debug 。

仓库里不包含 `build/`。第一次运行前要先构建：

```bash
python3 tools/sync_assets.py   # 从 ../_shared/assets 复制已就绪的资源（不复制人物语音）
godot --headless --path . --import
npm run build                  # 导出 Web 版到 build/web/
```

## 检查与验收

```bash
bash tools/check.sh            # 无头检查脚本错误，通过时输出 CHECK_OK
npm i && npx playwright install chrome
npm run e2e                    # 需要先 npm run serve；可加 --only=full|small|perf
```

e2e 用 CDP 发送真实多点触摸，在 844×390 和 667×375 视口下各打一整局，并测试性能。截图和 `report.json` 输出到 `tools/shots/`。

## Android APK

```bash
godot --headless --path . --export-debug "Android" build/android/ember-godot.apk
```

需要在编辑器设置里配置好 Android SDK 和 JDK 17 的路径。详细配置见 `ENGINE_NOTES.md` 的“APK 打包体验”一节。

## 目录

- `core/`：纯逻辑（状态机、战斗、波次、三选一、可复现随机数、bot），不依赖任何节点。
- `view/`：渲染、特效、HUD、触控、界面、音效，以及调试桥。
- `tools/`：资源同步、字体子集化、无头模拟、e2e。这些文件不会打进导出产物。
