#!/usr/bin/env zsh

echo ""
echo "tauri - distribute.sh - Building for MacOS ARM 64 - M1 macs"
echo ""

tauri build --target aarch64-apple-darwin

echo ""
echo "tauri - distribute.sh - Building for MacOS AMD 64 - Intel macs"
echo ""

tauri build --target x86_64-apple-darwin