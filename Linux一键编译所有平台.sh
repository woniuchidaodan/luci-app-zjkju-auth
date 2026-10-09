#!/bin/bash
echo "========================================"
echo "  锐捷认证客户端 - 多平台编译脚本"
echo "========================================"

rm -f ruijie_*

echo "[1/6] 编译 Windows x86_64..."
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o ruijie_windows_amd64.exe main.go

echo "[2/6] 编译 Linux x86_64..."
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o ruijie_linux_amd64 main.go

echo "[3/6] 编译 Linux ARMv8..."
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="-s -w" -o ruijie_linux_arm64 main.go

echo "[4/6] 编译 Linux ARMv7..."
GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build -ldflags="-s -w" -o ruijie_linux_armv7 main.go

echo "[5/6] 编译 macOS Intel..."
GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o ruijie_macos_amd64 main.go

echo "[6/6] 编译 macOS Apple Silicon..."
GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="-s -w" -o ruijie_macos_arm64 main.go

echo ""
echo "========================================"
echo "  编译完成！"
echo "========================================"
ls -lh ruijie_*
