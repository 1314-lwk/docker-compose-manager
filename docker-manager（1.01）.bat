@echo off
:: ============================================
::  Docker Compose 项目管理面板  v1.0（整合版）
::  作者：LWK-1314
::  更新日期：2026-08-27
:: ============================================
::  功能说明：
::    自动搜索指定路径下的 docker-compose.yml 或 docker-compose.yaml 文件，
::    以交互式菜单列出所有项目，支持启动（后台）、停止、查看状态和实时日志。
::    首次运行会引导选择搜索根目录（支持盘符或任意文件夹），
::    配置自动保存到同目录下的 config.ini，下次启动直接复用。
::
::  使用前提：
::    1. 必须以管理员身份运行（右键 -> 以管理员身份运行），否则脚本会提示退出。
::    2. 系统已安装 Docker Desktop 并添加到 PATH 环境变量。
::
::  注意事项（避免“踩坑”）：
::    1. 项目文件夹名称请不要包含感叹号 "!"。
::       （这是 Windows 批处理的历史遗留问题，带感叹号的路径会导致变量解析异常。）
::    2. 主菜单输入编号时，直接输入数字（如 1），不要加前导零（如 01）。
::    3. 搜索路径支持根目录（如 D:\），脚本会自动递归查找所有子目录，
::       扫描速度取决于硬盘性能，通常几秒内完成，请耐心等待。
::    4. 如果未找到任何项目，可按 R 键重新选择路径。
::    5. 如需重置搜索路径，可在主菜单按 R，或手动删除 config.ini 文件。
::
::  常见问题：
::    - 启动时提示“Docker 未运行”？脚本会自动尝试打开 Docker Desktop，
::      如果等待超时，请手动启动 Docker 后再试。
::    - 路径无效或项目目录已被删除？脚本会检测并返回菜单，不会误操作。
:: ============================================

setlocal enabledelayedexpansion

:: ============================================
:: 强制跳转到主逻辑，绕过可能被误解析的子程序区
:: ============================================
goto :main

:: ============================================
:: 子程序：检测并启动 Docker（通用版）
:: ============================================
:check_docker
docker info >nul 2>&1
if errorlevel 1 (
    echo Docker 未运行，正在尝试自动启动...
    set "started=0"

    :: 1. 直接用当前用户的安装路径（最常见，硬编码但用变量）
    if exist "%USERPROFILE%\AppData\Local\Programs\DockerDesktop\Docker Desktop.exe" (
        start "" "%USERPROFILE%\AppData\Local\Programs\DockerDesktop\Docker Desktop.exe"
        set "started=1"
    )

    :: 2. 如果上面的路径不存在，尝试从 docker.exe 位置推导
    if !started!==0 (
        for /f "delims=" %%i in ('where docker 2^>nul') do (
            set "docker_exe=%%i"
            set "docker_dir=%%~dpi"
            :: 去掉末尾的 resources\bin\
            set "docker_dir=!docker_dir:resources\bin\=!"
            if exist "!docker_dir!\Docker Desktop.exe" (
                start "" "!docker_dir!\Docker Desktop.exe"
                set "started=1"
            )
        )
    )

    :: 3. 尝试系统安装路径
    if !started!==0 if exist "C:\Program Files\Docker\Docker\Docker Desktop.exe" (
        start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        set "started=1"
    )

    :: 4. 尝试注册表名称（作为最后手段）
    if !started!==0 (
        start "" "Docker Desktop" 2>nul && set "started=1"
    )
    if !started!==0 (
        start "" "Docker" 2>nul && set "started=1"
    )

    if !started!==0 (
        echo 自动启动失败，请手动启动 Docker Desktop
        exit /b 1
    )

    :: 等待 Docker 就绪
    set /a wait=0
    :loop
    set /a wait+=1
    if !wait! geq 30 (
        echo 等待超时，请手动启动 Docker
        exit /b 1
    )
    docker info >nul 2>&1
    if errorlevel 1 (
        timeout /t 2 >nul
        goto loop
    )
    echo Docker 已就绪
) else (
    echo Docker 已运行
)
exit /b 0

:: ============================================
:: 主逻辑入口
:: ============================================
:main

:: 管理员权限检测
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 需要管理员权限！请右键点击此脚本，选择“以管理员身份运行”。 > con
    echo 按任意键退出... > con
    pause >nul
    exit /b
)

:: 启动提示
cls
echo ============================================
echo   Docker Compose 项目管理面板  v1.0
echo ============================================
echo   使用前请留意：
echo   1. 项目文件夹名请勿包含感叹号 "！"
echo      （否则脚本会因批处理特性解析异常）
echo   2. 主菜单输入编号时，直接输入数字（如 1）
echo      不要加前导零（如 01）
echo   3. 搜索路径支持盘符根目录（如 D:\）
echo      自动递归扫描，速度取决于硬盘性能
echo ============================================
echo.
echo 按任意键继续，或等待 5 秒自动继续...
timeout /t 5 >nul

:: 配置文件处理
set "CFG=%~dp0config.ini"
set "ROOT="

