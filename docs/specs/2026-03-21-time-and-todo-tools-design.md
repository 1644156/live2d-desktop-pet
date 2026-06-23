# 桌宠工具功能设计文档

## 概述

为 Live2D 桌宠应用新增两个核心工具功能：
1. **时间查询工具** - 支持当前时间、日期、农历、节气、倒计时查询
2. **智能提醒/待办系统** - 支持一次性提醒、重复提醒、待办管理、优先级分类

## 需求确认

| 功能模块 | 确认内容 |
|---------|---------|
| 时间查询 | 基础时间 + 农历 + 倒计时，使用 `zhdate` 库 |
| 提醒系统 | 全功能待办（一次性/重复/管理/优先级/分类/历史） |
| 提醒交互 | 气泡消息 + TTS 语音播报 |
| 架构方案 | 混合架构（时间查询为 Tool，提醒系统为独立后台服务） |

---

## 一、整体架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                           用户交互层                                 │
│                    (自然语言输入 → 气泡/语音输出)                     │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         ChatGraph (LangGraph)                       │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────────────────┐   │
│  │ 情绪分析    │ → │ LLM 生成    │ → │ Tool 调用               │   │
│  └─────────────┘   └─────────────┘   │  - get_weather          │   │
│                                      │  - get_time (新增)      │   │
│                                      │  - manage_todo (新增)   │   │
│                                      └─────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         工具层 (LangChain Tools)                    │
│  ┌───────────────────┐  ┌───────────────────────────────────────┐  │
│  │ get_time          │  │ manage_todo                           │  │
│  │ - 当前时间/日期    │  │ - 创建/查询/删除/完成 待办            │  │
│  │ - 农历/节气/节日   │  │ - 设置优先级/分类                     │  │
│  │ - 倒计时计算       │  │ - 写入 SQLite 数据库                  │  │
│  └───────────────────┘  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      后台服务层 (独立运行)                           │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │                    ReminderService                             │ │
│  │  - 定时扫描待办数据库                                          │ │
│  │  - 触发提醒 → 气泡消息 + TTS 播报                              │ │
│  │  - 处理重复提醒的下次触发                                      │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         数据存储层 (SQLite)                         │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │  todos 表                                                      │ │
│  │  - id, content, priority, category, status                    │ │
│  │  - remind_at, repeat_type, repeat_interval                    │ │
│  │  - created_at, completed_at, history                          │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

**核心设计思路**：
1. **时间查询**：纯 Tool 实现，即时响应
2. **待办管理**：Tool 负责数据操作，独立后台服务负责定时触发
3. **数据存储**：复用现有 SQLite，新增 `todos` 表

---

## 二、时间查询工具 (`get_time`)

### 2.1 功能清单

| 查询类型 | 示例输入 | 输出示例 |
|---------|---------|---------|
| 当前时间 | "现在几点了" | "主人，现在是 2026年03月21日 14:30:15（周五）～" |
| 当前日期 | "今天几号" | "今天是 2026年03月21日，星期五～" |
| 农历日期 | "农历几号" | "农历二月十二，春分节气～" |
| 星期 | "今天星期几" | "今天是星期五～" |
| 节气/节日 | "今天什么节日" | "今天是春分节气，万物复苏呢～" |
| 倒计时 | "离国庆还有几天" | "距离国庆节还有 194 天哦～" |
| 天数差 | "今年过了多少天" | "今年已经过去 80 天啦～" |

### 2.2 Tool 接口设计

```python
@tool
def get_time(query_type: str = "now", target: str = None) -> str:
    """
    查询时间、日期、农历、倒计时等信息。
    
    Args:
        query_type: 查询类型
            - "now": 当前时间
            - "date": 当前日期
            - "lunar": 农历日期
            - "weekday": 星期几
            - "festival": 节气/节日
            - "countdown": 倒计时（需提供 target）
            - "days_passed": 今年已过天数
        target: 目标日期/事件（用于倒计时）
            - 支持："国庆"、"春节"、"元旦"、"五一"、"端午"、"中秋"等节日
            - 支持："2026-06-01" 等具体日期
            - 支持："生日"（需用户预设）
    """
```

