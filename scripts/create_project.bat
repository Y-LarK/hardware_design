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
REM 前置：Vivado 已安装。脚本自动定位 vivado.bat，优先级：
REM       VIVADO_BAT 环境变量 > PATH > 常见安装位置（详见下方定位段注释）。
REM ============================================================================
setlocal

set SCRIPT_DIR=%~dp0
set ROOT=%SCRIPT_DIR%..

REM ---- 定位 Vivado ----
REM 【为什么不能只写 where vivado 再调 "%VIVADO%"】
REM   1) where 只把 PATH 条目当「目录」来查找。若 PATH 里加的是 vivado.bat
REM      文件本身而不是它的 bin 目录，where 找不到（PowerShell 的
REM      Get-Command 反而能找到，容易误判成环境没问题）。
REM   2) vivado.bat 内部靠 %~dp0 定位自己的 setupEnv.bat；用「带引号的裸名」
REM      调用（"%VIVADO%" 且 VIVADO=vivado）会让子脚本的 %~dp0 退化成当前
REM      工作目录，vivado.bat 于是去找 <当前目录>\setupEnv.bat 而启动失败。
REM   所以这里统一解析成「完整路径」，调用时用引号包住完整路径（含空格也安全）。
REM   注：多个版本目录时取第一个（字母序），如需指定请用 VIVADO_BAT（值不要加引号）。
REM
REM 【为什么调用要加 call】
REM   .bat 里不带 call 直接调用另一个 .bat，控制权**不会返回**：子脚本里的
REM   exit /b 会终止整条调用链，本脚本后面的 if errorlevel 判断和 pause 全被跳过。
REM   vivado.bat 末尾正是 exit /b %errorlevel%（第 50 行），所以不加 call 的现象是：
REM   Vivado 正常跑完 -> 窗口瞬间消失 -> 看不到"完成"和错误提示。
REM   加 call 后控制权返回，报错时也能停在 pause 上。
set VIVADO=
if defined VIVADO_BAT if exist "%VIVADO_BAT%" set "VIVADO=%VIVADO_BAT%"

if not defined VIVADO (
    for %%N in (vivado.bat vivado) do (
        if not defined VIVADO (
            for /f "delims=" %%P in ('where %%N 2^>nul') do (
                if not defined VIVADO set "VIVADO=%%P"
            )
        )
    )
)

if not defined VIVADO (
    for %%R in (
        "C:\Xilinx\Vivado" "D:\Xilinx\Vivado" "C:\Program Files\Xilinx\Vivado"
        "D:\Software\vivado\Vivado"
    ) do (
        if not defined VIVADO (
            for /d %%V in ("%%~R\*") do (
                if not defined VIVADO if exist "%%~V\bin\vivado.bat" set "VIVADO=%%~V\bin\vivado.bat"
            )
        )
    )
)

if not defined VIVADO (
    echo ERROR: 找不到 vivado.bat，请任选一种方式解决：
    echo   1. 把 Vivado 的 bin 目录加入 PATH（是目录，不是 vivado.bat 文件本身）
    echo   2. 设环境变量：set VIVADO_BAT=D:\Software\vivado\Vivado\2019.1\bin\vivado.bat
    echo   3. 编辑本脚本，在定位段把 VIVADO 直接写成完整路径
    pause
    exit /b 1
)
echo 使用 Vivado: %VIVADO%

REM 日志目录必须先建好，否则 -log 会因目录不存在而失败
if not exist "%ROOT%\out" mkdir "%ROOT%\out"

echo ===== 创建 Vivado 工程 =====
call "%VIVADO%" -mode batch -source "%SCRIPT_DIR%create_project.tcl" -log "%ROOT%\out\vivado_create.log" -journal "%ROOT%\out\vivado_create.jou"

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
