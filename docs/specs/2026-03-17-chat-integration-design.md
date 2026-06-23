# Live2D桌宠聊天功能集成设计文档

## 概述

基于Langgraph对接大模型，搭配定制化悬浮聊天UI（气泡+输入框），支持交互控制与模型灵活切换，保障轻量化、高适配的聊天体验。

## 一、整体架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Live2D Desktop Pet                            │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                        UI层 (PyQt5)                             │    │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐                    │    │
│  │  │ 主窗口    │  │ 气泡窗口  │  │ 输入框窗口│                    │    │
│  │  │ Live2D    │  │ ChatBubble│  │ InputBox  │                    │    │
│  │  │ WebView   │  │ WebView   │  │ WebView   │                    │    │
│  │  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘                    │    │
│  │        └──────────────┼──────────────┘                          │    │
│  │                       ↓                                         │    │
│  │              ┌─────────────────┐                                │    │
│  │              │  WebChannel桥   │                                │    │
│  │              │  (跨窗口通信)   │                                │    │
│  │              └────────┬────────┘                                │    │
│  └───────────────────────┼─────────────────────────────────────────┘    │
│                          ↓                                              │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                     对话引擎层 (Langgraph)                       │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │    │
│  │  │ 情绪分析节点│→ │ 对话生成节点│→ │ 回复格式化  │              │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘              │    │
│  │         ↑                ↑                                       │    │
│  │  ┌─────────────┐  ┌─────────────┐                                │    │
│  │  │ 角色人设    │  │ 对话历史    │                                │    │
│  │  │ (Prompt模板)│  │ (Memory)    │                                │    │
│  │  └─────────────┘  └─────────────┘                                │    │
│  └───────────────────────┬─────────────────────────────────────────┘    │
│                          ↓                                              │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                     大模型适配层                                 │    │
│  │  ┌─────────────────────────────────────────────────────────┐    │    │
│  │  │           统一LLM接口 (Langchain兼容)                    │    │    │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐                  │    │    │
│  │  │  │ 通义千问│  │ DeepSeek│  │ OpenAI  │  ...             │    │    │
│  │  │  │(默认)   │  │         │  │         │                  │    │    │
│  │  │  └─────────┘  └─────────┘  └─────────┘                  │    │    │
│  │  └─────────────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

**核心设计原则：**
- **三层解耦**：UI层、对话引擎层、大模型适配层独立，通过接口通信
- **配置驱动**：大模型切换仅需修改配置文件，无需改动代码
- **渐进增强**：当前实现文字聊天，预留语音扩展接口

## 二、UI层详细设计

### 2.1 多窗口结构

```
┌────────────────────────────────────────────────────────────────────┐
│                         桌面屏幕                                    │
│                                                                    │
│     ┌──────────────────┐                                           │
│     │   气泡窗口        │  ← 无边框、透明背景、HTML渲染             │
│     │   ChatBubble     │  ← 倒三角指向人物头顶                     │
│     │   (动态宽度)      │  ← 可临时拖动，人物移动时重置位置         │
│     └────────┬─────────┘                                           │
│              │ ▼ (倒三角指向)                                       │
│     ┌────────┴─────────┐                                           │
│     │   主窗口          │  ← 现有Live2D窗口 (400x500)               │
│     │   Live2DWindow   │  ← 无边框、透明、可拖动                   │
│     │   [Live2D模型]   │                                           │
│     └────────┬─────────┘                                           │
│              │                                                      │
│     ┌────────┴─────────┐                                           │
│     │   输入框窗口      │  ← 无边框、透明背景、HTML渲染             │
│     │   InputBox       │  ← 胶囊状外形，阴影效果                   │
│     │   (280x50)       │  ← 可临时拖动，人物移动时重置位置         │
│     └──────────────────┘                                           │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### 2.2 气泡窗口设计

**HTML结构：**
```html
<div class="bubble-container">
  <div class="bubble">
    <div class="bubble-text" id="message">消息内容</div>
  </div>
  <div class="bubble-tail"></div>  <!-- 倒三角 -->
</div>
```

**样式规范：**
| 属性 | 值 | 说明 |
|------|-----|------|
| 最大宽度 | 280px | 避免过度拉伸 |
| 内边距 | 12px 16px | 舒适阅读 |
| 圆角 | 16px | 动漫简约风 |
| 背景 | rgba(255,255,255,0.95) | 半透明白色 |
| 阴影 | 0 4px 12px rgba(0,0,0,0.15) | 轻微浮起感 |
| 倒三角 | 10px | 指向人物头顶 |

### 2.3 输入框窗口设计

**HTML结构：**
```html
<div class="input-container">
  <input type="text" id="user-input" placeholder="和我聊聊吧～">
  <button id="send-btn">发送</button>