### 2.3 节日映射表

```python
FESTIVALS = {
    # 公历节日
    "元旦": (1, 1),
    "五一": (5, 1),
    "国庆": (10, 1),
    
    # 农历节日（需动态计算）
    "春节": "lunar_new_year",        # 农历正月初一
    "元宵": "lunar_lantern",          # 农历正月十五
    "端午": "lunar_dragon_boat",      # 农历五月初五
    "中秋": "lunar_mid_autumn",       # 农历八月十五
    "重阳": "lunar_double_ninth",     # 农历九月初九
    
    # 节气（需动态计算）
    "清明": "solar_term",
    "春分": "solar_term",
    "夏至": "solar_term",
    "秋分": "solar_term",
    "冬至": "solar_term",
}
```

### 2.4 核心实现逻辑

```python
class TimeService:
    """时间查询服务"""
    
    def get_current_time(self) -> str:
        """获取当前时间（含农历）"""
        now = datetime.now()
        lunar = self._get_lunar_info(now)
        weekday = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][now.weekday()]
        return f"{now.strftime('%Y年%m月%d日 %H:%M:%S')}（{weekday} {lunar}）"
    
    def get_lunar_info(self) -> str:
        """获取农历信息"""
        now = datetime.now()
        lunar_date = ZhDate.from_datetime(now)
        solar_term = self._get_current_solar_term(now)
        return f"农历{lunar_date.cn_month}{lunar_date.cn_day}，{solar_term}"
    
    def calculate_countdown(self, target: str) -> str:
        """计算倒计时"""
        target_date = self._parse_target(target)
        days = (target_date - datetime.now().date()).days
        return f"距离{target}还有 {days} 天"
```

---

## 三、待办管理工具 (`manage_todo`)

### 3.1 功能清单

| 操作类型 | 示例输入 | 输出示例 |
|---------|---------|---------|
| 创建一次性提醒 | "10分钟后提醒我喝水" | "好的！我会在 14:40 提醒你喝水～" |
| 创建定时提醒 | "下午3点提醒我开会" | "已设置！下午 15:00 会提醒你开会～" |
| 创建重复提醒 | "每45分钟提醒我休息" | "好的！我会每 45 分钟提醒你休息～" |
| 查看待办 | "我有哪些待办事项" | "你有 3 个待办：1.喝水(14:40) 2.开会(15:00) ..." |
| 完成待办 | "完成喝水提醒" | "太棒了！'喝水提醒' 已标记完成～" |
| 删除待办 | "删除开会的提醒" | "已删除 '开会' 的提醒～" |
| 设置优先级 | "把开会提醒设为高优先级" | "已将 '开会' 设为高优先级～" |
| 设置分类 | "把喝水提醒归类到健康" | "已将 '喝水' 归类到健康～" |

### 3.2 Tool 接口设计

```python
@tool
def manage_todo(
    action: str,
    content: str = None,
    remind_at: str = None,
    repeat_type: str = None,
    repeat_interval: int = None,
    priority: str = None,
    category: str = None,
    todo_id: int = None
) -> str:
    """
    管理待办事项和提醒。
    
    Args:
        action: 操作类型
            - "create": 创建待办
            - "list": 查看待办列表
            - "complete": 完成待办
            - "delete": 删除待办
            - "update": 更新待办（优先级/分类）
        content: 待办内容（create 时必填）
        remind_at: 提醒时间（支持自然语言，如 "14:30"、"10分钟后"、"下午3点"）
        repeat_type: 重复类型
            - None: 不重复
            - "interval": 间隔重复（如每45分钟）
            - "daily": 每天重复
            - "weekly": 每周重复
        repeat_interval: 重复间隔（repeat_type="interval" 时使用，单位分钟）
        priority: 优先级
            - "low": 低
            - "normal": 普通（默认）
            - "high": 高
            - "urgent": 紧急
        category: 分类标签（如 "工作"、"健康"、"学习"）
        todo_id: 待办ID（complete/delete/update 时使用）
    """
```

