# Live2D 口型同步功能设计

## 概述

为 Live2D 桌面宠物添加口型同步功能，使模型在 TTS 语音播放时能够根据音频实时同步口型，提升交互的真实感和沉浸感。

## 目标

- 当 TTS 服务生成音频后，自动触发 Live2D 模型的口型同步
- 用户打断回复时，立即停止口型同步
- 保持现有文字显示逻辑不变

## 技术方案

### 方案选择：最小改动方案

在现有 TTS 音频回调中，将音频 URL 传递给前端 Live2D 模型，利用 `pixi-live2d-display-lipsyncpatch` 库的 `model.speak()` 方法实现口型同步。

### 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                         数据流向                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  TTS Service                                                    │
│       │                                                         │
│       ▼                                                         │
│  sentenceAudioReady 信号                                        │
│       │                                                         │
│       ▼                                                         │
│  ChatManager._on_tts_sentence_audio_ready()                     │
│       │                                                         │
│       ├──► 现有逻辑：更新 records 中的音频数据                    │
│       │                                                         │
│       └──► 新增逻辑：调用 WebBridge.speak_audio(url)            │
│                    │                                            │
│                    ▼                                            │
│              desktop.html                                       │
│                    │                                            │
│                    ▼                                            │
│              model.speak(url)  ──► 口型同步播放                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 文件改动清单

### 1. src/app/web_bridge.py

新增两个方法：

| 方法 | 功能 |
|------|------|
| `speak_audio(audio_url)` | 让 Live2D 模型播放音频并同步口型 |
| `stop_speaking()` | 停止 Live2D 模型的口型同步 |

### 2. public/desktop.html

新增两个 JavaScript 函数：

| 函数 | 功能 |
|------|------|
| `speakAudio(audioUrl)` | 调用 `model.speak()` 播放音频并同步口型 |
| `stopSpeaking()` | 调用 `model.stopSpeaking()` 停止播放 |

### 3. src/app/chat_manager.py

修改两个方法：

| 方法 | 改动 |
|------|------|
| `_on_tts_sentence_audio_ready()` | 新增调用 `speak_audio()` 触发口型同步 |
| `_interrupt_active_stream()` | 新增调用 `stop_speaking()` 停止口型 |

## 详细设计

### web_bridge.py 新增代码

```python
def speak_audio(self, audio_url: str):
    """让 Live2D 模型播放音频并同步口型"""
    if self._web_page and audio_url:
        escaped_url = audio_url.replace('\\', '\\\\').replace("'", "\\'")
        self._web_page.runJavaScript(f"speakAudio('{escaped_url}')")

def stop_speaking(self):
    """停止 Live2D 模型的口型同步"""
    if self._web_page:
        self._web_page.runJavaScript("stopSpeaking()")
```

### desktop.html 新增代码

```javascript
function speakAudio(audioUrl) {
    if (!model || !audioUrl) {
        return;
    }
    try {
        model.speak(audioUrl, {
            volume: 1.0,
            resetExpression: true,
            onFinish: function() {
                console.log('[Live2D] Audio playback finished');
            },
            onError: function(err) {
                console.error('[Live2D] Audio playback error:', err);
            }
        });
    } catch (e) {
        console.error('[Live2D] speakAudio failed:', e);
    }
}

function stopSpeaking() {
    if (model) {
        try {
            model.stopSpeaking();
        } catch (e) {
            console.error('[Live2D] stopSpeaking failed:', e);
        }
    }
}
```

### chat_manager.py 改动

#### _on_tts_sentence_audio_ready 方法

在现有逻辑后新增：

```python
# 新增：让 Live2D 模型同步口型
if self._window._bridge:
    self._window._bridge.speak_audio(data_url)
```

#### _interrupt_active_stream 方法

在方法开头新增：

```python
# 新增：停止 Live2D 口型同步
if self._window._bridge:
    self._window._bridge.stop_speaking()
```

## 时序图

```
用户发送消息
     │
     ▼
LLM 流式响应 ──► TTS 合成句子
     │
     ▼
TTS 音频就绪 ──► sentenceAudioReady 信号
     │
     ├──► 更新聊天记录（现有）
     │
     └──► WebBridge.speak_audio(url)
              │
              ▼
         model.speak(url)
              │
              ├──► 播放音频
              └──► 口型同步
              
用户打断 ──► _interrupt_active_stream()
              │
              └──► WebBridge.stop_speaking()
                        │
                        ▼
                   model.stopSpeaking()
```

## 边界情况处理

| 场景 | 处理方式 |
|------|---------|
| 模型未加载 | `speakAudio` 检查 `model` 是否存在 |
| 音频 URL 为空 | 提前返回，不调用 speak |
| 连续多句 | 由 TTS 队列控制，上一句播放完后触发下一句 |
| 用户打断 | 调用 `stopSpeaking()` 立即停止 |
| TTS 未开启 | 不触发口型同步逻辑 |

## 测试要点

1. **基础功能测试**
   - 开启 TTS 后发送消息，观察模型口型是否同步
   - 多句回复时，口型是否连续同步

2. **中断测试**
   - 在模型说话时发送新消息，口型是否立即停止
   - 在模型说话时关闭 TTS 功能，口型是否停止

3. **边界测试**
   - 模型未加载时开启 TTS，不应报错
   - 空音频 URL 时不应报错

## 依赖

- `pixi-live2d-display-lipsyncpatch` v0.5.0-ls-8（已集成）
- 现有 TTS 服务（通义千问 TTS）

## 风险评估

| 风险 | 等级 | 缓解措施 |
|------|------|---------|
| 音频播放延迟 | 低 | 使用 data URL 无网络延迟 |
| 口型不同步 | 低 | 由库自动处理，无需手动干预 |
| 内存泄漏 | 低 | 确保停止时正确清理资源 |
