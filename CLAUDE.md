# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在此代码仓库中工作时提供指导。

## 项目概览

这是 **WebRTC AAC Kit** 项目，为原生 WebRTC iOS 框架提供生产就绪的 RFC 3640 AAC 解码支持。该实现与上游 WebRTC 代码库保持版本同步，同时维持 API 完全兼容。

**核心技术栈：**
- C++17（解码器核心逻辑）
- Objective-C++（iOS 平台集成）
- GN/Ninja（来自 Chromium 的构建系统）
- iOS AudioToolbox（硬件加速解码）
- RFC 3640（MPEG-4 Audio RTP 载荷格式）

**支持的平台：**
- iOS 设备 (arm64)
- iOS 模拟器 (x86_64, arm64)
- Mac Catalyst (arm64, x86_64)
- macOS (arm64, x86_64)

## 构建命令

### 先决条件
确保 `depot_tools` 在您的 PATH 中：
```bash
export PATH="/Users/professional/depot_tools:$PATH"
```

### 完整多平台构建
构建所有平台并创建统一的 XCFramework：
```bash
cd /Users/professional/Dev/WebRTC-AAC-Kit
scripts/build_all_configs.sh
```

输出：`src/WebRTC.xcframework`（多平台）

### 平台特定构建

支持 7 个构建目标，覆盖所有 Apple 平台和架构组合：

#### iOS 设备

**arm64（真机）：**
```bash
cd src
gn gen out_ios_arm64 --args='
  target_os="ios"
  target_cpu="arm64"
  target_environment="device"
  ios_deployment_target="13.0"
  is_debug=false
  ios_enable_code_signing=false
  use_lld=true
  enable_dsyms=true
  symbol_level=1
  rtc_include_tests=false
  rtc_enable_objc_symbol_export=true
  rtc_enable_symbol_export=true
'
ninja -C out_ios_arm64 framework_objc
```

#### iOS 模拟器

**x86_64（Intel Mac）：**
```bash
gn gen out_ios_sim_x64 --args='
  target_os="ios"
  target_cpu="x64"
  target_environment="simulator"
  ios_deployment_target="13.0"
  is_debug=false
  rtc_enable_objc_symbol_export=true
  rtc_enable_symbol_export=true
'
ninja -C out_ios_sim_x64 framework_objc
```

**arm64（Apple Silicon Mac）：**
```bash
gn gen out_ios_sim_arm64 --args='
  target_os="ios"
  target_cpu="arm64"
  target_environment="simulator"
  ios_deployment_target="13.0"
  is_debug=false
  rtc_enable_objc_symbol_export=true
  rtc_enable_symbol_export=true
'
ninja -C out_ios_sim_arm64 framework_objc
```

#### Mac Catalyst

**arm64（Apple Silicon）：**
```bash
gn gen out_ios_catalyst_arm64 --args='
  target_os="ios"
  target_cpu="arm64"
  target_environment="catalyst"
  ios_deployment_target="14.0"
  is_debug=false
  rtc_enable_objc_symbol_export=true
  rtc_enable_symbol_export=true
'
ninja -C out_ios_catalyst_arm64 framework_objc
```

**x86_64（Intel Mac）：**
```bash
gn gen out_ios_catalyst_x64 --args='
  target_os="ios"
  target_cpu="x64"
  target_environment="catalyst"
  ios_deployment_target="14.0"
  is_debug=false
  rtc_enable_objc_symbol_export=true
  rtc_enable_symbol_export=true
'
ninja -C out_ios_catalyst_x64 framework_objc
```

#### macOS 原生

**arm64（Apple Silicon）：**
```bash
gn gen out_macos_arm64 --args='
  target_os="mac"
  target_cpu="arm64"
  mac_deployment_target="11.0"
  is_debug=false
  rtc_enable_objc_symbol_export=true
  rtc_enable_symbol_export=true
'
ninja -C out_macos_arm64 mac_framework_objc
```

