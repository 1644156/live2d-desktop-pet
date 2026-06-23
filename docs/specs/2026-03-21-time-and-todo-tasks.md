# 时间查询与待办提醒功能 - 实现计划

## 概述

本文档基于设计文档 `2026-03-21-time-and-todo-tools-design.md`，提供详细的实现步骤和任务清单。

---

## 实现阶段

### 阶段一：基础设施（P0）

#### 任务 1.1：创建 reminder 模块目录结构

```bash
mkdir -p src/reminder
```

创建文件：
- `src/reminder/__init__.py`
- `src/reminder/db.py`
- `src/reminder/time_parser.py`
- `src/reminder/service.py`

#### 任务 1.2：实现 TodoDatabase 类 (`src/reminder/db.py`)

**功能点**：
- [ ] 初始化数据库连接
- [ ] 创建 todos 表和 todo_history 表
- [ ] 实现 `create_todo()` 方法
- [ ] 实现 `get_pending_todos()` 方法
- [ ] 实现 `get_todos_by_status()` 方法
- [ ] 实现 `update_todo()` 方法
- [ ] 实现 `complete_todo()` 方法
- [ ] 实现 `delete_todo()` 方法
- [ ] 实现 `record_trigger()` 方法
- [ ] 实现待办数量限制（最多 50 个）

**验收标准**：
- 数据库文件正确创建
- CRUD 操作正常
- 边界情况正确处理

#### 任务 1.3：实现 TimeParser 类 (`src/reminder/time_parser.py`)

**功能点**：
- [ ] 实现 `_parse_minutes_later()` - "X分钟后"
- [ ] 实现 `_parse_hours_later()` - "X小时后"
- [ ] 实现 `_parse_half_hour_later()` - "半小时后"
- [ ] 实现 `_parse_time_of_day()` - "下午X点"、"早上X点"
- [ ] 实现 `_parse_relative_day()` - "明天"、"后天"
- [ ] 实现 `_parse_repeat_interval()` - "每X分钟"
- [ ] 实现 `_parse_daily_repeat()` - "每天X点"
- [ ] 实现 `_parse_weekly_repeat()` - "每周一X点"
- [ ] 实现时间已过期检测
- [ ] 实现间隔过短检测（最小 5 分钟）

**验收标准**：
- 所有时间格式正确解析
- 边界情况正确处理

---

### 阶段二：工具实现（P1）

#### 任务 2.1：实现 get_time 工具 (`src/chat/tools/time_tool.py`)

**功能点**：
- [ ] 实现 `get_time()` Tool 函数
- [ ] 实现 `TimeService` 类
  - [ ] `get_current_time()` - 当前时间
  - [ ] `get_current_date()` - 当前日期
  - [ ] `get_lunar_info()` - 农历信息（使用 zhdate）
  - [ ] `get_weekday()` - 星期几
  - [ ] `get_festival_info()` - 节气/节日
  - [ ] `calculate_countdown()` - 倒计时计算
  - [ ] `get_days_passed()` - 今年已过天数
- [ ] 实现节日映射表
- [ ] 实现农历节日动态计算

**验收标准**：
- 所有查询类型正确返回
- 农历信息准确
- 倒计时计算正确

#### 任务 2.2：实现 manage_todo 工具 (`src/chat/tools/todo_tool.py`)

**功能点**：
- [ ] 实现 `manage_todo()` Tool 函数
- [ ] 实现 action 分发逻辑
  - [ ] `create` - 创建待办
  - [ ] `list` - 查看待办列表
  - [ ] `complete` - 完成待办
  - [ ] `delete` - 删除待办
  - [ ] `update` - 更新待办
- [ ] 集成 TimeParser 解析提醒时间
- [ ] 集成 TodoDatabase 进行数据操作
- [ ] 实现错误处理和用户友好提示

**验收标准**：
- 所有操作正确执行
- 错误提示友好

#### 任务 2.3：更新 tools/__init__.py

**功能点**：
- [ ] 导出 `get_time` 工具
- [ ] 导出 `manage_todo` 工具

---

### 阶段三：后台服务（P2）

#### 任务 3.1：实现 ReminderService 类 (`src/reminder/service.py`)

**功能点**：
- [ ] 继承 QObject，定义 `reminder_triggered` 信号
- [ ] 实现定时扫描机制（使用 QTimer）
- [ ] 实现 `should_trigger()` 触发条件判断
- [ ] 实现 `_check_and_trigger()` 扫描逻辑
- [ ] 实现重复提醒的下次触发计算
- [ ] 实现 `start()` 和 `stop()` 方法
- [ ] 实现异常处理，确保服务不中断

**验收标准**：
- 提醒按时触发
- 重复提醒正确计算下次时间
- 服务稳定运行

#### 任务 3.2：集成到 ChatManager (`src/app/chat_manager.py`)

**功能点**：
- [ ] 初始化 TodoDatabase 实例
- [ ] 初始化 ReminderService 实例
- [ ] 连接 `reminder_triggered` 信号
- [ ] 实现 `_on_reminder_triggered()` 回调
  - [ ] 显示气泡消息
  - [ ] TTS 语音播报（如果开启）
