# 长期记忆系统与情绪状态持久化设计

## 概述

本设计实现长期记忆系统和情绪状态持久化功能，让 AI 能够记住用户的个人信息、重要事件、偏好习惯，并保持情绪状态的连续性。

## 需求总结

| 维度 | 选择 |
|------|------|
| 长期记忆用途 | 完整记忆（个人信息、事件约定、偏好习惯） |
| 存储方式 | 混合方案（SQLite + 向量数据库） |
| 记忆提取方式 | 智能触发（关键词判断 + LLM 提取） |
| 情绪持久化范围 | 完整记录（状态 + 历史 + 触发原因） |
| 实现方式 | 分阶段实现 |

## 第一阶段：情绪状态持久化

### 模块结构

```
src/
├── chat/
│   ├── emotions.py            # 现有：情绪分析（需修改）
│   └── emotion_store.py       # 新增：情绪持久化存储
├── app/
│   └── .cache.sqlite          # 现有数据库（新增表）
```

### 数据库表设计

```sql
-- 情绪状态表：存储情绪历史
CREATE TABLE emotion_states (
    id INTEGER PRIMARY KEY,
    session_id TEXT,               -- 关联会话
    emotion_type TEXT NOT NULL,    -- 情绪类型
    emotion_intensity REAL,        -- 情绪强度
    trigger_text TEXT,             -- 触发情绪的文本
    trigger_source TEXT,           -- 触发来源（user/assistant）
    created_at DATETIME,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);
```

### EmotionStore 类接口

```python
# src/chat/emotion_store.py

class EmotionStore:
    """情绪状态持久化管理器"""
    
    def __init__(self, db_path: str):
        """初始化存储器，连接数据库"""
    
    # ===== 情绪记录 =====
    def save_emotion(
        self,
        session_id: str,
        emotion_type: str,
        emotion_intensity: float,
        trigger_text: str = None,
        trigger_source: str = None
    ) -> int:
        """保存情绪状态，返回记录ID"""
    
    def get_current_emotion(self) -> Optional[dict]:
        """获取当前情绪状态"""
    
    def get_emotion_history(self, limit: int = 20) -> list[dict]:
        """获取情绪历史记录"""
    
    # ===== 情绪分析 =====
    def get_emotion_trend(self, hours: int = 24) -> dict:
        """分析情绪趋势（如：最近24小时情绪分布）"""
    
    def get_dominant_emotion(self, hours: int = 24) -> str:
        """获取主导情绪类型"""
    
    def get_emotion_triggers(self, emotion_type: str, limit: int = 10) -> list[str]:
        """获取特定情绪的触发文本"""
    
    # ===== 清理 =====
    def cleanup_old_emotions(self, days: int = 30) -> int:
        """清理旧情绪记录"""
```

### 修改 EmotionAnalyzer 类

```python
class EmotionAnalyzer:
    def __init__(self, emotion_store: EmotionStore = None):
        self._store = emotion_store
        self._current_emotion = "neutral"
        self._current_intensity = 0.0
    
    def analyze(self, text: str, session_id: str = None) -> tuple[str, float]:
        """分析情绪并持久化"""
        emotion_type, intensity = self._analyze_text(text)
        
        # 更新当前情绪
        self._current_emotion = emotion_type
        self._current_intensity = intensity
        
        # 持久化情绪状态
        if self._store and session_id:
            self._store.save_emotion(
                session_id=session_id,
                emotion_type=emotion_type,
                emotion_intensity=intensity,
                trigger_text=text,
                trigger_source="user"
            )
        
        return emotion_type, intensity
    
    def restore_emotion(self):
        """从数据库恢复情绪状态"""
        if self._store:
            current = self._store.get_current_emotion()
            if current:
                self._current_emotion = current['emotion_type']
                self._current_intensity = current['emotion_intensity']
    
    def get_emotion_trend_context(self) -> str:
        """获取情绪趋势上下文（用于 Prompt）"""
        if not self._store:
            return ""
        
        trend = self._store.get_emotion_trend(hours=24)
        dominant = self._store.get_dominant_emotion(hours=24)
        
        return f"最近情绪以{dominant}为主，情绪分布：{trend}"
```

## 第二阶段：长期记忆系统

### 模块结构

```
src/
├── chat/
│   ├── memory_store.py        # 新增：长期记忆存储
│   └── memory_extractor.py    # 新增：记忆提取器
├── app/
│   └── .cache.sqlite          # 现有数据库（新增表）
├── data/
│   └── chroma/                # 向量数据库存储目录
```

### 数据库表设计

```sql
-- 长期记忆表：存储结构化记忆
CREATE TABLE memories (
    id INTEGER PRIMARY KEY,
    memory_type TEXT NOT NULL,     -- 类型：profile/event/preference
    memory_key TEXT,               -- 键：如 'name', 'city', 'favorite_game'
    memory_value TEXT,             -- 值：如 '李奇楠', '枣庄'
    source_text TEXT,              -- 原始文本
    confidence REAL,               -- 置信度
    created_at DATETIME,
    updated_at DATETIME,
    is_active INTEGER DEFAULT 1
);

-- 向量记忆表：存储向量嵌入的元数据
CREATE TABLE vector_memories (
    id INTEGER PRIMARY KEY,
    memory_id INTEGER,             -- 关联 memories 表
    vector_id TEXT,                -- 向量数据库中的ID
    created_at DATETIME,
    FOREIGN KEY (memory_id) REFERENCES memories(id)
);
```

### MemoryStore 类接口

