# 对话历史持久化与上下文压缩设计

## 概述

本设计实现对话历史的持久化存储和智能压缩，解决现有系统中对话历史仅在内存中、程序关闭后丢失的问题，同时通过上下文压缩控制 Token 消耗。

## 需求总结

| 维度 | 选择 |
|------|------|
| 持久化范围 | 完整会话状态（模块化架构） |
| 存储方案 | 混合方案（SQLite + 未来向量数据库） |
| 压缩策略 | 混合策略（滑动窗口 + 重要性 + 时间衰减） |
| 触发时机 | 智能触发（Token估算 + 事件触发） |
| 实现方式 | 渐进式实现（分两阶段） |

## 第一阶段：核心持久化

### 模块结构

```
src/
├── chat/
│   ├── graph.py              # 现有：对话流程图（需修改）
│   ├── conversation_store.py # 新增：对话持久化存储
│   └── context_compressor.py # 新增：上下文压缩器
├── app/
│   └── .cache.sqlite         # 现有数据库（新增表）
```

### 数据库表设计

在现有 `.cache.sqlite` 中新增以下表：

```sql
-- 会话表：管理对话会话
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,           -- 会话ID（UUID）
    model_name TEXT,               -- 使用的模型名称
    persona_name TEXT,             -- 角色名称
    created_at DATETIME,           -- 创建时间
    updated_at DATETIME,           -- 最后更新时间
    is_active INTEGER DEFAULT 1    -- 是否活跃
);

-- 消息表：存储对话消息
CREATE TABLE messages (
    id INTEGER PRIMARY KEY,
    session_id TEXT,               -- 关联会话
    role TEXT NOT NULL,            -- 'user' 或 'assistant'
    content TEXT NOT NULL,         -- 消息内容
    emotion_type TEXT,             -- 情绪类型
    emotion_intensity REAL,        -- 情绪强度
    created_at DATETIME,           -- 创建时间
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);

-- 摘要表：存储压缩后的对话摘要
CREATE TABLE summaries (
    id INTEGER PRIMARY KEY,
    session_id TEXT,               -- 关联会话
    summary_text TEXT,             -- 摘要内容
    message_range_start INTEGER,   -- 覆盖的消息起始ID
    message_range_end INTEGER,     -- 覆盖的消息结束ID
    created_at DATETIME,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);
```

### 核心类接口

#### ConversationStore 类

```python
# src/chat/conversation_store.py

class ConversationStore:
    """对话历史持久化管理器"""
    
    def __init__(self, db_path: str):
        """初始化存储器，连接数据库"""
    
    # ===== 会话管理 =====
    def create_session(self, model_name: str, persona_name: str) -> str:
        """创建新会话，返回会话ID"""
    
    def get_current_session(self) -> Optional[str]:
        """获取当前活跃会话ID"""
    
    def close_session(self, session_id: str):
        """关闭会话"""
    
    # ===== 消息管理 =====
    def save_message(
        self, 
        session_id: str,
        role: str, 
        content: str,
        emotion_type: str = None,
        emotion_intensity: float = None
    ) -> int:
        """保存单条消息，返回消息ID"""
    
    def load_messages(
        self, 
        session_id: str, 
        limit: int = 20
    ) -> list[dict]:
        """加载指定会话的最近消息"""
    
    def load_all_messages(self, session_id: str) -> list[dict]:
        """加载指定会话的所有消息"""
    
    # ===== 摘要管理 =====
    def save_summary(
        self,
        session_id: str,
        summary_text: str,
        message_range: tuple[int, int]
    ):
        """保存对话摘要"""
    
    def get_latest_summary(self, session_id: str) -> Optional[dict]:
        """获取最新的对话摘要"""
    
    # ===== 清理 =====
    def cleanup_old_sessions(self, days: int = 30) -> int:
        """清理旧会话，返回清理数量"""
```

#### ContextCompressor 类

```python
# src/chat/context_compressor.py

class ContextCompressor:
    """对话上下文压缩器"""
    
    # 配置常量
    MAX_TOKENS = 2000           # 触发压缩的Token阈值
    KEEP_RECENT_MESSAGES = 6    # 保留的最近完整消息数
    MIN_MESSAGES_TO_COMPRESS = 10  # 最少消息数才触发压缩
    
    def __init__(self, llm: ChatOpenAI):
        """初始化压缩器"""
    
    def estimate_tokens(self, messages: list) -> int:
        """估算消息列表的Token数量（简单估算：字符数/2）"""
    
    def should_compress(self, messages: list) -> bool:
        """判断是否需要压缩"""
    
    def compress(
        self, 
        messages: list,
        keep_recent: int = None
    ) -> tuple[str, list]:
        """
        压缩对话历史
        
        Args:
            messages: 完整消息列表
            keep_recent: 保留的最近消息数
            
        Returns:
            (摘要文本, 保留的最近消息列表)
        """
    
    def extract_key_facts(self, messages: list) -> list[str]:
        """从对话中提取关键事实（为未来长期记忆预留）"""
```

### 与现有代码集成

#### 修改 ChatGraph 类

