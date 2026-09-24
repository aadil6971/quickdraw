# Icon assets

QuickDraw.svg is the vector source: coral rounded tile, translucent box, and Lucide arrow-up-right. QuickDraw.png is the 1024 px transparent render. QuickDraw.icns contains standard macOS icon sizes.

The arrow was retrieved using the find-assets tool from Iconify's Lucide collection. See LUCIDE-LICENSE for attribution and licensing.

To regenerate the icon on macOS, render QuickDraw.svg to a transparent 1024 × 1024 PNG, then create a QuickDraw.iconset with 16, 32, 128, 256, and 512 px images at 1× and 2×. Run `iconutil -c icns QuickDraw.iconset`.