### 3.3 数据库表设计

```sql
-- 待办事项表
CREATE TABLE todos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,              -- 待办内容
    status TEXT DEFAULT 'pending',      -- pending/completed/cancelled
    priority TEXT DEFAULT 'normal',     -- low/normal/high/urgent
    category TEXT DEFAULT 'default',    -- 分类标签
    remind_at DATETIME,                 -- 提醒时间
    repeat_type TEXT,                   -- interval/daily/weekly
    repeat_interval INTEGER,            -- 间隔分钟数
    last_triggered_at DATETIME,         -- 上次触发时间
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME,
    is_active INTEGER DEFAULT 1         -- 是否启用
);

-- 提醒历史表
CREATE TABLE todo_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    todo_id INTEGER,
    action TEXT,                        -- created/completed/deleted/triggered
    triggered_at DATETIME,
    FOREIGN KEY (todo_id) REFERENCES todos(id)
);

-- 索引
CREATE INDEX idx_todos_remind_at ON todos(remind_at);
CREATE INDEX idx_todos_status ON todos(status);
CREATE INDEX idx_todos_is_active ON todos(is_active);
```

---

## 四、后台提醒服务 (`ReminderService`)

### 4.1 服务架构

```python
class ReminderService(QObject):
    """后台提醒服务 - 定时扫描待办并触发提醒"""
    
    reminder_triggered = pyqtSignal(dict)  # 提醒触发信号
    
    def __init__(self, db: TodoDatabase, check_interval_ms: int = 60000):
        """
        Args:
            db: 待办数据库实例
            check_interval_ms: 扫描间隔，默认 60 秒
        """
```

### 4.2 核心工作流程

```
┌─────────────────────────────────────────────────────────────┐
│                    ReminderService                          │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    │
│  │ 定时扫描    │ →  │ 查询数据库  │ →  │ 检查触发    │    │
│  │ (每60秒)    │    │ 待办列表    │    │ 条件        │    │
│  └─────────────┘    └─────────────┘    └──────┬──────┘    │
│                                                │            │
│                                                ▼            │
│                     ┌─────────────────────────────────┐    │
│                     │ 是否到提醒时间？                 │    │
│                     └─────────────┬───────────────────┘    │
│                                   │                         │
│                    ┌──────────────┴──────────────┐         │
│                    ▼                             ▼         │
│              【是】触发提醒               【否】继续等待    │
│                    │                                        │
│                    ▼                                        │
│         ┌─────────────────────┐                            │
│         │ 发出信号            │                            │
│         │ reminder_triggered  │                            │
│         └──────────┬──────────┘                            │
│                    │                                        │
│                    ▼                                        │
│         ┌─────────────────────┐                            │
│         │ 更新待办状态        │                            │
│         │ - 一次性：标记完成  │                            │
│         │ - 重复：计算下次    │                            │
│         └─────────────────────┘                            │
└─────────────────────────────────────────────────────────────┘
```

### 4.3 触发条件判断逻辑

```python
def should_trigger(self, todo: dict) -> bool:
    """判断是否应该触发提醒"""
    now = datetime.now()
    remind_at = todo['remind_at']
    
    # 已触发过且未到下次时间
    if todo['last_triggered_at']:
        if todo['repeat_type'] == 'interval':
            next_time = todo['last_triggered_at'] + timedelta(minutes=todo['repeat_interval'])
            if now < next_time:
                return False
    
    # 到达提醒时间（允许 1 分钟误差）
    return abs((now - remind_at).total_seconds()) <= 60
```

### 4.4 与 ChatManager 集成

```python
class ChatManager:
    def __init__(self, window, chat_graph):
        # ... 现有代码 ...
        
        # 初始化提醒服务
        self._reminder_db = TodoDatabase(db_path)
        self._reminder_service = ReminderService(self._reminder_db)
        self._reminder_service.reminder_triggered.connect(self._on_reminder_triggered)
        self._reminder_service.start()
    
    def _on_reminder_triggered(self, todo: dict):
        """处理提醒触发"""
        # 1. 显示气泡消息
        message = f"主人！{todo['content']}～"
        self._window.show_bubble_message(message)
        
        # 2. 如果 TTS 开启，语音播报
        if self.tts_enabled and self._tts_service:
            self._tts_service.speak_sentence(message, 0)
```

