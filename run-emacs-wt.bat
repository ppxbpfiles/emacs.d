@echo off
setlocal

set "PORTABLE_ROOT=%~dp0"

:: Windows Terminal (wt.exe) ‚ğ‹N“®‚µ‚Ä run-emacs-nw.bat ‚ğÀs
wt.exe --title "Emacs" cmd.exe /c ""%PORTABLE_ROOT%run-emacs-nw.bat" %*"

endlocal
