# Liquid Glass App Icon 设置

> 发布状态：沿用既有 AppIcon asset name、bundle identity 和正式图标。以下导入说明仍然适用。

## 选择结果

制作了三个原创方向：

- A — Glass GPA：GPA 字样 + 上升轨迹；小尺寸识别最强，与 Dashboard Hero 最一致。
- B — Glass 4.0：视觉集中，但更容易像普通 GPA calculator。
- C — Academic Glass Mark：独特，但 60 pt 下书页与曲线信息损失较多。

正式选择 A，并进行了第二轮优化：增加安全边距、缩短趋势线、加强 GPA 字重、统一左上光源、降低环境光饱和度、减小阴影与边框存在感。正式文件为 `candidate_a_glass_gpa_round2.svg`。

## 文件

`Documentation/Icon/Layers`：

1. `icon_background.svg` — 深海军蓝空间渐变。
2. `icon_ambient_glow.svg` — 右上冰蓝、左下暖金环境光。
3. `icon_glass_card.svg` — 主玻璃成绩卡。
4. `icon_primary_gpa.svg` — GPA、趋势线和上升点。
5. `icon_highlight.svg` — 左上镜面高光。
6. `icon_depth.svg` — 柔和深度阴影。

`Documentation/Icon/Previews` 包含 Default、Dark、Clear、Tinted、Monochrome、候选、两轮方案、小尺寸和浅/深主屏幕 PNG。

项目当前使用 `AppIcon1024.png` 作为可以立即编译的临时/正式 raster fallback。它由正式 SVG 确定性渲染，不是 AI 生成图片。

## 导入 Icon Composer

1. 打开 Xcode 附带的 Icon Composer。
2. New Document，选择 iOS App Icon，画布 1024 × 1024。
3. 按上面的 1→6 顺序导入 SVG；每个 SVG 保持原始画布位置，不要自动裁切内容。
4. Background depth 设为 0。
5. Ambient 两个 glow depth 约 0.05，opacity 保持 SVG 内值。
6. Glass Card depth 约 0.18；Material 选择标准 glass，折射 low-to-medium，specular 约 20%，不要另加厚描边。
7. Primary Symbol depth 约 0.30；保持 GPA 为主要轮廓。趋势线不使用独立发光。
8. Highlight depth 约 0.34；blend 使用 Screen/Lighten，强度低。
9. Depth layer 置于 Glass Card 后；soft shadow，Y offset 小，blur 大。
10. 只启用轻微系统视差、环境光响应与动态阴影；不启用旋转、闪烁或呼吸动画。
11. 分别查看 Default、Dark、Clear、Tinted 和 Monochrome；若 Tinted 时金色消失，GPA 与曲线必须仍靠明暗结构可辨。
12. 导出 `.icon`，在 Xcode Target > General > App Icons and Accent Colors 中选择它；保留 Assets fallback 直到真机确认。

当前环境虽然已安装 Icon Composer，但没有可靠的命令行文档格式可用于无损自动生成 `.icon` 工程，因此没有伪造该文件。全部可导入图层和设置均已交付，不阻塞主应用。
