# WebRTC AAC Kit

WebRTC AAC Kit 为原生 WebRTC iOS 框架提供生产就绪的 AAC (RFC 3640) 解码器，打包为支持设备 (arm64) 和模拟器 (x86_64) 的 XCFramework。该 Kit 与上游 WebRTC 保持版本同步，同时扩展标准的 `mpeg4-generic` 音频载荷支持。

## 功能特性
- 完整的 RFC 3640 AU 头部解析，支持可配置的 `sizelength` / `indexlength` / `indexdeltalength` 处理
- AudioSpecificConfig (ASC) 解析器和生成器，当前支持 AAC-LC 配置（8kHz–96kHz，单声道/立体声）
- 通过 AudioToolbox 实现的 iOS 硬件加速解码路径，具备运行时能力检查和 PLC 降级支持
- 集成到 WebRTC 构建图的 GN/Ninja 构建目标，以及自动化的 XCFramework 打包脚本

## 代码仓库布局
- `src/` – 带有 AAC 编解码器添加的 WebRTC 源码树（`modules/audio_coding/codecs/aac`、`api/audio_codecs/aac`）
- `scripts/create_xcframework.sh` – 为构建的框架封装 `xcodebuild -create-xcframework`
- `examples/simple_aac_test.swift` – 演示集成工厂的轻量级验证脚本

## 从源码构建
先决条件：macOS 12+、Xcode 14+、iOS SDK 13+，以及本地可用的 `depot_tools`。

```bash
# 环境设置
cd /Users/professional/Dev/WebRTC-AAC-Kit/src
export PATH="/Users/professional/depot_tools:$PATH"

# 设备构建 (arm64)
./buildtools/mac/gn gen out_ios_arm64 --args='
is_debug=false
target_os="ios"
target_cpu="arm64"
target_environment="device"
ios_deployment_target="13.0"
ios_enable_code_signing=false
use_lld=true
enable_dsyms=true
symbol_level=1
rtc_include_tests=false
'
ninja -C out_ios_arm64 framework_objc

# 模拟器构建 (x86_64)
./buildtools/mac/gn gen out_ios_x64_sim --args='
is_debug=false
target_os="ios"
target_cpu="x64"
target_environment="simulator"
ios_deployment_target="13.0"
ios_enable_code_signing=false
use_lld=true
enable_dsyms=true
symbol_level=1
rtc_include_tests=false
'
ninja -C out_ios_x64_sim framework_objc

# 打包 XCFramework（从仓库根目录运行）
cd /Users/professional/Dev/WebRTC-AAC-Kit
bash scripts/create_xcframework.sh
```

> [信息] 打包脚本使用 `xcodebuild -sdk ios -version` 打印 SDK 元数据。如果本地未安装该 SDK，您可能会看到 "SDK ios cannot be located"；XCFramework 仍会在 `src/WebRTC.xcframework` 下生成。

### 自动化多平台构建
使用 `scripts/build_all_configs.sh` 编译每个请求的切片（iOS 设备、模拟器、Catalyst 和 macOS）并输出统一的 XCFramework：
```bash
cd /Users/professional/Dev/WebRTC-AAC-Kit
scripts/build_all_configs.sh
```

- 默认产物位于 `src/WebRTC.xcframework`；如需自定义名称，可在调用前设置 `OUTPUT_NAME=<YourName>.xcframework`
- 必要时覆盖平台最低版本，例如 `CATALYST_TARGET=14.0 MAC_TARGET=12.0 scripts/build_all_configs.sh`
- 自动启用 Objective-C/C 导出（`rtc_enable_objc_symbol_export=true`、`rtc_enable_symbol_export=true`），确保生成的框架在 Xcode 中链接干净
- 脚本假设 `gn`、`ninja`、`xcodebuild` 和 `lipo` 在 `PATH` 中可用；确保事先配置好 `depot_tools`
- 每个构建目录（`src/out_*`）都会重新生成；重用它们以加速增量重建

## 使用 XCFramework

### Xcode 项目
1. 将 `src/WebRTC.xcframework` 拖入您的项目并启用 *Embed & Sign*
2. 链接 `WebRTC.framework` 并导入 `<WebRTC/WebRTC.h>`（Obj-C）或 `import WebRTC`（Swift）

### Swift Package Manager
```swift
.binaryTarget(
    name: "WebRTC",
    path: "./src/WebRTC.xcframework"
)
```

### CocoaPods（私有规范示例）
```ruby
Pod::Spec.new do |s|
  s.name    = 'WebRTC-AAC'
  s.version = '0.0.1'
  s.summary = 'WebRTC framework with RFC 3640 AAC decoder support'
  s.platform = :ios, '13.0'
  s.vendored_frameworks = 'src/WebRTC.xcframework'
end
```

## 运行时说明
- 使用标准 WebRTC 助手创建工厂（`RTC.createDefaultAudioDecoderFactory()`）以自动获取 AAC 实现
- 使用符合 RFC 3640 的 SDP，例如：
  ```
  m=audio 9 UDP/TLS/RTP/SAVPF 96
  a=rtpmap:96 mpeg4-generic/44100/2
  a=fmtp:96 streamType=5;mode=AAC-hbr;objectType=2;samplingFrequency=44100;
           channelCount=2;sizelength=13;indexlength=3;indexdeltalength=3
  ```

## 验证代码片段
```bash
# 确认导出的 AAC 符号
nm src/WebRTC.xcframework/ios-arm64/WebRTC.framework/WebRTC | grep AudioDecoderAac

# 检查目标架构
lipo -info src/WebRTC.xcframework/ios-arm64/WebRTC.framework/WebRTC
lipo -info src/WebRTC.xcframework/ios-x86_64-simulator/WebRTC.framework/WebRTC
```

## 延伸阅读
- `WebRTC-AAC-Kit Technical Documentation.md` – Framework 完整技术规范（1,510行）
- `WebRTC-AAC-Support-for-MediaMTX.md` – 服务器端（MediaMTX）集成指南
- `CLAUDE.md` – 开发者指引（Claude Code 专用）

## 许可证
所有修改遵循上游 WebRTC BSD 许可证；许可证和专利文本请参考原始 WebRTC 仓库。