---

## 五、自然语言时间解析 (`TimeParser`)

### 5.1 支持的时间格式

| 类型 | 示例 | 解析结果 |
|------|------|---------|
| 相对时间 | "10分钟后"、"半小时后" | now + offset |
| 时间点 | "下午3点"、"早上8点" | 今天 HH:MM |
| 日期时间 | "明天早上8点"、"后天下午2点" | 日期 + 时间 |
| 星期 | "下周一早上9点" | 下个周一 + 时间 |
| 重复间隔 | "每45分钟"、"每小时" | repeat_type + interval |

### 5.2 解析器实现

```python
class TimeParser:
    """自然语言时间解析器"""
    
    PATTERNS = [
        (r"(\d+)分钟后", "_parse_minutes_later"),
        (r"(\d+)小时后", "_parse_hours_later"),
        (r"半小时后", "_parse_half_hour_later"),
        (r"(下午|上午)(\d+)点(?:半)?", "_parse_time_of_day"),
        (r"(明天|后天)(.+)", "_parse_relative_day"),
        (r"每(\d+)(分钟|小时)", "_parse_repeat_interval"),
        (r"每天(.+)", "_parse_daily_repeat"),
        (r"每周([一二三四五六日])(.+)", "_parse_weekly_repeat"),
    ]
    
    def parse_remind_time(self, text: str) -> tuple[datetime, str, int]:
        """
        解析提醒时间
        
        Returns:
            (remind_at, repeat_type, repeat_interval)
        """
        text = text.strip()
        
        for pattern, method_name in self.PATTERNS:
            match = re.search(pattern, text)
            if match:
                method = getattr(self, method_name)
                return method(match, text)
        
        return None, None, None
```

---

## 六、文件结构与模块组织

### 6.1 新增文件结构

```
src/
├── chat/
│   ├── tools/
│   │   ├── __init__.py          # 更新：导出新工具
│   │   ├── weather.py           # 现有
│   │   ├── time_tool.py         # 新增：时间查询工具
│   │   └── todo_tool.py         # 新增：待办管理工具
│   └── ...
│
├── reminder/                     # 新增：提醒服务模块
│   ├── __init__.py
│   ├── service.py               # ReminderService 后台服务
│   ├── time_parser.py           # 自然语言时间解析
│   └── db.py                    # 待办数据库操作
│
└── app/
    ├── main.py                  # 更新：初始化提醒服务
    ├── chat_manager.py          # 更新：集成提醒服务
    └── ...
```

### 6.2 模块职责说明

| 模块 | 职责 | 依赖 |
|------|------|------|
| `tools/time_tool.py` | 时间查询 Tool，处理即时查询请求 | zhdate, datetime |
| `tools/todo_tool.py` | 待办管理 Tool，处理 CRUD 操作 | reminder/db.py |
| `reminder/service.py` | 后台定时服务，扫描并触发提醒 | PyQt5, db.py |
| `reminder/time_parser.py` | 解析自然语言时间描述 | datetime, re |
| `reminder/db.py` | SQLite 数据库操作封装 | sqlite3 |

### 6.3 模块接口设计

```python
# reminder/db.py
class TodoDatabase:
    """待办数据库操作"""
    
    def __init__(self, db_path: str):
        self._db_path = db_path
        self._init_tables()
    
    def create_todo(self, **kwargs) -> int:
        """创建待办，返回 ID"""
        
    def get_pending_todos(self) -> list[dict]:
        """获取所有待处理的待办"""
        
    def get_todos_by_status(self, status: str) -> list[dict]:
        """按状态获取待办"""
        
    def update_todo(self, todo_id: int, **kwargs) -> bool:
        """更新待办"""
        
    def complete_todo(self, todo_id: int) -> bool:
        """完成待办"""
        
    def delete_todo(self, todo_id: int) -> bool:
        """删除待办"""
        
    def record_trigger(self, todo_id: int) -> bool:
        """记录触发历史"""
```

