@echo off
setlocal
chcp 65001 >nul

rem ===================================================================
rem  PCL CE self-use build
rem  Branch : selfuse (upstream dev + removed region restriction)
rem  Usage  : build-selfuse.cmd [Release^|Debug]     (default: Release)
rem  Output : publish\selfuse\Plain Craft Launcher 2.exe
rem
rem  Optional file selfuse.env (repo root, git-ignored) is loaded first,
rem  one KEY=VALUE per line, '#' starts a comment. Recognised keys:
rem    SELFUSE_DOTNET = full path to a dotnet.exe with SDK 10.0.402+
rem    HTTPS_PROXY / HTTP_PROXY = proxy for NuGet restore
rem    PCL_MS_CLIENT_ID, PCL_CURSEFORGE_API_KEY, ... = build-time secrets
rem  NOTE: any PCL_* key present there is COMPILED INTO the binary.
rem ===================================================================

set "ROOT=%~dp0"
set "CONFIG=%~1"
if not defined CONFIG set "CONFIG=Release"

if exist "%ROOT%selfuse.env" (
    for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%ROOT%selfuse.env") do (
        if not "%%A"=="" set "%%A=%%B"
    )
    rem tell the source generator to bake the PCL_* values in
    set "PCL_WRITE_SECRET=1"
    echo [info] loaded selfuse.env
)

if not defined SELFUSE_DOTNET set "SELFUSE_DOTNET=dotnet"

"%SELFUSE_DOTNET%" --list-sdks > "%TEMP%\pcl-selfuse-sdks.txt" 2>nul
if errorlevel 1 (
    echo [ERROR] dotnet SDK not found.
    echo         Install .NET SDK 10.0.402 or newer, or set SELFUSE_DOTNET
    echo         in selfuse.env to a full dotnet.exe path.
    del "%TEMP%\pcl-selfuse-sdks.txt" >nul 2>&1
    exit /b 9009
)

rem The source generators reference Roslyn 5.6, so SDK 10.0.100 fails with
rem CS9248; 10.0.402 or newer is required.
findstr /r /c:"^10\.0\.[4-9]" /c:"^1[1-9]\." "%TEMP%\pcl-selfuse-sdks.txt" >nul
if errorlevel 1 (
    echo [ERROR] SDK too old. Need 10.0.402 or newer, found:
    type "%TEMP%\pcl-selfuse-sdks.txt"
    del "%TEMP%\pcl-selfuse-sdks.txt" >nul 2>&1
    exit /b 1
)
del "%TEMP%\pcl-selfuse-sdks.txt" >nul 2>&1

echo [info] building %CONFIG% / x64 with "%SELFUSE_DOTNET%"
pushd "%ROOT%"
"%SELFUSE_DOTNET%" publish "Plain Craft Launcher 2\Plain Craft Launcher 2.csproj" ^
    -c %CONFIG% -p:Platform=x64 -p:SelfContained=true -p:DeleteExistingFiles=true ^
    -o "%ROOT%publish\selfuse"
set "RC=%ERRORLEVEL%"
popd

if not "%RC%"=="0" (
    echo [ERROR] build failed, exit code %RC%
    exit /b %RC%
)

echo.
echo [done] "%ROOT%publish\selfuse\Plain Craft Launcher 2.exe"
exit /b 0