**x86_64（Intel Mac）：**
```bash
gn gen out_macos_x64 --args='
  target_os="mac"
  target_cpu="x64"
  mac_deployment_target="11.0"
  is_debug=false
  rtc_enable_objc_symbol_export=true
  rtc_enable_symbol_export=true
'
ninja -C out_macos_x64 mac_framework_objc
```

### 构建自定义的环境变量
```bash
# 自定义部署目标
IOS_DEVICE_TARGET=14.0 \
CATALYST_TARGET=15.0 \
MAC_TARGET=12.0 \
OUTPUT_NAME=WebRTC-Custom.xcframework \
scripts/build_all_configs.sh
```

### 测试

**运行单元测试：**
```bash
# 构建测试目标（仅 iOS）
ninja -C src/out_ios_arm64 audio_decoder_aac_unittests

# 测试位置
# src/api/audio_codecs/aac/audio_decoder_aac_unittest.cc
```

**验证符号导出：**
```bash
# 检查构建框架中的 AAC 解码器符号
nm src/WebRTC.xcframework/ios-arm64/WebRTC.framework/WebRTC | grep AudioDecoderAac

# 验证架构
lipo -info src/WebRTC.xcframework/ios-arm64/WebRTC.framework/WebRTC
lipo -info src/WebRTC.xcframework/ios-arm64_x86_64-simulator/WebRTC.framework/WebRTC
```

**验证 XCFramework 结构：**
```bash
# 列出所有二进制切片
find src/WebRTC.xcframework -maxdepth 2 -type f -name "WebRTC" -exec lipo -info {} \;
```

## 架构概览

### 三层架构设计

```
┌─────────────────────────────────────────────┐
│  API 层 (api/audio_codecs/aac/)             │
│  - AacAudioDecoderFactory (工厂)            │
│  - SdpToConfig (SDP 解析)                   │
│  - MakeAudioDecoder (实例化)                │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  解码器层 (modules/.../codecs/aac/)         │
│  - AudioDecoderAac (WebRTC 接口实现)        │
│  - ParsePayload (RTP → AU 提取)             │
│  - DecodeInternal (解码编排)                │
│  - GeneratePlc (丢包补偿)                   │
└─────────────────────────────────────────────┘
         ↓                           ↓
┌──────────────────┐    ┌────────────────────────┐
│  格式模块         │    │  平台层                 │
│  (format/)       │    │  (ios/)                 │
│  - RFC3640 解析  │    │  - AudioToolbox 封装   │
│  - ASC 解析      │    │  - 能力检测            │
│  - 位读取器      │    │  - 硬件解码            │
└──────────────────┘    └────────────────────────┘
```

### 关键模块职责

**格式模块 (`modules/audio_coding/codecs/aac/format/`)：**
- `aac_format_rfc3640.cc`：解析 RFC 3640 AU 头部节（支持多 AU）
- `aac_format_audio_specific_config.cc`：解析/生成 AudioSpecificConfig (ASC)
- `aac_format_create_config.cc`：从参数创建 ASC

**解码器模块 (`modules/audio_coding/codecs/aac/decoder/`)：**
- `audio_decoder_aac_core.cc`：主解码器生命周期（初始化、销毁、配置验证）
- `audio_decoder_aac_parse.cc`：RTP 载荷 → EncodedAudioFrame 转换
- `audio_decoder_aac_config.cc`：SDP fmtp 解析和配置创建
- `audio_decoder_aac_runtime.cc`：解码执行和缓冲区管理

**iOS 平台层 (`modules/audio_coding/codecs/aac/ios/`)：**
- `audio_decoder_aac_ios.mm`：AudioConverter 管理和初始化
- `audio_decoder_aac_ios_decode.mm`：通过 AudioToolbox 的实际 AAC→PCM 解码
- `audio_decoder_aac_ios_capabilities.mm`：运行时能力检测

