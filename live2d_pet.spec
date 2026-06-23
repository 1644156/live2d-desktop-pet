# -*- mode: python ; coding: utf-8 -*-
"""
Live2D Desktop Pet PyInstaller 打包配置

使用方法:
    pyinstaller live2d_pet.spec

注意:
    1. 首次打包前请确保已安装所有依赖
    2. 嵌入模型默认不打包（体积过大），用户首次运行时会自动下载
    3. API Key 需要在运行时配置
"""

import os
import sys
from PyInstaller.utils.hooks import collect_data_files, collect_submodules

block_cipher = None

PROJECT_ROOT = os.path.dirname(os.path.abspath(SPEC))

def get_relative_path(path):
    return os.path.join(PROJECT_ROOT, path)

datas = []

datas += [
    (get_relative_path('public/models'), 'public/models'),
    (get_relative_path('public/*.html'), 'public'),
    (get_relative_path('public/*.js'), 'public'),
    (get_relative_path('config'), 'config'),
    (get_relative_path('src/utils'), 'src/utils'),
]

datas += collect_data_files('PyQt5')
datas += collect_data_files('PyQtWebEngine')

hiddenimports = [
    'PyQt5',
    'PyQt5.QtCore',
    'PyQt5.QtGui',
    'PyQt5.QtWidgets',
    'PyQt5.QtWebEngineWidgets',
    'PyQt5.QtWebEngineCore',
    'PyQt5.QtWebChannel',
    'PyQt5.sip',
    
    'langchain',
    'langchain_openai',
    'langgraph',
    'langgraph.graph',
    'langgraph.graph.message',
    'langgraph.checkpoint.memory',
    
    'yaml',
    'requests',
    'requests_cache',
    'retry_requests',
    'openmeteo_requests',
    
    'chromadb',
    'chromadb.config',
    'chromadb.api',
    'chromadb.db',
    
    'fastembed',
    'onnxruntime',
    
    'zhdate',
    
    'sqlite3',
    'sqlite3.dbapi2',
    
    'app',
    'app.main',
    'app.window',
    'app.bubble_window',
    'app.input_window',
    'app.history_window',
    'app.todo_window',
    'app.tray',
    'app.web_bridge',
    'app.chat_manager',
    'app.idle_manager',
    'app.model3_assets',
    
    'chat',
    'chat.graph',
    'chat.llm_provider',
    'chat.persona',
    'chat.emotions',
    'chat.emotion_store',
    'chat.conversation_store',
    'chat.memory_store',
    'chat.memory_extractor',
    'chat.context_compressor',
    
    'chat.tools',
    'chat.tools.time_tool',
    'chat.tools.todo_tool',
    'chat.tools.weather',
    
    'reminder',
    'reminder.db',
    'reminder.service',
    'reminder.time_parser',
    
    'tts',
    'tts.tts_service',
    'tts.audio_player',
]

hiddenimports += collect_submodules('langchain')
hiddenimports += collect_submodules('langchain_openai')
hiddenimports += collect_submodules('langgraph')
hiddenimports += collect_submodules('chromadb')
hiddenimports += collect_submodules('fastembed')
hiddenimports += collect_submodules('onnxruntime')

a = Analysis(
    [get_relative_path('src/app/main.py')],
    pathex=[PROJECT_ROOT],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[get_relative_path('build_hooks/runtime_hook.py')],
    excludes=[
        'tkinter',
        'matplotlib',
        'PIL',
        'scipy',
        'numpy.f2py',
        'IPython',
        'jupyter',
        'notebook',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='Live2DDesktopPet',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=get_relative_path('public/models/Mao/Mao.model3.json').replace('Mao.model3.json', 'icon.ico') if os.path.exists(get_relative_path('public/models/Mao/icon.ico')) else None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='Live2DDesktopPet',
)
