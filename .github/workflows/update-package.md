# Package.swift 自动更新说明

## 工作流程

当你推送一个新的 release tag 时（例如 `M143.0-aac`），GitHub Actions 会自动：

1. **构建 XCFramework**
   - 编译所有平台（iOS、模拟器、Catalyst、macOS）
   - 打包为 `WebRTC-M143.0-aac.xcframework.zip`
   - 计算 SHA256 checksum

2. **创建 GitHub Release**
   - 上传 XCFramework.zip
   - 生成 Release Notes
   - 包含 SwiftPM 集成说明

3. **自动更新 Package.swift**
   - 用新的 Release URL 替换旧 URL
   - 更新 checksum
   - 自动提交并推送到 main 分支

## 手动更新 Package.swift（如需要）

如果自动更新失败，可以手动更新：

```bash
# 1. 下载最新 Release 的 XCFramework
wget https://github.com/Ahua9527/WebRTC-AAC-Kit/releases/download/M143.0-aac/WebRTC-M143.0-aac.xcframework.zip

# 2. 计算 checksum
swift package compute-checksum WebRTC-M143.0-aac.xcframework.zip

# 3. 编辑 Package.swift，更新 URL 和 checksum
vim Package.swift

# 4. 提交
git add Package.swift
git commit -m "chore: update Package.swift for M143.0-aac"
git push origin main
```

## 验证

推送 tag 后，检查以下内容：

1. **GitHub Actions 运行成功**
   - 访问 `https://github.com/Ahua9527/WebRTC-AAC-Kit/actions`
   - 确认 Release 工作流成功完成

2. **Release 已创建**
   - 访问 `https://github.com/Ahua9527/WebRTC-AAC-Kit/releases`
   - 验证新 Release 存在且包含 XCFramework.zip

3. **Package.swift 已更新**
   - 检查 main 分支的 Package.swift
   - 确认 URL 和 checksum 正确

4. **SPM 可用**
   - 在 Xcode 中尝试添加 Package Dependency
   - 验证可以选择新版本

## 故障排除

### Package.swift 未自动更新

**可能原因：**
- GitHub Actions 权限不足
- sed 命令失败

**解决方案：**
手动更新（参考上面的步骤）

### Xcode 无法找到版本

**可能原因：**
- Git tag 格式不正确
- Release 未创建成功

**解决方案：**
```bash
# 检查 tag 格式
git tag -l

# 重新推送 tag
git push --delete origin M143.0-aac
git push origin M143.0-aac
```

### Checksum 验证失败

**可能原因：**
- Package.swift 中的 checksum 不正确

**解决方案：**
重新计算并更新：
```bash
wget <release-url>
swift package compute-checksum <archive>
# 更新 Package.swift
```