</div>
```

**样式规范：**
| 属性 | 值 | 说明 |
|------|-----|------|
| 尺寸 | 280x50 | 胶囊状 |
| 圆角 | 25px | 完整胶囊形 |
| 背景 | rgba(255,255,255,0.95) | 半透明白色 |
| 阴影 | 0 4px 10px rgba(0,0,0,0.1) | 轻微浮起感 |
| 发送按钮 | 圆角胶囊 | 空输入时置灰 |

### 2.4 窗口协同逻辑

```python
# 位置计算伪代码
def update_window_positions():
    main_x, main_y = main_window.pos()
    
    # 气泡：主窗口上方居中
    bubble_x = main_x + (400 - bubble_width) // 2
    bubble_y = main_y - bubble_height - 10
    bubble_window.move(bubble_x, bubble_y)
    
    # 输入框：主窗口下方居中
    input_x = main_x + (400 - 280) // 2
    input_y = main_y + 500 + 10
    input_window.move(input_x, input_y)
```

**拖动状态管理：**
- 用户拖动气泡/输入框 → 标记 `is_manually_moved = True`
- 主窗口移动时 → 检查标记，若为True则重置位置并清除标记

## 三、对话引擎层详细设计

### 3.1 Langgraph状态图

```
┌─────────────────────────────────────────────────────────────────────┐
│                      ChatGraph 状态图                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   ┌─────────────┐                                                   │
│   │   START     │                                                   │
│   └──────┬──────┘                                                   │
│          │ user_input                                               │
│          ↓                                                          │
│   ┌─────────────┐                                                   │
│   │ 情绪分析节点 │  ← 分析用户输入的情绪倾向                        │
│   │ analyze_    │     输出: emotion_type (happy/sad/angry/...)     │
│   │ emotion     │                                                   │
│   └──────┬──────┘                                                   │
│          │                                                          │
│          ↓                                                          │
│   ┌─────────────┐                                                   │
│   │ 对话生成节点 │  ← 结合人设+情绪+历史生成回复                    │
│   │ generate_   │     输出: response_text                          │
│   │ response    │                                                   │
│   └──────┬──────┘                                                   │
│          │                                                          │
│          ↓                                                          │
│   ┌─────────────┐                                                   │
│   │ 回复格式化  │  ← 添加颜文字、调整语气                           │
│   │ format_     │     输出: final_response                         │
│   │ response    │                                                   │
│   └──────┬──────┘                                                   │
│          │                                                          │
│          ↓                                                          │
│   ┌─────────────┐                                                   │
│   │    END      │                                                   │
│   └─────────────┘                                                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2 状态定义

```python
from typing import TypedDict
from langgraph.graph import StateGraph

class ChatState(TypedDict):
    user_input: str              # 用户输入
    emotion_type: str            # 情绪类型: happy/sad/angry/shy/lonely/...
    emotion_intensity: float     # 情绪强度: 0.0-1.0
    response_text: str           # 原始回复
    final_response: str          # 最终回复（含颜文字）
    history: list                # 对话历史
```

### 3.3 角色人设模板

从 `bot.py` 移植并优化：

```python
PERSONA_TEMPLATE = """
你是丛雨（Murasame），一个活泼可爱的虚拟少女桌宠。

【性格特征】
- 活泼开朗，偶尔会害羞
- 喜欢和主人聊天，对主人的生活很感兴趣
- 会用可爱的颜文字表达情绪
- 有时会撒娇，但很懂事

【说话风格】
- 语气轻松活泼，像朋友一样
- 适当使用颜文字（不要每句都用）
- 回复简洁，一般1-3句话
- 关心主人的状态

【当前情绪】
{emotion_context}

【对话历史】
{history}

【用户说】
{user_input}

【你的回复】
"""
```

### 3.4 情绪系统映射

从 `bot.py` 的 `MURASAME_FACES` 提取情绪类型：

