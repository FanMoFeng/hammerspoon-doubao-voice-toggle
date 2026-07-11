# Hammerspoon 豆包语音输入开关

用 Mac 键盘上的 **右 Command（⌘）** 一键调用豆包输入法的语音识别：

- 第一次单击右 Command：切换到豆包输入法，等待切换完成，然后启动语音输入。
- 第二次单击右 Command：停止语音输入，并恢复之前使用的输入法。

脚本专门处理了输入法切换延迟、Option 误判双击、重复按键事件和状态错乱等问题。

## 功能特点

- 等待豆包输入法真正生效后才发送语音快捷键。
- 自动记录并恢复原来的输入法，不限于微信输入法。
- 两次左 Option 之间有安全间隔，减少豆包提示“不要双击”的情况。
- 切换过程中忽略重复操作，防止脚本状态错乱。
- 语音框启动后带有短暂保护期，避免刚弹出就被异常按键事件关闭。
- 重新加载配置时自动停止旧监听器和定时器。
- 全程在本机运行，不上传文字、录音或使用记录。

## 使用条件

1. macOS。
2. 已安装并启用[豆包输入法](https://www.doubao.com/)。
3. 已安装 [Hammerspoon](https://www.hammerspoon.org/)。
4. 豆包输入法的语音快捷键已设置为“单击左 Option”。

## 安装方法

### 第一步：安装并授权 Hammerspoon

1. 安装并打开 Hammerspoon。
2. 打开“系统设置 → 隐私与安全性 → 辅助功能”。
3. 允许 Hammerspoon 控制电脑。
4. 建议在 Hammerspoon 设置中开启开机启动。

### 第二步：设置豆包语音快捷键

进入豆包输入法设置，确认语音输入快捷键为：

```text
单击左 Option
```

如果这里设置成了双击、长按或其他按键，本脚本将无法正确控制语音输入。

### 第三步：下载脚本

可以下载本仓库 ZIP，也可以使用 Git：

```bash
git clone https://github.com/FanMoFeng/hammerspoon-doubao-voice-toggle.git
```

把 `doubao_voice.lua` 复制到：

```text
~/.hammerspoon/doubao_voice.lua
```

然后打开 `~/.hammerspoon/init.lua`，加入：

```lua
require("doubao_voice")
```

如果还没有 `init.lua`，新建一个并只写上面这一行即可。

> 不建议直接覆盖已有的 `init.lua`，否则可能丢失你原来的 Hammerspoon 配置。

### 第四步：重新加载

点击菜单栏中的 Hammerspoon 图标，选择 **Reload Config**。

看到“右 Command 豆包语音开关已启动”的提示，就说明加载成功。

## 使用方法

1. 将光标放进任意可输入文字的位置。
2. 单击一次右 Command，等待豆包语音框出现。
3. 正常说话。
4. 再次单击右 Command，停止语音并恢复原输入法。

右 Command 会被脚本独占。需要使用普通 Command 快捷键时，请使用左 Command。

## 可调整参数

以下参数位于 `doubao_voice.lua` 文件开头：

| 参数 | 默认值 | 作用 |
| --- | ---: | --- |
| `TARGET_METHOD` | `豆包输入法` | 目标输入法名称 |
| `SWITCH_TIMEOUT` | `3.0` | 等待输入法切换的最长秒数 |
| `DOUBAO_READY_DELAY` | `0.35` | 确认切换后，额外等待豆包准备的时间 |
| `MIN_OPTION_INTERVAL` | `1.10` | 两次 Option 单击的最短间隔 |
| `VOICE_START_GUARD` | `1.50` | 语音启动后的停止保护时间 |
| `RESTORE_DELAY` | `0.80` | 停止语音后恢复原输入法的等待时间 |

如果电脑较慢，出现“已经切到豆包但语音框没有弹出”，可以把：

```lua
local DOUBAO_READY_DELAY = 0.35
```

改成：

```lua
local DOUBAO_READY_DELAY = 0.60
```

## 常见问题

### 按右 Command 没有反应

- 检查 Hammerspoon 是否正在运行。
- 检查“辅助功能”权限是否已经开启。
- 在 Hammerspoon 菜单中选择 Reload Config。
- 打开 Hammerspoon Console 查看红色错误信息。

### 能切换到豆包，但语音框没有出现

- 检查豆包语音快捷键是否为“单击左 Option”。
- 适当增大 `DOUBAO_READY_DELAY`。
- 确保豆包输入法已经在 macOS 输入法列表中启用。

### 提示“不要双击左 Option”

- 检查 `init.lua` 中是否重复写了多次 `require("doubao_voice")`。
- 检查是否还有另一段脚本也在模拟左 Option。
- 重新加载一次 Hammerspoon 配置，清理旧监听器。

### 语音框刚出现就自动关闭

新版带有启动保护时间。确认使用的是仓库最新脚本，并避免同时按住左右 Command。

### 停止后没有恢复原输入法

确认原输入法仍在 macOS 的输入法列表中。脚本通过输入源 ID 恢复，若原输入法被系统禁用，将无法切回。

## 工作原理

脚本不是固定等待一段时间后盲目按键，而是按以下顺序工作：

```text
右 Command
  → 请求切换到豆包输入法
  → 检查豆包输入源是否真正生效
  → 等待豆包完成准备
  → 模拟单击左 Option
  → 再次按右 Command 时停止语音
  → 恢复之前的输入源 ID
```

## 隐私说明

脚本只进行三类本地操作：

- 监听右 Command。
- 切换 macOS 输入法。
- 模拟左 Option 按键。

脚本不访问麦克风、不读取输入内容、不连接网络，也不收集任何数据。实际语音识别由豆包输入法完成，其隐私规则以豆包输入法自身说明为准。

## 许可证

[MIT License](LICENSE)