---

## 七、错误处理与边界情况

### 7.1 错误处理策略

| 场景 | 处理方式 | 用户提示 |
|------|---------|---------|
| 时间解析失败 | 返回 None，让 LLM 重新询问 | "主人，我没听懂这个时间呢，能再说清楚一点吗？" |
| 数据库操作失败 | 捕获异常，记录日志 | "哎呀，保存失败了，再试一次吧～" |
| 提醒时间已过期 | 拒绝创建，提示用户 | "这个时间已经过去了哦，要设置未来的时间～" |
| 重复提醒间隔过短 | 限制最小间隔 5 分钟 | "间隔太短啦，最少要 5 分钟哦～" |
| 待办数量过多 | 限制最多 50 个待办 | "待办太多啦，先完成一些再添加吧～" |
| TTS 服务不可用 | 仅显示气泡，跳过语音 | 正常显示气泡消息 |

### 7.2 边界情况处理

```python
# 时间解析边界情况
class TimeParser:
    def parse_remind_time(self, text: str) -> tuple:
        # 边界 1: 空输入
        if not text or not text.strip():
            return None, None, None
        
        # 边界 2: 时间已过期
        remind_at = self._do_parse(text)
        if remind_at and remind_at < datetime.now():
            raise ValueError("TIME_PASSED")
        
        # 边界 3: 间隔过短
        if repeat_type == "interval" and repeat_interval < 5:
            raise ValueError("INTERVAL_TOO_SHORT")
        
        return remind_at, repeat_type, repeat_interval
```

```python
# 待办创建边界情况
class TodoDatabase:
    def create_todo(self, **kwargs) -> int:
        # 边界 1: 待办数量限制
        pending_count = len(self.get_pending_todos())
        if pending_count >= 50:
            raise ValueError("TODO_LIMIT_EXCEEDED")
        
        # 边界 2: 内容长度限制
        content = kwargs.get('content', '')
        if len(content) > 200:
            content = content[:200] + "..."
        
        # 边界 3: 优先级校验
        valid_priorities = ['low', 'normal', 'high', 'urgent']
        if kwargs.get('priority') not in valid_priorities:
            kwargs['priority'] = 'normal'
```

### 7.3 Tool 错误响应格式

```python
@tool
def manage_todo(action: str, **kwargs) -> str:
    try:
        result = _do_action(action, kwargs)
        return f"成功！{result}"
    except ValueError as e:
        error_code = str(e)
        error_messages = {
            "TIME_PASSED": "这个时间已经过去了哦～",
            "INTERVAL_TOO_SHORT": "间隔太短啦，最少要 5 分钟～",
            "TODO_LIMIT_EXCEEDED": "待办太多啦，先完成一些再添加～",
            "TODO_NOT_FOUND": "找不到这个待办呢～",
        }
        return error_messages.get(error_code, "操作失败啦，再试试～")
    except Exception as e:
        print(f"[manage_todo] 错误: {e}")
        return "哎呀，出错了，稍后再试～"
```

---

## 八、测试策略

### 8.1 测试层次

