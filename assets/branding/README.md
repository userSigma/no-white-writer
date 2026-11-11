# 不白写作 Logo

[SVG 源稿](<app_icon.svg>) 为用户于 2026-11-09 提供的原文件，保持原始字节、840×855 比例、灰阶、透明圆角和 SVG 滤镜。[PNG 预览](<app_icon.png>) 为等比置于透明正方形内的 256px 栅格图。

使用已有 Python/Pillow 和本机 Chrome 或 Edge 重建 Windows 图标：

```powershell
python tool/generate_app_icon.py
# 指定浏览器或额外预览文件：
python tool/generate_app_icon.py --browser "C:\Program Files\Google\Chrome\Application\chrome.exe" --preview build/app-icon-preview.png
```

转换仅使用本地文件和新的独立浏览器配置目录。Chromium 保留 SVG 的渐变、裁剪、模糊与 turbulence 纹理；Pillow 生成 16、24、32、48、64、128、256px 多尺寸 ICO。SVG 按原比例完整居中，四周留透明像素，不拉伸或裁边。

Windows 可执行文件、任务栏/快捷方式及 Inno Setup 均复用 [ICO](<../../windows/runner/resources/app_icon.ico>)；未更换应用主题色、文字标题或应用版本。仅重建原生资源时无需添加 Flutter SVG 运行时依赖。
