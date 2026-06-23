# Live2D Desktop Pet Build Script (PowerShell)
# Usage: .\build.ps1

param(
    [switch]$Clean = $false,
    [switch]$IncludeModel = $false,
    [string]$PythonPath = ""
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Live2D Desktop Pet Build Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Set Python path
if ($PythonPath) {
    $env:Path = "$PythonPath;$env:Path"
}

# Check Python
try {
    $pythonVersion = python --version 2>&1
    Write-Host "[Info] Python version: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "[Error] Python not found, please install Python 3.10+" -ForegroundColor Red
    exit 1
}

# Check PyInstaller
$pyinstallerInstalled = python -m pip show pyinstaller 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[Info] Installing PyInstaller..." -ForegroundColor Yellow
    python -m pip install --user pyinstaller
}

# Clean old files
if ($Clean) {
    Write-Host "[Step 1/6] Cleaning old build files..." -ForegroundColor Yellow
    if (Test-Path "dist\Live2DDesktopPet") {
        Remove-Item -Recurse -Force "dist\Live2DDesktopPet"
    }
    if (Test-Path "build") {
        Remove-Item -Recurse -Force "build"
    }
} else {
    Write-Host "[Step 1/6] Skip cleaning (use -Clean to clean)" -ForegroundColor Gray
}

# Install dependencies
Write-Host "[Step 2/6] Checking dependencies..." -ForegroundColor Yellow
python -m pip install --user -r requirements.txt 2>$null

# Build
Write-Host "[Step 3/6] Building..." -ForegroundColor Yellow
Write-Host "This may take a few minutes, please wait..." -ForegroundColor Gray

$pyinstallerArgs = @("live2d_pet.spec", "--clean")
if ($Clean) {
    $pyinstallerArgs += "--noconfirm"
}

& python -m PyInstaller $pyinstallerArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "[Error] Build failed!" -ForegroundColor Red
    exit 1
}

# Copy extra files
Write-Host "[Step 4/6] Copying extra files..." -ForegroundColor Yellow

$distPath = "dist\Live2DDesktopPet"

# Audio files
if (Test-Path "音色.wav") {
    Copy-Item "音色.wav" $distPath -Force
}
if (Test-Path "日语.wav") {
    Copy-Item "日语.wav" $distPath -Force
}

# Create directories
New-Item -ItemType Directory -Force -Path "$distPath\data" | Out-Null
New-Item -ItemType Directory -Force -Path "$distPath\models" | Out-Null
New-Item -ItemType Directory -Force -Path "$distPath\config" | Out-Null

# Optional: Copy embedding model
if ($IncludeModel) {
    Write-Host "[Step 5/6] Copying embedding model (this may take a while)..." -ForegroundColor Yellow
    $modelSrc = "src\app\models\Qwen"
    $modelDst = "$distPath\models\Qwen"
    if (Test-Path $modelSrc) {
        Copy-Item -Recurse -Force $modelSrc $modelDst
        Write-Host "[Info] Embedding model copied" -ForegroundColor Green
    }
} else {
    Write-Host "[Step 5/6] Skip embedding model (use -IncludeModel to include)" -ForegroundColor Gray
    Write-Host "[Info] Embedding model will be downloaded on first run (~600MB)" -ForegroundColor Gray
}

# Create config template
Write-Host "[Step 6/6] Creating config template..." -ForegroundColor Yellow

$configTemplate = @"
# LLM Configuration File
# Please fill in your API configuration before first run

# Qwen (Recommended)
api_key: "your-api-key-here"
base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1"
model_name: "qwen-plus"

# General parameters
temperature: 0.85

# Embedding model configuration
embedding:
  enabled: true
  model: "Qwen/Qwen3-Embedding-0.6B"

# TTS configuration
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
"@

$configTemplate | Out-File -FilePath "$distPath\config\llm_config.yaml.template" -Encoding UTF8

# Create README
$readmeContent = @"
# Live2D Desktop Pet - User Guide

## First Run Setup

### 1. Configure API Key
1. Go to the 'config' folder
2. Rename 'llm_config.yaml.template' to 'llm_config.yaml'
3. Edit the file and replace 'your-api-key-here' with your actual API Key

### 2. Embedding Model
On first run, the program will automatically download the embedding model (~600MB) from ModelScope.
If your network is slow, you can:
- Manually download Qwen3-Embedding-0.6B from ModelScope
- Place it in the 'models' folder

### 3. Run the Program
Double-click 'Live2DDesktopPet.exe' to start

## Features
- Right-click on model: Open menu
- Left-click drag: Move window
- System tray icon: Quick settings

## Supported LLM Services
- Qwen (Recommended)
- DeepSeek
- OpenAI
- Other OpenAI API compatible services
"@

$readmeContent | Out-File -FilePath "$distPath\README.txt" -Encoding UTF8

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Output directory: $distPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Edit config\llm_config.yaml.template and add your API Key"
Write-Host "  2. Rename the template file to llm_config.yaml"
Write-Host "  3. Embedding model will be downloaded on first run (~600MB)"
Write-Host "  4. You can package the entire dist\Live2DDesktopPet folder for distribution"
Write-Host ""

# Calculate build size
$size = (Get-ChildItem -Recurse $distPath | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "Build size: $([math]::Round($size, 2)) MB" -ForegroundColor Cyan