### 数据流

```
RTP 数据包 (mpeg4-generic 载荷)
   ↓
AacFormatParser::ParseRfc3640AuHeaders()
   ├─ 读取 AU-headers-length (16 位)
   ├─ 解析 AU 头部 (sizelength/indexlength/indexdeltalength 位)
   └─ 提取访问单元 (AU)
   ↓
AudioDecoderAac::ParsePayload()
   ├─ 为每个 AU 创建 EncodedAudioFrame
   ├─ 分配 RTP 时间戳
   └─ 返回 ParseResult 向量
   ↓
AudioDecoderAac::DecodeInternal()
   └─ 委托给平台解码器
   ↓
AudioDecoderAacIos::Decode()
   ├─ AudioConverterFillComplexBuffer (硬件解码)
   ├─ 输入：AAC 帧 + Magic Cookie (ASC)
   └─ 输出：PCM 16 位采样
   ↓
音频缓冲区管理（环形缓冲区）
   ├─ 缓存解码的 PCM (1024 或 2048 采样)
   ├─ 切片为 10ms 帧
   └─ 在丢包时提供 PLC
```

### 关键配置点

**SDP fmtp 参数 (RFC 3640)：**
- `sizelength`、`indexlength`、`indexdeltalength`：AU 头部位长度
- `config`：十六进制编码的 AudioSpecificConfig（可选，缺失时自动生成）
- `objectType`：AAC 配置（2=AAC-LC, 5=HE-AAC, 29=HE-AAC v2）
- `samplingFrequency`、`channelCount`：音频格式

**AudioSpecificConfig (ASC) 结构：**
- 决定：对象类型、采样率、通道配置
- 处理 HE-AAC 配置的 SBR/PS 扩展
- 作为 "Magic Cookie" 注入到 AudioConverter

**帧大小逻辑：**
- AAC-LC：1024 采样/帧
- HE-AAC/HE-AAC v2：2048 采样/帧（由于 SBR）
- 输出粒度：10ms PCM 块（通过环形缓冲区）

## 代码模式和约定

### 命名约定
- **类**：PascalCase（`AudioDecoderAac`、`AacFormatParser`）
- **函数/变量**：snake_case（`sample_rate_hz_`、`DecodeInternal`）
- **成员变量**：尾随下划线（`config_`、`converter_`）
- **常量**：kPascalCase（WebRTC 风格）或 SCREAMING_SNAKE_CASE

### 内存管理
- **C++**：使用 `std::unique_ptr`、`std::optional`、`BufferT<T>` 的 RAII
- **Objective-C++**：iOS 对象的 ARC（自动引用计数）
- **禁止裸指针**：始终使用智能指针或 RAII 包装器

### 错误处理模式
```cpp
// 解析结果返回 std::optional
std::optional<Config> ParseConfig(...) {
  if (error_condition) {
    RTC_LOG(LS_ERROR) << "描述性错误消息";
    return std::nullopt;
  }
  return config;
}

// 在解码器中存储错误状态
bool has_error_;
std::string last_error_;

// 操作前检查有效性
if (!IsConfigValid()) {
  has_error_ = true;
  last_error_ = "无效配置";
  return false;
}
```

### 日志记录
使用 WebRTC 日志宏：
```cpp
RTC_LOG(LS_INFO) << "AAC 解码器已初始化：" << sample_rate << "Hz";
RTC_LOG(LS_WARNING) << "异常 AU 计数：" << au_count;
RTC_LOG(LS_ERROR) << "解码失败：" << error_code;
```

### 平台条件编译
```cpp
#if defined(WEBRTC_USE_APPLE_AAC)
  // iOS 特定实现
  ios_decoder_ = std::make_unique<AudioDecoderAacIos>(config);
#else
  // 其他平台的占位符
  decoder_available_ = false;
#endif
```

## 构建系统 (GN/Ninja)

