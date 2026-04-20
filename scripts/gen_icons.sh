#!/bin/zsh
cd ../

SRC="WatchFix.png"

# App 图标
sips -z 29 29   "$SRC" --out App/Resources/AppIcon29x29.png
sips -z 58 58   "$SRC" --out App/Resources/AppIcon29x29@2x.png
sips -z 87 87   "$SRC" --out App/Resources/AppIcon29x29@3x.png
sips -z 40 40   "$SRC" --out App/Resources/AppIcon40x40.png
sips -z 80 80   "$SRC" --out App/Resources/AppIcon40x40@2x.png
sips -z 120 120 "$SRC" --out App/Resources/AppIcon40x40@3x.png
sips -z 50 50   "$SRC" --out App/Resources/AppIcon50x50.png
sips -z 100 100 "$SRC" --out App/Resources/AppIcon50x50@2x.png
sips -z 114 114 "$SRC" --out App/Resources/AppIcon57x57@2x.png
sips -z 171 171 "$SRC" --out App/Resources/AppIcon57x57@3x.png
sips -z 60 60   "$SRC" --out App/Resources/AppIcon60x60.png
sips -z 120 120 "$SRC" --out App/Resources/AppIcon60x60@2x.png
sips -z 180 180 "$SRC" --out App/Resources/AppIcon60x60@3x.png
sips -z 72 72   "$SRC" --out App/Resources/AppIcon72x72.png
sips -z 76 76   "$SRC" --out App/Resources/AppIcon76x76.png
sips -z 144 144 "$SRC" --out App/Resources/AppIcon72x72@2x.png
sips -z 152 152 "$SRC" --out App/Resources/AppIcon76x76@2x.png

# Preferences 图标
sips -z 29 29 "$SRC" --out Preferences/Resources/icon.png
sips -z 58 58 "$SRC" --out Preferences/Resources/icon@2x.png
sips -z 87 87 "$SRC" --out Preferences/Resources/icon@3x.png

echo "=== 完成 ==="
ls -la App/Resources/AppIcon*.png Preferences/Resources/icon*.png