```python
class ChatGraph:
    def __init__(self, config_path: str = None):
        # ... 现有初始化代码 ...
        
        # 新增：对话存储器
        self._store = ConversationStore(self._get_db_path())
        self._compressor = ContextCompressor(self._llm)
        self._current_session_id = None
        
        # 启动时恢复或创建会话
        self._init_session()
    
    def _init_session(self):
        """初始化会话：恢复上次会话或创建新会话"""
        self._current_session_id = self._store.get_current_session()
        
        if self._current_session_id:
            self._restore_history()
        else:
            self._current_session_id = self._store.create_session(
                model_name=self._model_name,
                persona_name=PERSONA_NAME
            )
    
    def _restore_history(self):
        """从数据库恢复对话历史"""
        messages = self._store.load_messages(self._current_session_id)
        
        for msg in messages:
            if msg['role'] == 'user':
                self._history.append(HumanMessage(content=msg['content']))
            else:
                self._history.append(AIMessage(content=msg['content']))
    
    def _persist_result(self, user_input: str, final_response: str, user_city: str):
        """持久化对话结果"""
        # 保存用户消息
        self._store.save_message(
            session_id=self._current_session_id,
            role='user',
            content=user_input
        )
        
        # 保存AI回复
        self._store.save_message(
            session_id=self._current_session_id,
            role='assistant',
            content=final_response,
            emotion_type=self._emotion_analyzer.current_emotion
        )
        
        # 内存历史（现有逻辑保持不变）
        self._history.append(HumanMessage(content=user_input))
        self._history.append(AIMessage(content=final_response))
        if len(self._history) > 10:
            self._history = self._history[-10:]
        self._user_city = user_city or self._user_city
    
    def _build_system_prompt(self, emotion_type: str, user_input: str, user_city: str) -> str:
        """构建系统提示词"""
        emotion_context = self._emotion_analyzer.get_context(emotion_type)
        
        # 获取摘要（如果有）
        summary = self._store.get_latest_summary(self._current_session_id)
        summary_text = f"【历史摘要】{summary['summary_text']}" if summary else ""
        
        # 格式化最近对话
        history_text = self._format_history()
        
        # ... 构建完整 prompt ...
    
    def _check_and_compress(self):
        """检查并执行压缩"""
        messages = self._store.load_all_messages(self._current_session_id)
        
        if self._compressor.should_compress(messages):
            summary, recent = self._compressor.compress(messages)
            
            self._store.save_summary(
                session_id=self._current_session_id,
                summary_text=summary,
                message_range=(messages[0]['id'], messages[-(KEEP_RECENT_MESSAGES+1)]['id'])
            )
    
    def close(self):
        """关闭时保存状态"""
        self._check_and_compress()
        self._store.close_session(self._current_session_id)
```

#### 修改 ChatManager 类

```python
class ChatManager:
    def __init__(self, window, chat_graph, parent=None):
        # ... 现有初始化代码 ...
        
        # 新增：监听程序关闭事件
        self._window._tray.quit_requested.connect(self._on_quit)
    
    def _on_quit(self):
        """程序退出前保存状态"""
        if self._chat_graph:
            self._chat_graph.close()
    
    def clear_history(self):
        """清空对话历史"""
        self._chat_graph.clear_history()
        self._records.clear()
        
        # 清空数据库
        self._chat_graph._store.cleanup_old_sessions(days=0)
```

### 数据流

```
用户输入
    │
    ▼
ChatManager._on_user_message()
    │
    ▼
ChatGraph.chat() / stream_chat()
    ├─ _init_session() ← 恢复/创建会话
    ├─ _restore_history() ← 加载历史消息
    ├─ _build_system_prompt() ← 注入摘要+历史
    ├─ LLM 调用
    └─ _persist_result() ← 保存消息到数据库
    │
    ▼
ConversationStore
    ├─ save_message() ← 写入 messages 表
    └─ get_latest_summary() ← 获取摘要
    │
    ▼
程序退出 / 会话切换
    ├─ _check_and_compress() ← 检查是否需要压缩
    │   └─ ContextCompressor.compress() ← 生成摘要
    ├─ save_summary() ← 保存摘要
    └─ close_session() ← 关闭会话
```

### 错误处理

```python
# ConversationStore 错误处理
class ConversationStore:
    def save_message(self, ...):
        try:
            # 数据库操作
        except sqlite3.Error as e:
            print(f"[ConversationStore] 保存消息失败: {e}")
            return -1
    
    def load_messages(self, ...):
        try:
            # 数据库操作
        except sqlite3.Error as e:
            print(f"[ConversationStore] 加载消息失败: {e}")
            return []

# ContextCompressor 错误处理
class ContextCompressor:
    def compress(self, messages):
        try:
            summary = self._llm.invoke(prompt)
            return summary.content, messages[-KEEP_RECENT_MESSAGES:]
        except Exception as e:
            print(f"[ContextCompressor] 压缩失败: {e}")
            return "", messages
```

### Prompt 注入格式

```
【历史摘要】
用户之前询问了北京明天的天气，AI 帮助查询并建议带伞。用户还创建了一个下午3点的待办提醒。

【最近对话】
用户: 今天心情不太好
夏目安安: 怎么了？愿意和我说说吗？
用户: 工作压力有点大
夏目安安: 辛苦了...有什么我可以帮你的吗？

【当前情绪】
现在心情平静。

【用户说】
{user_input}

【你的回复】
```

## 第二阶段：智能压缩（未来扩展）

- 实现重要性判断和关键事实提取
- 实现 Token 估算和智能触发
- 为未来长期记忆预留接口
- 支持情绪状态持久化

## 文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/chat/conversation_store.py` | 新增 | 对话持久化存储 |
| `src/chat/context_compressor.py` | 新增 | 上下文压缩器 |
| `src/chat/graph.py` | 修改 | 集成持久化和压缩 |
| `src/app/chat_manager.py` | 修改 | 添加退出保存逻辑 |