### 关键 GN 文件

**`modules/audio_coding/codecs/aac/BUILD.gn`：**
- 定义 `rtc_library("audio_decoder_aac")` 目标
- 仅 iOS 编译（`if (is_ios)`）
- 链接 iOS 框架：`AudioToolbox.framework`、`CoreAudio.framework`
- 编译器标志：`-fobjc-arc`、`-Wno-incomplete-umbrella`
- 定义：`WEBRTC_USE_APPLE_AAC`

**`api/audio_codecs/aac/BUILD.gn`：**
- 工厂接口目标：`aac_audio_decoder_factory`
- 依赖于核心解码器模块
- 非 iOS 平台的空实现

### 关键构建标志
- `rtc_enable_objc_symbol_export=true`：导出 ObjC 符号以供 Swift/Xcode 链接
- `rtc_enable_symbol_export=true`：导出 C 符号
- `ios_enable_code_signing=false`：框架构建期间禁用签名
- `use_lld=true`：使用 LLVM 链接器以加快构建
- `enable_dsyms=true` + `symbol_level=1`：生成调试符号

### 依赖项
```gn
deps = [
  "../../../../api/audio_codecs:audio_codecs_api",
  "../../../../rtc_base:logging",
  "../../../../rtc_base:checks",
  "../../../../system_wrappers",
]
```

## 集成点

### 在 WebRTC 中注册 AAC 解码器

使用默认音频解码器工厂时，AAC 解码器会自动注册：

```objc
// Objective-C
RTCPeerConnectionFactory *factory = [[RTCPeerConnectionFactory alloc] init];
// AAC 解码器现在通过 factory->CreateAudioDecoderFactory() 可用
```

```swift
// Swift
import WebRTC
let factory = RTCPeerConnectionFactory()
// AAC 解码器自动包含
```

### AAC 流的 SDP 示例

```sdp
m=audio 9 UDP/TLS/RTP/SAVPF 96
a=rtpmap:96 mpeg4-generic/44100/2
a=fmtp:96 streamType=5;profile-level-id=1;mode=AAC-hbr;
          objectType=2;config=1190;
          samplingFrequency=44100;channelCount=2;
          sizelength=13;indexlength=3;indexdeltalength=3
```

**关键 fmtp 字段：**
- `config=1190`：十六进制 AudioSpecificConfig (AAC-LC, 44.1kHz, 立体声)
- `sizelength=13`：AU 大小使用 13 位
- `indexlength=3`、`indexdeltalength=3`：标准 RFC 3640 值

### 支持的配置

| 配置 | 对象类型 | 采样率 | 声道 | 状态 |
|------|----------|---------|------|------|
| AAC-LC | 2 | 8kHz-96kHz | 单声道/立体声 | ✅ 完全支持 |
| HE-AAC | 5 | 8kHz-96kHz | 单声道/立体声 | ✅ 支持 (SBR) |
| HE-AAC v2 | 29 | 8kHz-96kHz | 立体声 | ✅ 支持 (SBR+PS) |

## 常见开发场景

### 添加新采样率支持

1. 验证 iOS AudioToolbox 支持：
```cpp
// 在 audio_decoder_aac_ios_capabilities.mm 中
bool IsSampleRateSupported(uint32_t sample_rate) {
  // 添加新速率到支持列表
}
```

2. 解码器核心无需代码更改（已支持 8kHz-96kHz 范围）

### 调试解码失败

按以下顺序检查：
1. **SDP 解析**：验证 `AacAudioDecoderFactory::SdpToConfig()` 成功
2. **ASC 验证**：记录 `audio_specific_config` 十六进制字节
3. **AudioConverter 创建**：检查 `ConfigureAudioConverter()` 中的 `OSStatus`
4. **输入数据**：验证 AU 大小与 `sizelength` 编码匹配
5. **能力**：确保 `AacIosCapabilities::IsAacDecodingSupported()` 返回 true