```
┌─────────────────────────────────────────────────────────────┐
│                      测试金字塔                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                    ┌─────────┐                              │
│                    │ E2E 测试 │  (集成测试)                  │
│                    └────┬────┘                              │
│                         │                                   │
│              ┌──────────┴──────────┐                        │
│              │    服务集成测试     │  (ReminderService)      │
│              └──────────┬──────────┘                        │
│                         │                                   │
│        ┌────────────────┴────────────────┐                  │
│        │         Tool 单元测试            │  (get_time,     │
│        │                                  │   manage_todo)  │
│        └────────────────┬────────────────┘                  │
│                         │                                   │
│  ┌──────────────────────┴──────────────────────┐            │
│  │              工具类单元测试                   │            │
│  │  (TimeParser, TodoDatabase)                  │            │
│  └──────────────────────────────────────────────┘            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 8.2 单元测试用例

#### TimeParser 测试

```python
class TestTimeParser:
    def test_parse_minutes_later(self):
        """测试 'X分钟后' 解析"""
        parser = TimeParser()
        remind_at, _, _ = parser.parse_remind_time("10分钟后")
        expected = datetime.now() + timedelta(minutes=10)
        assert abs((remind_at - expected).total_seconds()) < 5
    
    def test_parse_time_of_day(self):
        """测试 '下午X点' 解析"""
        remind_at, _, _ = parser.parse_remind_time("下午3点")
        assert remind_at.hour == 15
    
    def test_parse_relative_day(self):
        """测试 '明天早上X点' 解析"""
        remind_at, _, _ = parser.parse_remind_time("明天早上8点")
        assert remind_at.hour == 8
        assert remind_at.date() == (datetime.now() + timedelta(days=1)).date()
    
    def test_parse_repeat_interval(self):
        """测试重复间隔解析"""
        _, repeat_type, interval = parser.parse_remind_time("每45分钟提醒我")
        assert repeat_type == "interval"
        assert interval == 45
```

#### TodoDatabase 测试

```python
class TestTodoDatabase:
    def test_create_todo(self, tmp_path):
        """测试创建待办"""
        db = TodoDatabase(tmp_path / "test.db")
        todo_id = db.create_todo(content="测试待办", remind_at=datetime.now())
        assert todo_id > 0
    
    def test_get_pending_todos(self, tmp_path):
        """测试获取待处理待办"""
        db = TodoDatabase(tmp_path / "test.db")
        db.create_todo(content="待办1", remind_at=datetime.now())
        db.create_todo(content="待办2", remind_at=datetime.now())
        todos = db.get_pending_todos()
        assert len(todos) == 2
    
    def test_complete_todo(self, tmp_path):
        """测试完成待办"""
        db = TodoDatabase(tmp_path / "test.db")
        todo_id = db.create_todo(content="测试", remind_at=datetime.now())
        db.complete_todo(todo_id)
        todos = db.get_pending_todos()
        assert len(todos) == 0
    
    def test_todo_limit(self, tmp_path):
        """测试待办数量限制"""
        db = TodoDatabase(tmp_path / "test.db")
        for i in range(50):
            db.create_todo(content=f"待办{i}", remind_at=datetime.now())
        with pytest.raises(ValueError, match="TODO_LIMIT_EXCEEDED"):
            db.create_todo(content="超限", remind_at=datetime.now())
```

### 8.3 集成测试用例

```python
class TestReminderService:
    def test_reminder_triggers_on_time(self, qtbot, tmp_path):
        """测试提醒按时触发"""
        db = TodoDatabase(tmp_path / "test.db")
        service = ReminderService(db, check_interval_ms=100)
        
        # 创建一个即将触发的待办
        remind_at = datetime.now() + timedelta(seconds=1)
        db.create_todo(content="测试提醒", remind_at=remind_at)
        
        # 等待触发
        with qtbot.wait_signal(service.reminder_triggered, timeout=5000) as blocker:
            service.start()
        
        assert "测试提醒" in blocker.args[0]['content']
```

---

## 九、依赖清单

### 9.1 新增依赖

```
zhdate>=0.1.0          # 农历计算
```

### 9.2 现有依赖（复用）

```
PyQt5>=5.15            # GUI 框架
langchain>=0.3.0       # Tool 定义
langgraph>=0.2.0       # 对话流程
```

---

## 十、实现优先级

| 优先级 | 模块 | 说明 |
|--------|------|------|
| P0 | `reminder/db.py` | 数据库基础，其他模块依赖 |
| P0 | `reminder/time_parser.py` | 时间解析，Tool 和服务依赖 |
| P1 | `tools/time_tool.py` | 时间查询功能，用户可见 |
| P1 | `tools/todo_tool.py` | 待办管理功能，用户可见 |
| P2 | `reminder/service.py` | 后台提醒服务 |
| P2 | `chat_manager.py` 集成 | 连接提醒服务与 UI |
| P3 | 测试用例 | 确保质量 |
