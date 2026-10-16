@echo off
REM ============================================================================
REM create_project.bat —— 一键创建 Vivado 工程（Windows 用）
REM ----------------------------------------------------------------------------
REM 用法：双击本文件即可（或在 cmd 中执行 scripts\create_project.bat）
REM
REM 作用：生成 cpu_single\cpu_single.xpr，之后用 Vivado GUI 打开它即可
REM       跑仿真、看波形、综合实现。
REM
REM 【为什么需要这个脚本】
REM   .xpr 工程文件不能进 git（Vivado 版本单向升级 + 绝对路径 + 跨 OS 分隔符），
REM   所以约定：仓库只存源文件，工程各人用本脚本自动生成一次。
REM   详见 design/BUILD.md
REM
REM 前置：Vivado 已安装且 vivado.bat 在 PATH 中。
REM ============================================================================
setlocal

set SCRIPT_DIR=%~dp0
set ROOT=%SCRIPT_DIR%..
set VIVADO=vivado

where %VIVADO% >nul 2>nul
if errorlevel 1 (
    echo ERROR: 找不到 vivado，请把 Vivado 的 bin 目录加入 PATH
    echo        或编辑本脚本，把 VIVADO 设为完整路径，例如：
    echo        set VIVADO=C:\Xilinx\Vivado\2019.1\bin\vivado.bat
    pause
    exit /b 1
)

REM 日志目录必须先建好，否则 -log 会因目录不存在而失败
if not exist "%ROOT%\out" mkdir "%ROOT%\out"

echo ===== 创建 Vivado 工程 =====
"%VIVADO%" -mode batch -source "%SCRIPT_DIR%create_project.tcl" -log "%ROOT%\out\vivado_create.log" -journal "%ROOT%\out\vivado_create.jou"

if errorlevel 1 (
    echo.
    echo 创建失败，请看 out\vivado_create.log
    pause
    exit /b 1
)

echo.
echo ===== 完成 =====
echo   工程文件：cpu_single\cpu_single.xpr
echo   下一步：用 Vivado GUI 打开它
echo     - 看波形：Flow Navigator -^> Simulation -^> Run Behavioral Simulation
echo     - 综合实现：Flow Navigator -^> Synthesis / Implementation
pause