- [ ] 在 `stop()` 方法中停止提醒服务

**验收标准**：
- 提醒触发时正确显示气泡
- TTS 正常播报

#### 任务 3.3：更新 ChatGraph (`src/chat/graph.py`)

**功能点**：
- [ ] 将 `get_time` 添加到工具列表
- [ ] 将 `manage_todo` 添加到工具列表
- [ ] 更新系统提示词，说明新工具能力

---

### 阶段四：依赖与配置（P2）

#### 任务 4.1：更新 requirements.txt

**新增依赖**：
```
zhdate>=0.1.0
```

#### 任务 4.2：更新配置文件（可选）

在 `config/llm_config.yaml` 中添加提醒相关配置：
```yaml
reminder:
  check_interval_ms: 60000    # 扫描间隔
  max_todos: 50               # 最大待办数
  min_interval_minutes: 5     # 最小重复间隔
```

---

### 阶段五：测试（P3）

#### 任务 5.1：TimeParser 单元测试

**测试用例**：
- [ ] `test_parse_minutes_later`
- [ ] `test_parse_hours_later`
- [ ] `test_parse_time_of_day`
- [ ] `test_parse_relative_day`
- [ ] `test_parse_repeat_interval`
- [ ] `test_time_passed_error`
- [ ] `test_interval_too_short_error`

#### 任务 5.2：TodoDatabase 单元测试

**测试用例**：
- [ ] `test_create_todo`
- [ ] `test_get_pending_todos`
- [ ] `test_complete_todo`
- [ ] `test_delete_todo`
- [ ] `test_todo_limit`

#### 任务 5.3：get_time 工具测试

**测试用例**：
- [ ] `test_get_current_time`
- [ ] `test_get_lunar_info`
- [ ] `test_countdown`

#### 任务 5.4：manage_todo 工具测试

**测试用例**：
- [ ] `test_create_one_time_todo`
- [ ] `test_create_repeat_todo`
- [ ] `test_list_todos`
- [ ] `test_complete_todo`

#### 任务 5.5：ReminderService 集成测试

**测试用例**：
- [ ] `test_reminder_triggers_on_time`
- [ ] `test_repeat_reminder`

---

## 文件清单

### 新增文件

| 文件路径 | 说明 |
|---------|------|
| `src/reminder/__init__.py` | 模块初始化 |
| `src/reminder/db.py` | 待办数据库操作 |
| `src/reminder/time_parser.py` | 时间解析器 |
| `src/reminder/service.py` | 后台提醒服务 |
| `src/chat/tools/time_tool.py` | 时间查询工具 |
| `src/chat/tools/todo_tool.py` | 待办管理工具 |

### 修改文件

| 文件路径 | 修改内容 |
|---------|---------|
| `src/chat/tools/__init__.py` | 导出新工具 |
| `src/chat/graph.py` | 注册新工具 |
| `src/app/chat_manager.py` | 集成提醒服务 |
| `requirements.txt` | 添加 zhdate 依赖 |

---

## 实现顺序

```
┌─────────────────────────────────────────────────────────────┐
│  阶段一：基础设施 (P0)                                       │
│  ├── 1.1 创建目录结构                                        │
│  ├── 1.2 实现 TodoDatabase                                   │
│  └── 1.3 实现 TimeParser                                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  阶段二：工具实现 (P1)                                       │
│  ├── 2.1 实现 get_time 工具                                  │
│  ├── 2.2 实现 manage_todo 工具                               │
│  └── 2.3 更新 __init__.py                                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  阶段三：后台服务 (P2)                                       │
│  ├── 3.1 实现 ReminderService                                │
│  ├── 3.2 集成到 ChatManager                                  │
│  └── 3.3 更新 ChatGraph                                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  阶段四：依赖与配置 (P2)                                     │
│  ├── 4.1 更新 requirements.txt                               │
│  └── 4.2 更新配置文件（可选）                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  阶段五：测试 (P3)                                           │
│  ├── 5.1 TimeParser 测试                                     │
│  ├── 5.2 TodoDatabase 测试                                   │
│  ├── 5.3 get_time 测试                                       │
│  ├── 5.4 manage_todo 测试                                    │
│  └── 5.5 ReminderService 测试                                │
└─────────────────────────────────────────────────────────────┘
```

---

## 预计工作量

| 阶段 | 任务数 | 预计时间 |
|------|--------|---------|
| 阶段一 | 3 | 基础模块 |
| 阶段二 | 3 | 工具实现 |
| 阶段三 | 3 | 服务集成 |
| 阶段四 | 2 | 配置更新 |
| 阶段五 | 5 | 测试验证 |

---

## 验收标准

### 功能验收

- [ ] 用户可以通过自然语言查询时间/日期/农历/倒计时
- [ ] 用户可以通过自然语言创建一次性提醒
- [ ] 用户可以通过自然语言创建重复提醒
- [ ] 提醒按时触发，显示气泡消息
- [ ] TTS 开启时，提醒语音播报
- [ ] 用户可以查看/完成/删除待办

### 质量验收

- [ ] 无明显 bug
- [ ] 错误提示友好
- [ ] 代码符合项目规范
- [ ] 核心功能有测试覆盖
