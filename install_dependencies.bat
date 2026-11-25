@echo off
setlocal
echo FrontBack dependency installer
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_dependencies.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" (
    echo Installation completed successfully.
) else (
    echo Installation did not complete. Review the messages above.
)
pause
exit /b %EXIT_CODE%
