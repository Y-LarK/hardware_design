@echo off
REM ============================================================================
REM build.bat —— 一键构建（综合 -> 实现 -> 比特流），Windows 用
REM ----------------------------------------------------------------------------
REM 用法（在资源管理器里双击本文件，或在 cmd 中执行）：
REM   scripts\build.bat            构建
REM   scripts\build.bat program    构建并烧录到开发板
REM
REM 前置：Vivado 已安装，且 vivado.bat 在 PATH 中。
REM       若没在 PATH，把下面 VIVADO 改成实际路径，例如：
REM       set VIVADO=C:\Xilinx\Vivado\2019.1\bin\vivado.bat
REM ============================================================================
setlocal

set SCRIPT_DIR=%~dp0
set ROOT=%SCRIPT_DIR%..
set VIVADO=vivado

where %VIVADO% >nul 2>nul
if errorlevel 1 (
    echo ERROR: 找不到 vivado，请把 Vivado 的 bin 目录加入 PATH
    echo        或编辑本脚本，把 VIVADO 设为完整路径
    pause
    exit /b 1
)

REM 日志目录必须先建好，否则 -log 会因目录不存在而失败
if not exist "%ROOT%\out" mkdir "%ROOT%\out"

echo ===== 构建单周期 CPU =====
"%VIVADO%" -mode batch -source "%SCRIPT_DIR%build.tcl" -log "%ROOT%\out\vivado_build.log" -journal "%ROOT%\out\vivado_build.jou"
if errorlevel 1 (
    echo.
    echo 构建失败，请看 out\vivado_build.log
    pause
    exit /b 1
)

if /i "%1"=="program" (
    echo.
    echo ===== 烧录到开发板 =====
    "%VIVADO%" -mode batch -source "%SCRIPT_DIR%program.tcl" -log "%ROOT%\out\vivado_program.log" -journal "%ROOT%\out\vivado_program.jou"
    if errorlevel 1 (
        echo.
        echo 烧录失败，请看 out\vivado_program.log
        pause
        exit /b 1
    )
)

echo.
echo ===== 完成 =====
echo   比特流：out\cpu_board.bit
pause
