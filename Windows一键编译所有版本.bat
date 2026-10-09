@echo off
chcp 65001 >nul
echo ========================================
echo  锐捷认证客户端 - 多平台编译脚本
echo ========================================

if exist ruijie_* del ruijie_*

echo [1/6] 编译 Windows x86_64...
set GOOS=windows&set GOARCH=amd64&set CGO_ENABLED=0
go build -ldflags="-s -w" -o ruijie_windows_amd64.exe main.go

echo [2/6] 编译 Linux x86_64...
set GOOS=linux&set GOARCH=amd64&set CGO_ENABLED=0
go build -ldflags="-s -w" -o ruijie_linux_amd64 main.go

echo [3/6] 编译 Linux ARMv8...
set GOOS=linux&set GOARCH=arm64&set CGO_ENABLED=0
go build -ldflags="-s -w" -o ruijie_linux_arm64 main.go

echo [4/6] 编译 Linux ARMv7...
set GOOS=linux&set GOARCH=arm&set GOARM=7&set CGO_ENABLED=0
go build -ldflags="-s -w" -o ruijie_linux_armv7 main.go

echo [5/6] 编译 macOS Intel...
set GOOS=darwin&set GOARCH=amd64&set CGO_ENABLED=0
go build -ldflags="-s -w" -o ruijie_macos_amd64 main.go

echo [6/6] 编译 macOS Apple Silicon...
set GOOS=darwin&set GOARCH=arm64&set CGO_ENABLED=0
go build -ldflags="-s -w" -o ruijie_macos_arm64 main.go

echo.
echo ========================================
echo  编译完成！
echo ========================================
dir ruijie_*
pause