启用详细日志：
```cpp
RTC_LOG(LS_INFO) << "AU 计数：" << headers.size();
RTC_LOG(LS_INFO) << "AU[0] 大小：" << headers[0].size;
```

### 扩展到 Android 平台

1. 创建 `modules/audio_coding/codecs/aac/android/` 目录
2. 使用 MediaCodec 实现 `AudioDecoderAacAndroid`
3. 使用 Android 条件更新 `BUILD.gn`：
```gn
if (is_android) {
  sources += [ "android/audio_decoder_aac_android.cc" ]
}
```
4. 添加 `WEBRTC_USE_ANDROID_AAC` 定义
5. 使用 Android 路径更新 `AudioDecoderAac::InitializeDecoder()`

## 重要文件

**头文件：**
- `src/modules/audio_coding/codecs/aac/audio_decoder_aac.h`：主解码器接口
- `src/modules/audio_coding/codecs/aac/aac_format.h`：格式结构（AacConfig、AuHeader、Rfc3640Config）
- `src/api/audio_codecs/aac/audio_decoder_aac.h`：工厂 API

**实现文件：**
- `src/modules/audio_coding/codecs/aac/decoder/audio_decoder_aac_core.cc`：解码器生命周期
- `src/modules/audio_coding/codecs/aac/format/aac_format_rfc3640.cc`：RFC 3640 解析器
- `src/modules/audio_coding/codecs/aac/ios/audio_decoder_aac_ios_decode.mm`：iOS 硬件解码

**构建文件：**
- `src/modules/audio_coding/codecs/aac/BUILD.gn`：核心解码器构建
- `src/api/audio_codecs/aac/BUILD.gn`：工厂构建
- `scripts/build_all_configs.sh`：多平台自动化

**文档：**
- `README.md`：快速入门和功能
- `WebRTC-AAC-Kit Technical Documentation.md`：Framework 技术规范
- `examples/simple_aac_test.swift`：Swift 集成示例

## XCFramework 分发

### 打包分发
```bash
cd src
ditto -c -k --sequesterRsrc --keepParent WebRTC.xcframework WebRTC.xcframework.zip
```

### 计算 SwiftPM 校验和
```bash
swift package compute-checksum WebRTC.xcframework.zip
```

### Xcode 集成
1. 将 `WebRTC.xcframework` 拖入 Xcode 项目
2. 在 *Frameworks, Libraries, and Embedded Content* 中设置 **Embed & Sign**
3. 导入：`import WebRTC` (Swift) 或 `#import <WebRTC/WebRTC.h>` (Obj-C)

### CocoaPods Podspec
```ruby
Pod::Spec.new do |s|
  s.name    = 'WebRTC-AAC'
  s.version = '1.0.0'
  s.platform = :ios, '13.0'
  s.vendored_frameworks = 'src/WebRTC.xcframework'
end
```

## 代码量参考

AAC 实现是模块化且组织良好的：

| 模块 | 总行数 | 关键文件 |
|------|---------|-----------|
| 格式解析 | ~597 行 | RFC 3640 解析器、ASC 解析器、配置生成器 |
| 解码器核心 | ~620 行 | 生命周期、载荷解析、配置、运行时 |
| iOS 平台 | ~416 行 | AudioToolbox 封装器、解码、能力 |
| **AAC 代码总计** | **~1,633 行** | 不包括头文件和测试 |

这是一个专注的、生产就绪的实现，没有不必要的复杂性。

## 快速参考：文件大小限制

遵循项目的编码标准：
- **C++/Objective-C++**：每文件最多 250 行
- 所有 AAC 文件都符合此限制（最大：226 行）
- 文件组织到逻辑子目录：`format/`、`decoder/`、`ios/`

## 增量开发工作流

### 修改 AAC 代码