```python
# src/chat/memory_store.py

class MemoryStore:
    """长期记忆存储管理器"""
    
    def __init__(self, db_path: str, vector_db_path: str = None):
        """初始化存储器，连接数据库和向量数据库"""
    
    # ===== 记忆管理 =====
    def save_memory(
        self,
        memory_type: str,       # profile/event/preference
        memory_key: str,
        memory_value: str,
        source_text: str = None,
        confidence: float = 1.0
    ) -> int:
        """保存记忆，返回记忆ID"""
    
    def get_memory(self, memory_key: str) -> Optional[str]:
        """获取特定记忆"""
    
    def get_all_memories(self, memory_type: str = None) -> list[dict]:
        """获取所有记忆（可按类型筛选）"""
    
    def update_memory(self, memory_key: str, memory_value: str) -> bool:
        """更新记忆"""
    
    def delete_memory(self, memory_key: str):
        """删除记忆"""
    
    # ===== 向量检索 =====
    def search_similar_memories(self, query: str, k: int = 5) -> list[dict]:
        """语义相似性检索记忆"""
    
    def get_context_for_prompt(self, query: str = None) -> str:
        """生成用于 Prompt 的记忆上下文"""
    
    # ===== 清理 =====
    def cleanup_duplicate_memories(self):
        """清理重复记忆"""
```

### MemoryExtractor 类接口

```python
# src/chat/memory_extractor.py

class MemoryExtractor:
    """从对话中提取记忆"""
    
    # 触发记忆提取的关键词
    TRIGGER_KEYWORDS = [
        "我叫", "我是", "我住", "我在", "我喜欢", "我讨厌", 
        "我生日", "我今年", "我的生日", "我职业",
        "记住", "别忘了", "记得", "提醒我",
        "约定", "答应", "承诺", "下次"
    ]
    
    def __init__(self, llm: ChatOpenAI, memory_store: MemoryStore):
        """初始化提取器"""
    
    def should_extract(self, text: str) -> bool:
        """判断是否需要提取记忆"""
    
    def extract_memories(self, user_input: str, ai_response: str) -> list[dict]:
        """从对话中提取记忆"""
    
    def _extract_with_llm(self, user_input: str, ai_response: str) -> list[dict]:
        """使用 LLM 提取记忆"""
```

## 与现有代码集成

### 修改 ChatGraph 类

```python
class ChatGraph:
    def __init__(self, config_path: str = None):
        # ... 现有初始化代码 ...
        
        # 新增：情绪存储和记忆系统
        self._emotion_store = EmotionStore(self._get_db_path())
        self._memory_store = MemoryStore(self._get_db_path())
        self._memory_extractor = MemoryExtractor(self._llm, self._memory_store)
        
        # 恢复情绪状态
        self._emotion_analyzer = EmotionAnalyzer(self._emotion_store)
        self._emotion_analyzer.restore_emotion()
    
    def _build_system_prompt(self, emotion_type: str, user_input: str, user_city: str) -> str:
        # ... 现有代码 ...
        
        # 新增：注入记忆上下文
        memory_context = self._memory_store.get_context_for_prompt(user_input)
        
        # 新增：注入情绪趋势
        emotion_trend = self._emotion_analyzer.get_emotion_trend_context()
        
        # 构建完整 prompt
        # ...
    
    def _persist_result(self, user_input: str, final_response: str, user_city: str):
        # ... 现有持久化代码 ...
        
        # 新增：提取记忆
        if self._memory_extractor.should_extract(user_input):
            memories = self._memory_extractor.extract_memories(user_input, final_response)
            for mem in memories:
                self._memory_store.save_memory(**mem)
```

## 数据流

```
用户输入
    │
    ▼
ChatGraph._build_initial_state()
    ├─ EmotionAnalyzer.restore_emotion() ← 恢复上次情绪
    └─ MemoryStore.get_context_for_prompt() ← 获取相关记忆
    │
    ▼
ChatGraph._build_system_prompt()
    ├─ 注入情绪趋势上下文
    ├─ 注入记忆上下文
    ├─ 注入对话摘要
    └─ 注入最近对话历史
    │
    ▼
LLM 调用 → 生成回复
    │
    ▼
ChatGraph._persist_result()
    ├─ ConversationStore.save_message() ← 保存消息
    ├─ EmotionStore.save_emotion() ← 保存情绪
    └─ MemoryExtractor.extract_memories() ← 提取记忆
        └─ MemoryStore.save_memory() ← 保存记忆
```

## Prompt 注入格式

```
【用户画像】
- 名字：李奇楠
- 城市：枣庄
- 喜好：打游戏、唱歌

【重要约定】
- 答应给用户唱歌
- 约定下次聊游戏

【之前的对话记忆】
我们之前聊过天气，你告诉过我你在北京，还说喜欢我陪你看雨...

【最近情绪】
最近情绪以开心为主，今天聊得很愉快。

【最近对话】
用户: 我喜欢你
夏目安安: 谢谢你喜欢我...
...（最近6条）

【当前情绪】
现在心情平静。

【用户说】
{user_input}

【你的回复】
```

## 文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/chat/emotion_store.py` | 新增 | 情绪持久化存储 |
| `src/chat/memory_store.py` | 新增 | 长期记忆存储 |
| `src/chat/memory_extractor.py` | 新增 | 记忆提取器 |
| `src/chat/emotions.py` | 修改 | 集成情绪持久化 |
| `src/chat/graph.py` | 修改 | 集成记忆系统 |
| `requirements.txt` | 修改 | 添加 chromadb 依赖 |

## 依赖

```
chromadb>=0.4.0  # 向量数据库
```
