#!/usr/bin/env zsh

echo ""
echo "Creating icons from sway-us-lightx1376.png"
echo ""

convert sway-us-lightx1376.png -resize 32x32 32x32.png
convert sway-us-lightx1376.png -resize 128x128 128x128.png
convert sway-us-lightx1376.png -resize 1024x1024 1024x1024.png
convert sway-us-lightx1376.png -resize 512x512 512x512.png
convert sway-us-lightx1376.png -resize 512x512 icon.png
convert sway-us-lightx1376.png -resize 256x256 128x128@2x.png
convert sway-us-lightx1376.png -resize 107x107 Square107x107Logo.png
convert sway-us-lightx1376.png -resize 142x142 Square142x142Logo.png
convert sway-us-lightx1376.png -resize 150x150 Square150x150Logo.png
convert sway-us-lightx1376.png -resize 284x284 Square284x284Logo.png
convert sway-us-lightx1376.png -resize 30x30 Square30x30Logo.png
convert sway-us-lightx1376.png -resize 310x310 Square310x310Logo.png
convert sway-us-lightx1376.png -resize 44x44 Square44x44Logo.png
convert sway-us-lightx1376.png -resize 71x71 Square71x71Logo.png
convert sway-us-lightx1376.png -resize 89x89 Square89x89Logo.png
convert sway-us-lightx1376.png -resize 50x50 StoreLogo.png

# https://stackoverflow.com/a/20703594/6410635
rm -rf Sway.iconset
mkdir -p Sway.iconset
sips -z 16 16     1024x1024.png --out Sway.iconset/icon_16x16.png
sips -z 32 32     1024x1024.png --out Sway.iconset/icon_16x16@2x.png
sips -z 32 32     1024x1024.png --out Sway.iconset/icon_32x32.png
sips -z 64 64     1024x1024.png --out Sway.iconset/icon_32x32@2x.png
sips -z 128 128   1024x1024.png --out Sway.iconset/icon_128x128.png
sips -z 256 256   1024x1024.png --out Sway.iconset/icon_128x128@2x.png
sips -z 256 256   1024x1024.png --out Sway.iconset/icon_256x256.png
sips -z 512 512   1024x1024.png --out Sway.iconset/icon_256x256@2x.png
sips -z 512 512   1024x1024.png --out Sway.iconset/icon_512x512.png
cp 1024x1024.png Sway.iconset/icon_512x512@2x.png
cp 1024x1024.png Sway.iconset/icon_512x512@2x.png
iconutil -c icns Sway.iconset
cp Sway.icns icon.icns

# https://stackoverflow.com/a/49823738/6410635
convert -background transparent "sway-us-lightx1376.png" -define icon:auto-resize=16,24,32,48,64,72,96,128,256 "icon.ico"