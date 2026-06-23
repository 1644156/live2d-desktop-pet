# Live2D 桌宠设计文档

## 概述

基于现有的 Live2D Web 实现，使用 PyQt5 + QWebEngineView 构建桌面宠物应用。

## 需求

- 窗口模式：透明悬浮窗 / 有边框窗口，支持切换
- 交互方式：鼠标跟随 + 点击触发 + 右键菜单
- 自动行为：仅待机动作

## 技术方案

PyQt5 + QWebEngineView 内嵌浏览器渲染 Live2D，复用现有 JS 代码。

## 架构

```
┌─────────────────────────────────────┐
│           PyQt5 主窗口               │
│  ┌───────────────────────────────┐  │
│  │     QWebEngineView            │  │
│  │  ┌─────────────────────────┐  │  │
│  │  │   Live2D (JS/Canvas)    │  │  │
│  │  │   - pixi.js 渲染        │  │  │
│  │  │   - 模型加载/交互       │  │  │
│  │  └─────────────────────────┘  │  │
│  └───────────────────────────────┘  │
│                                     │
│  右键菜单 / 系统托盘 / 模式切换      │
└─────────────────────────────────────┘
```

## 模块设计

### main.py - 程序入口
- 初始化 QApplication
- 创建主窗口
- 启动事件循环

### window.py - 主窗口
- 窗口属性设置（无边框、置顶、透明）
- QWebEngineView 加载 HTML
- 模式切换（透明/边框）
- 右键菜单
- 鼠标事件处理（拖拽、点击传递）

### web_bridge.py - Python-JS 通信
- QWebChannel 桥接
- 暴露 Python 接口给 JS 调用
- 调用 JS 接口控制模型

### tray.py - 系统托盘
- 托盘图标
- 托盘菜单（显示/隐藏、模式切换、退出）

## 文件结构

```
live2d/
├── public/
│   ├── models/Mao/     # 模型资源
│   ├── index.html      # 原Web页面
│   └── desktop.html    # 桌宠专用页面
├── src/
│   ├── utils/          # JS库
│   └── app/
│       ├── main.py     # 入口
│       ├── window.py   # 主窗口
│       ├── web_bridge.py
│       └── tray.py
└── requirements.txt
```

## 功能实现

### 透明窗口
- 设置 `Qt.FramelessWindowHint`
- 设置 `Qt.WindowTransparentForInput` (可选穿透)
- 设置 `WA_TranslucentBackground`

### 鼠标跟随
- JS 端监听 mousemove 事件
- 通过 bridge 传递坐标给 JS
- JS 调用 `model.focus(x, y)`

### 右键菜单
- 重写 `contextMenuEvent`
- 菜单项：表情列表、动作列表、模式切换、退出

### 系统托盘
- QSystemTrayIcon
- 最小化时隐藏到托盘
- 托盘菜单控制

## 依赖

```
PyQt5>=5.15
PyQtWebEngine>=5.15
```

## 实现步骤

1. 创建桌面专用 HTML 页面（简化版）
2. 实现主窗口框架
3. 实现 Python-JS 通信桥
4. 实现右键菜单
5. 实现系统托盘
6. 实现模式切换