if exist "%CFG%" (
    for /f "tokens=2 delims==" %%a in ('findstr "ROOT" "%CFG%"') do set "ROOT=%%a"
)

:select_path
if defined ROOT (
    cls
    echo ========================================
    echo       当前搜索路径：%ROOT%
    echo ========================================
    echo 1. 使用当前路径
    echo 2. 重新选择路径
    echo.
    set /p "choice_path=请选择（1 或 2）: "
    if "!choice_path!"=="1" goto :path_selected
    if "!choice_path!"=="2" set "ROOT=" & goto :show_drives
    echo 无效选择
    pause
    goto select_path
)

:show_drives
cls
echo ========================================
echo        请选择项目所在盘符
echo ========================================
echo.

set "drive_count=0"
for %%d in (A C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%d:\" (
        set /a drive_count+=1
        set "drive_!drive_count!=%%d"
        echo !drive_count!. %%d 盘
    )
)

if %drive_count% equ 0 (
    echo 未检测到任何可用盘符，请手动输入路径
    set /p "ROOT=请输入完整路径（例如 D:\Projects\）: "
    goto :save_config
)

echo.
echo 0. 手动输入路径
echo.
set /p "drive_choice=请输入盘符编号（0-9）: "

if "%drive_choice%"=="0" (
    set /p "ROOT=请输入完整路径（例如 D:\Projects\）: "
    goto :save_config
)

set "selected_drive=!drive_%drive_choice%!"
if not defined selected_drive (
    echo 无效编号，请重新选择
    pause
    goto show_drives
)

set "ROOT=%selected_drive%:\"

:save_config
if not "!ROOT:~-1!"=="\" set "ROOT=!ROOT!\"

> "%CFG%" echo ROOT=!ROOT!
echo 配置已保存到 config.ini
echo 当前搜索路径：!ROOT!
echo.
pause

:path_selected
set "IGNORE_LIST=tidb weaviate postgres redis"

:menu
cls
echo ========================================
echo        Docker Compose 项目管理面板
echo ========================================
echo 搜索目录：%ROOT%
echo 正在扫描项目...
echo.

set count=0

for /f "delims=" %%i in ('dir /s /b "%ROOT%docker-compose.y*" 2^>nul ^| findstr /v /i "%IGNORE_LIST%"') do (
    set "full_path=%%~dpi"
    set "full_path=!full_path:~0,-1!"
    set /a count+=1
    set "proj_path_!count!=!full_path!"
    for %%a in ("!full_path!") do set "proj_name_!count!=%%~nxa"
)

if %count% equ 0 (
    echo 在 %ROOT% 下未找到任何 docker-compose 文件
    echo.
    echo 按 R 键重新选择路径，按其他键返回主菜单
    set /p "retry=请选择: "
    if /i "!retry!"=="R" (
        set "ROOT="
        del "%CFG%" 2>nul
        goto select_path
    )
    goto menu
)

echo 找到 %count% 个项目：
echo ======================
for /l %%i in (1,1,%count%) do (
    echo %%i. !proj_name_%%i!   [路径: !proj_path_%%i!]
)
echo.
echo 0. 退出
echo R. 重新选择路径
echo.
set /p choice="请输入数字选择项目: "

if /i "%choice%"=="R" (
    set "ROOT="
    del "%CFG%" 2>nul
    goto select_path
)
if "%choice%"=="0" exit
if not defined proj_path_%choice% (
    echo 无效选择
    pause
    goto menu
)

set "selected_path=!proj_path_%choice%!"
set "selected_name=!proj_name_%choice%!"

:action
cls
echo 当前选择：%selected_name%
echo 路径：%selected_path%
echo ======================
echo 1. 启动（后台运行）
echo 2. 停止
echo 3. 查看状态
echo 4. 查看实时日志（最后50行）
echo 5. 返回主菜单
echo R. 重新选择路径
echo.
set /p act="请输入操作: "

if /i "%act%"=="R" (
    set "ROOT="
    del "%CFG%" 2>nul
    goto select_path
)
if "%act%"=="1" (
    call :check_docker
    if errorlevel 1 (
        echo Docker 启动失败，操作中止
        pause
        goto action
    )
    cd /d "%selected_path%" 2>nul || ( echo 路径无效 & pause & goto action )
    docker compose up -d
    echo 启动完成
    pause
    goto action
)
if "%act%"=="2" (
    cd /d "%selected_path%" 2>nul || ( echo 路径无效 & pause & goto action )
    docker compose down
    echo 已停止
    pause
    goto action
)
if "%act%"=="3" (
    cd /d "%selected_path%" 2>nul || ( echo 路径无效 & pause & goto action )
    docker compose ps
    pause
    goto action
)
if "%act%"=="4" (
    cd /d "%selected_path%" 2>nul || ( echo 路径无效 & pause & goto action )
    echo 实时日志（按 Ctrl+C 退出）
    docker compose logs -f --tail=50
    pause
    goto action
)
if "%act%"=="5" goto menu
goto action