@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo   Live2D Desktop Pet 打包脚本
echo ========================================
echo.

REM 检查 Python 环境
python --version >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 Python，请先安装 Python 3.10+
    pause
    exit /b 1
)

REM 检查 PyInstaller
pip show pyinstaller >nul 2>&1
if errorlevel 1 (
    echo [信息] 正在安装 PyInstaller...
    pip install pyinstaller
)

echo [步骤 1/5] 清理旧的打包文件...
if exist "dist\Live2DDesktopPet" rmdir /s /q "dist\Live2DDesktopPet"
if exist "build" rmdir /s /q "build"

echo [步骤 2/5] 检查依赖...
pip install -r requirements.txt

echo [步骤 3/5] 开始打包...
echo 这可能需要几分钟时间，请耐心等待...
pyinstaller live2d_pet.spec --clean

if errorlevel 1 (
    echo [错误] 打包失败！
    pause
    exit /b 1
)

echo [步骤 4/5] 复制额外文件...

REM 复制音频文件
if exist "音色.wav" copy "音色.wav" "dist\Live2DDesktopPet\"
if exist "日语.wav" copy "日语.wav" "dist\Live2DDesktopPet\"

REM 创建数据目录
if not exist "dist\Live2DDesktopPet\data" mkdir "dist\Live2DDesktopPet\data"

REM 创建模型缓存目录
if not exist "dist\Live2DDesktopPet\models" mkdir "dist\Live2DDesktopPet\models"

REM 创建用户配置模板
if not exist "dist\Live2DDesktopPet\config" mkdir "dist\Live2DDesktopPet\config"

echo [步骤 5/5] 创建配置模板...
(
echo # 大模型配置文件
echo # 请在首次运行前填写您的 API 配置
echo.
echo # 通义千问 ^(推荐^)
echo api_key: "your-api-key-here"
echo base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1"
echo model_name: "qwen-plus"
echo.
echo # 通用参数
echo temperature: 0.85
echo.
echo # 向量嵌入模型配置
echo embedding:
echo   enabled: true
echo   model: "Qwen/Qwen3-Embedding-0.6B"
echo.
echo # 语音合成配置
echo tts:
echo   enabled: false
echo   speech_mode: "zh"
echo   voice_file: "音色.wav"
echo   voice_file_ja: "日语.wav"
echo   preferred_name: "live2d_pet"
echo.
echo reminder:
echo   check_interval_ms: 10000
echo   max_todos: 50
echo   min_interval_minutes: 5
) > "dist\Live2DDesktopPet\config\llm_config.yaml.template"

echo.
echo ========================================
echo   打包完成！
echo ========================================
echo.
echo 输出目录: dist\Live2DDesktopPet
echo.
echo 后续步骤:
echo   1. 编辑 config\llm_config.yaml.template 填入 API Key
echo   2. 将模板文件重命名为 llm_config.yaml
echo   3. 首次运行时嵌入模型会自动下载（约 600MB）
echo   4. 可以将整个 dist\Live2DDesktopPet 目录打包分发
echo.
pause
