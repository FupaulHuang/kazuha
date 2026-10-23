@echo off
setlocal
set "COMPOSA_EXE=%~dp0dist\portable\composa-1.4.0-win-x64\composa.exe"
if not exist "%COMPOSA_EXE%" (
  echo Composa is missing. Keep this launcher beside the dist folder.
  pause
  exit /b 1
)
start "" "%COMPOSA_EXE%" %*
