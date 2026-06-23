"""
PyInstaller 运行时钩子

此脚本在打包后的应用程序启动时运行，用于：
1. 设置正确的工作目录
2. 处理资源路径
3. 初始化运行时环境
"""

import os
import sys


def get_base_dir():
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def setup_environment():
    base_dir = get_base_dir()
    
    os.chdir(base_dir)
    
    if base_dir not in sys.path:
        sys.path.insert(0, base_dir)
    
    src_dir = os.path.join(base_dir, 'src')
    if src_dir not in sys.path:
        sys.path.insert(0, src_dir)
    
    os.environ['LIVE2D_BASE_DIR'] = base_dir
    
    config_dir = os.path.join(base_dir, 'config')
    if not os.path.exists(config_dir):
        os.makedirs(config_dir, exist_ok=True)
        
        default_llm_config = """# 大模型配置文件
# 请填写您的 API 配置

# 通义千问 (示例)
api_key: "your-api-key-here"
base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1"
model_name: "qwen-plus"

# 通用参数
temperature: 0.85

# 向量嵌入模型配置
embedding:
  enabled: true
  model: "BAAI/bge-base-zh-v1.5"

# 语音合成配置
tts:
  enabled: false
  speech_mode: "zh"
  voice_file: "音色.wav"
  voice_file_ja: "日语.wav"
  preferred_name: "live2d_pet"

reminder:
  check_interval_ms: 10000
  max_todos: 50
  min_interval_minutes: 5
"""
        config_file = os.path.join(config_dir, 'llm_config.yaml')
        if not os.path.exists(config_file):
            with open(config_file, 'w', encoding='utf-8') as f:
                f.write(default_llm_config)
            print(f"[Runtime] 已创建默认配置文件: {config_file}")
            print("[Runtime] 请编辑配置文件填入您的 API Key")
        
        default_model_config = """model:
  default_path: public/models/Mao/Mao.model3.json
"""
        model_config_file = os.path.join(config_dir, 'model_config.yaml')
        if not os.path.exists(model_config_file):
            with open(model_config_file, 'w', encoding='utf-8') as f:
                f.write(default_model_config)
    
    data_dir = os.path.join(base_dir, 'data')
    if not os.path.exists(data_dir):
        os.makedirs(data_dir, exist_ok=True)
    
    models_dir = os.path.join(base_dir, 'models')
    if not os.path.exists(models_dir):
        os.makedirs(models_dir, exist_ok=True)


setup_environment()

print(f"[Runtime] 工作目录: {os.getcwd()}")
print(f"[Runtime] 基础目录: {get_base_dir()}")