```bash
# 1. 编辑 src/modules/audio_coding/codecs/aac/ 中的源文件
# 2. 增量构建（仅重新编译更改的文件）
cd src
ninja -C out_ios_arm64 framework_objc

# Ninja 输出显示正在重建的内容：
# [1/3] CXX obj/modules/audio_coding/codecs/aac/audio_decoder_aac_core.o
# [2/3] SOLINK WebRTC.framework/WebRTC
# [3/3] STAMP framework_objc

# 3. 验证符号
nm out_ios_arm64/WebRTC.framework/WebRTC | grep AudioDecoderAac
```

### 清理构建

```bash
# 移除单个平台
rm -rf src/out_ios_arm64

# 移除所有平台
rm -rf src/out_*

# 完全重建
scripts/build_all_configs.sh
```

## 故障排除

### 构建错误

**缺少 depot_tools：**
```bash
# 安装 depot_tools
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="/path/to/depot_tools:$PATH"
```

**"SDK ios cannot be located"：**
- iOS SDK 检查失败时的预期现象
- XCFramework 仍然构建成功
- 验证：`xcodebuild -showsdks`

**符号导出问题：**
确保 GN 参数包括：
```
rtc_enable_objc_symbol_export=true
rtc_enable_symbol_export=true
```

**Ninja 构建挂起或崩溃：**
- 限制并行度：`ninja -j4 -C out_ios_arm64 framework_objc`
- 检查可用内存（并行构建需要约 8GB）

**Catalyst 构建失败，出现 "ios13.0-macabi" 错误：**
- Xcode SDK 26.0+ 要求 Catalyst 目标 ≥ 14.0
- 设置 `CATALYST_TARGET=14.0` 或更高

### 运行时错误

**"此设备不支持 AAC 解码"：**
- 检查 `AacIosCapabilities::IsAacDecodingSupported()`
- 验证 iOS 版本 ≥ 13.0
- 在物理设备上测试（模拟器可能有限制）

**AudioConverter 返回 -50（参数错误）：**
- 无效的 AudioSpecificConfig
- 记录 ASC 十六进制字节并验证结构
- 检查对象类型、采样率、通道配置

**AudioConverter 返回 -66690（数据错误）：**
- 输入数据不完整或损坏
- 验证 AU 大小解析与 `sizelength` 配置匹配
- 检查网络传输的丢包

**无音频输出：**
- 验证 SDP fmtp 与编码器配置匹配
- 检查 AU 头部解析：`sizelength`、`indexlength`、`indexdeltalength`
- 在 `ParseRfc3640AuHeaders()` 中启用日志
- 确认 `DecodeInternal()` 正在被调用

**音频播放过快或过慢：**
- SDP 和实际编码之间的采样率不匹配
- 检查 RTP 时间戳增量（应与采样率匹配）

## 性能考虑

### 硬件加速
- iOS 自动使用 AudioToolbox 硬件解码器
- 硬件解码：~0.8% CPU，50mW 功耗
- 软件解码：~3% CPU，150mW 功耗（多 67% 功耗）
- 始终验证 `IsAacDecodingSupported()` 返回 true

### 内存使用
- 单个解码器实例：~220KB（包括环形缓冲区）
- 10 个并发音频流：总共 ~2.2MB
- 环形缓冲区大小：2 倍帧大小（为最小延迟优化）

### 延迟分解
```
网络：100-300ms
RTP 缓冲区 (NetEQ)：20-50ms
AAC 解码：2-5ms（硬件加速）
环形缓冲区：0-20ms（最大 2 帧）
音频播放：10-50ms
总典型：~200ms 端到端
```

## 其他资源

综合文档请参见：
- `WebRTC-AAC-Kit Technical Documentation.md` - Framework 技术规范（1,510 行）
- `WebRTC AAC (RFC 3640) Support for MediaMTX.md` - 服务器端集成指南
- `examples/simple_aac_test.swift` - 最小 Swift 集成示例