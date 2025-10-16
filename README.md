# WebRTC AAC Kit

WebRTC AAC Kit 为原生 WebRTC iOS 框架提供生产就绪的 AAC (RFC 3640) 解码器，打包为支持设备 (arm64)的 XCFramework。该 Kit 与上游 WebRTC 保持版本同步，同时扩展标准的 `mpeg4-generic` 音频载荷支持。

## 功能特性
- 完整的 RFC 3640 AU 头部解析，支持可配置的 `sizelength` / `indexlength` / `indexdeltalength` 处理
- AudioSpecificConfig (ASC) 解析器和生成器，当前支持 AAC-LC 配置（8kHz–96kHz，单声道/立体声）
- 通过 AudioToolbox 实现的 iOS 硬件加速解码路径，具备运行时能力检查和 PLC 降级支持


## 安装方式

### Swift Package Manager（推荐）

**在 Xcode 中添加依赖：**

1. 打开你的 Xcode 项目
2. 选择 **File → Add Package Dependencies...**
3. 输入仓库 URL：
   ```
   https://github.com/Ahua9527/WebRTC-AAC-Kit.git
   ```
4. 选择版本规则（推荐：**Up to Next Major**）
5. 点击 **Add Package**

**在 Package.swift 中声明：**

```swift
dependencies: [
    .package(url: "https://github.com/Ahua9527/WebRTC-AAC-Kit.git", from: "M142.0.0")
]
```

**使用框架：**

```swift
import WebRTC

// 创建 PeerConnectionFactory
let factory = RTCPeerConnectionFactory()

// AAC 解码器已自动注册，无需额外配置
```

### 手动集成

1. 从 [Releases](https://github.com/Ahua9527/WebRTC-AAC-Kit/releases) 下载最新的 `WebRTC-M*.xcframework.zip`
2. 解压并将 `WebRTC.xcframework` 拖入 Xcode 项目
3. 在 Target 设置中选择 **Embed & Sign**
4. 导入使用：`import WebRTC`（Swift）或 `#import <WebRTC/WebRTC.h>`（Objective-C）

## 运行时说明
- 使用标准 WebRTC 助手创建工厂（`RTC.createDefaultAudioDecoderFactory()`）以自动获取 AAC 实现
- 使用符合 RFC 3640 的 SDP，例如：
  ```
  m=audio 9 UDP/TLS/RTP/SAVPF 96
  a=rtpmap:96 mpeg4-generic/44100/2
  a=fmtp:96 streamType=5;mode=AAC-hbr;objectType=2;samplingFrequency=44100;
           channelCount=2;sizelength=13;indexlength=3;indexdeltalength=3
  ```

## 延伸阅读
- [WebRTC-AAC-Kit Technical Documentation](WebRTC-AAC-Kit%20Technical%20Documentation.md)  – Framework 完整技术规范（1,510行）

## 许可证
所有修改遵循上游 WebRTC BSD 许可证；许可证和专利文本请参考原始 WebRTC 仓库。