| 情绪类型 | 触发关键词示例 | 颜文字示例 |
|---------|---------------|-----------|
| happy | 开心、高兴、喜欢、谢谢 | (｡•̀ᴗ-)✧ |
| shy | 害羞、脸红、喜欢你 | (⁄ ⁄•⁄ω⁄•⁄ ⁄) |
| lonely | 孤单、想你、不在 | (；′⌒`) |
| excited | 哇、太棒了、好耶 | ☆ ～('▽^人) |
| angry | 生气、讨厌、哼 | (｀皿´＃) |
| scared | 吓、可怕、害怕 | (ﾉﾟ⊿ﾟ)ﾉ |

### 3.5 对话历史管理

```python
from langchain.memory import ConversationBufferWindowMemory

# 保留最近5轮对话，避免上下文过长
memory = ConversationBufferWindowMemory(
    k=5,
    return_messages=True
)
```

## 四、大模型适配层详细设计

### 4.1 统一LLM接口

```python
from langchain_openai import ChatOpenAI

def create_llm_from_config(config_path: str = "config/llm_config.yaml") -> ChatOpenAI:
    """根据配置文件创建LLM实例"""
    config = load_llm_config(config_path)
    return ChatOpenAI(
        api_key=config['api_key'],
        base_url=config['base_url'],
        model=config['model_name'],
        temperature=config.get('temperature', 0.85),
        max_tokens=config.get('max_tokens', 500)
    )
```

### 4.2 配置文件格式

创建 `config/llm_config.yaml`：

```yaml
# 大模型配置文件
# 仅需修改三个参数即可切换模型

# 通义千问 (默认)
api_key: "your-dashscope-api-key"
base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1"
model_name: "qwen-turbo"

# 通用参数
temperature: 0.85
max_tokens: 500

# ===== 其他模型配置示例（注释掉）=====
# DeepSeek:
#   api_key: "your-deepseek-api-key"
#   base_url: "https://api.deepseek.com/v1"
#   model_name: "deepseek-chat"

# OpenAI:
#   api_key: "your-openai-api-key"
#   base_url: "https://api.openai.com/v1"
#   model_name: "gpt-4o-mini"
```

**切换模型只需三步：**
1. 修改 `api_key`
2. 修改 `base_url`
3. 修改 `model_name`

### 4.3 异常处理

```python
def safe_chat(llm, prompt: str) -> str:
    """带异常处理的对话调用"""
    try:
        response = llm.invoke(prompt)
        return response.content
    except Exception as e:
        error_msg = str(e).lower()
        
        if "api key" in error_msg or "unauthorized" in error_msg:
            return "API密钥配置有误，请检查配置文件～"
        elif "timeout" in error_msg or "connection" in error_msg:
            return "网络连接超时啦，稍后再试试～"
        elif "rate limit" in error_msg:
            return "请求太频繁了，让我休息一下～"
        else:
            return "暂时没法回复啦，再试试～"
```

## 五、功能控制层详细设计

### 5.1 菜单栏集成

在现有右键菜单和系统托盘菜单中添加聊天功能开关：

```python
# 右键菜单新增项
class Live2DWindow:
    def contextMenuEvent(self, event):
        menu = QMenu(self)
        
        # === 新增：聊天功能开关 ===
        chat_action = menu.addAction("聊天功能: 开启" if self.chat_enabled else "聊天功能: 关闭")
        chat_action.triggered.connect(self.toggle_chat)
        
        menu.addSeparator()
        
        # 原有菜单项...
```

### 5.2 聊天功能状态管理

```python
class ChatManager:
    """聊天功能管理器"""
    
    def __init__(self, bubble_window, input_window, chat_engine):
        self.bubble_window = bubble_window
        self.input_window = input_window
        self.chat_engine = chat_engine
        self._enabled = True
    
    @property
    def enabled(self) -> bool:
        return self._enabled
    
    def enable(self):
        """开启聊天功能"""
        self._enabled = True
        self.bubble_window.show()
        self.input_window.show()
    
    def disable(self):
        """关闭聊天功能"""
        self._enabled = False
        self.bubble_window.hide()
        self.input_window.hide()
    
    def toggle(self):
        """切换聊天功能状态"""
        if self._enabled:
            self.disable()
        else:
            self.enable()
        return self._enabled
```

### 5.3 完整交互流程

```
┌─────────────────────────────────────────────────────────────────────┐
│                      用户交互流程                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  用户点击输入框                                                      │
│       ↓                                                             │
│  输入框获取焦点 → 显示光标                                           │
│       ↓                                                             │
│  用户输入文字 → 实时检测输入状态                                      │
│       ↓                                                             │
│  ┌─────────────────────────────────────┐                            │
│  │ 输入为空？                          │                            │
│  │   是 → 发送按钮置灰，禁止提交        │                            │
│  │   否 → 发送按钮激活                 │                            │
│  └─────────────────────────────────────┘                            │
│       ↓                                                             │
│  用户点击发送/按回车                                                  │
│       ↓                                                             │
│  ┌─────────────────────────────────────┐                            │
│  │ 聊天功能是否开启？                   │                            │
│  │   否 → 忽略操作                     │                            │
│  │   是 → 继续                         │                            │
│  └─────────────────────────────────────┘                            │
│       ↓                                                             │
│  输入框清空 → 显示"思考中..."状态                                     │
│       ↓                                                             │
│  调用Langgraph对话引擎                                               │
│       ↓                                                             │
│  ┌─────────────────────────────────────┐                            │
│  │ 调用成功？                          │                            │
│  │   是 → 气泡显示回复内容              │                            │
│  │   否 → 气泡显示友好错误提示          │                            │
│  └─────────────────────────────────────┘                            │
│       ↓                                                             │
│  5秒后气泡自动隐藏（或用户交互时立即隐藏）                            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 六、文件结构与实现计划

### 6.1 新增文件结构

```
live2d隐藏任务栏版/
├── config/
│   └── llm_config.yaml          # [新增] 大模型配置文件
├── public/
│   ├── models/Mao/              # 现有模型资源
│   ├── desktop.html             # 现有Live2D页面
│   ├── bubble.html              # [新增] 气泡窗口HTML
│   └── input.html               # [新增] 输入框窗口HTML
├── src/
│   ├── app/
│   │   ├── main.py              # 现有入口
│   │   ├── window.py            # [修改] 主窗口，集成聊天功能
│   │   ├── web_bridge.py        # [修改] 通信桥，新增聊天接口
│   │   ├── tray.py              # [修改] 托盘，新增聊天开关
│   │   ├── bubble_window.py     # [新增] 气泡窗口类
│   │   ├── input_window.py      # [新增] 输入框窗口类
│   │   └── chat_manager.py      # [新增] 聊天功能管理器
│   └── chat/                    # [新增] 对话引擎模块
│       ├── __init__.py
│       ├── graph.py             # Langgraph状态图定义
│       ├── nodes.py             # 状态节点实现
│       ├── persona.py           # 角色人设模板
│       ├── emotions.py          # 情绪系统
│       └── llm_provider.py      # LLM配置加载
└── requirements.txt             # [修改] 新增依赖
```

### 6.2 依赖更新

```txt
# requirements.txt
PyQt5>=5.15
PyQtWebEngine>=5.15
langchain>=0.3.0
langchain-openai>=0.3.0
langgraph>=0.2.0
pyyaml>=6.0
```

### 6.3 实现计划（自顶向下）

| 阶段 | 任务 | 预计文件 |
|------|------|----------|
| **Phase 1: UI层基础** | | |
| 1.1 | 创建气泡窗口HTML | `public/bubble.html` |
| 1.2 | 创建输入框窗口HTML | `public/input.html` |
| 1.3 | 实现气泡窗口类 | `src/app/bubble_window.py` |
| 1.4 | 实现输入框窗口类 | `src/app/input_window.py` |
| 1.5 | 集成到主窗口，实现跟随逻辑 | `src/app/window.py` |
| **Phase 2: 对话引擎层** | | |
| 2.1 | 创建LLM配置文件和加载器 | `config/llm_config.yaml`, `src/chat/llm_provider.py` |
| 2.2 | 移植角色人设模板 | `src/chat/persona.py` |
| 2.3 | 移植情绪系统 | `src/chat/emotions.py` |
| 2.4 | 实现Langgraph状态图 | `src/chat/graph.py`, `src/chat/nodes.py` |
| **Phase 3: 功能控制层** | | |
| 3.1 | 实现聊天管理器 | `src/app/chat_manager.py` |
| 3.2 | 集成到右键菜单 | `src/app/window.py` |
| 3.3 | 集成到系统托盘 | `src/app/tray.py` |
| 3.4 | 更新WebBridge支持聊天通信 | `src/app/web_bridge.py` |
| **Phase 4: 测试与优化** | | |
| 4.1 | 端到端测试 | - |
| 4.2 | 异常处理完善 | - |
| 4.3 | 性能优化 | - |

## 七、设计决策记录

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 实施顺序 | 自顶向下 | 早期就能看到可视化效果，快速验证UI交互 |
| 气泡位置策略 | 固定偏移跟随 | 实现简单，Live2D头部位置变化不大 |
| 拖动行为 | 临时拖动+重置 | 允许用户调整，但人物移动时恢复整齐布局 |
| 框架选择 | Langgraph | 支持状态图、条件分支，便于后续语音功能扩展 |
| 窗口方案 | 双HTML窗口 | 满足独立悬浮需求，复用现有代码，样式灵活 |
| 配置格式 | 简化YAML | 仅需三参数切换模型，无需provider字段 |
