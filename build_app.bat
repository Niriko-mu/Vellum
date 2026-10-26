@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "EXIT_CODE=1"
set "NO_PAUSE=0"
if /i "%~1"=="--no-pause" set "NO_PAUSE=1"

rem Build ABI-split Release APKs for Vellum and rename them for GitHub Release.
rem Output: build\app\outputs\flutter-apk\Vellum-V<version>-<abi>.apk

cd /d "%~dp0"
echo === Vellum Android Release Builder ===
echo [1/4] Checking Flutter SDK and project...

set "VELLUM_FLUTTER="
for /f "delims=" %%F in ('where flutter.bat 2^>nul') do (
  if not defined VELLUM_FLUTTER set "VELLUM_FLUTTER=%%F"
)
if not defined VELLUM_FLUTTER (
  echo [ERROR] Flutter SDK was not found on PATH.
  goto finish
)
echo SDK: !VELLUM_FLUTTER!

if not exist pubspec.yaml (
  echo [ERROR] pubspec.yaml was not found in %CD%.
  goto finish
)

set "RAW_VERSION="
set "VERSION="
for /f "tokens=2 delims=:" %%V in ('findstr /r /c:"^version:" pubspec.yaml') do set "RAW_VERSION=%%V"
for /f "tokens=1 delims=+ " %%V in ("!RAW_VERSION!") do set "VERSION=%%V"
if "!VERSION!"=="" (
  echo [ERROR] Could not read the version from pubspec.yaml.
  goto finish
)

set "OUT=build\app\outputs\flutter-apk"
if not exist build mkdir build
set "VELLUM_BUILD_LOG=%CD%\build\build_app.log"
>"!VELLUM_BUILD_LOG!" echo Vellum V!VERSION! build started: %DATE% %TIME%
echo Log: !VELLUM_BUILD_LOG!
echo.
echo [2/4] Resolving project dependencies...
rem Skip the Flutter SDK update check: its git fetch can hang before any output.
rem Keep real dependency resolution enabled, and retain the native exit code.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& $env:ComSpec /d /c ('call '+[char]34+$env:VELLUM_FLUTTER+[char]34+' --no-version-check pub get 2>&1') | ForEach-Object { $_; $_ | Out-File -LiteralPath $env:VELLUM_BUILD_LOG -Append -Encoding utf8 }; exit $LASTEXITCODE"
if errorlevel 1 (
  echo [ERROR] Dependency resolution failed. See !VELLUM_BUILD_LOG!
  goto finish
)

echo.
echo [3/4] Building ABI-split Release APKs for Vellum V!VERSION!...
echo Gradle compilation may take several minutes. Output is also saved to the log.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& $env:ComSpec /d /c ('call '+[char]34+$env:VELLUM_FLUTTER+[char]34+' --no-version-check build apk --release --split-per-abi --no-pub 2>&1') | ForEach-Object { $_; $_ | Out-File -LiteralPath $env:VELLUM_BUILD_LOG -Append -Encoding utf8 }; exit $LASTEXITCODE"
if errorlevel 1 (
  echo [ERROR] Release APK build failed. See !VELLUM_BUILD_LOG!
  goto finish
)

echo.
echo [4/4] Checking and renaming APKs...
for %%A in (armeabi-v7a arm64-v8a x86_64) do (
  if not exist "!OUT!\app-%%A-release.apk" (
    echo [ERROR] Expected build artifact is missing: !OUT!\app-%%A-release.apk
    goto finish
  )
)
for %%A in (armeabi-v7a arm64-v8a x86_64) do (
  set "SOURCE=!OUT!\app-%%A-release.apk"
  set "TARGET=!OUT!\Vellum-V!VERSION!-%%A.apk"
  move /y "!SOURCE!" "!TARGET!" >nul
  if errorlevel 1 (
    echo [ERROR] Failed to rename %%A APK.
    goto finish
  )
)

echo.
echo === Renamed outputs ===
for %%F in ("%OUT%\Vellum-V!VERSION!-*.apk") do (
  if exist "%%~fF" (
    echo %%~nxF  %%~zF bytes
    certutil -hashfile "%%~fF" SHA256 | findstr /r /v "^$ SHA256"
  )
)

echo.
echo [OK] ABI-split Release APKs are ready in:
echo %CD%\%OUT%
set "EXIT_CODE=0"

:finish
echo.
if "!NO_PAUSE!"=="0" (
  echo Press any key to close this window. Use --no-pause for automated builds.
  pause >nul
)
exit /b !EXIT_CODE!
