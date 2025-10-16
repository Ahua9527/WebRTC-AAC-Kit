# WebRTC AAC（RFC 3640）支持指南 - 简化版

本文档说明 MediaMTX Extended 在 WebRTC 场景下对 AAC（MPEG-4 Audio）编解码的支持方案。当前版本采用简化实现，仅支持固定的 48kHz AAC-LC 配置，以快速打通基本链路。

## 1. 背景概述

- 浏览器生态默认只保证 Opus/G.711，可选支持 AAC。MediaMTX 需要在 WebRTC 方向与多种 AAC 源（RTSP、SRT、RTMP 等）互通，或从 WebRTC 客户端接收 AAC。
- AAC 采用 RFC 3640（`audio/mpeg4-generic`）封装，`fmtp` 字段包含：
  - `config`: AudioSpecificConfig 的十六进制编码（如 `1190` = 48kHz 立体声 AAC-LC）
  - `sizelength`: AU 长度字段位数（默认 13）
  - `indexlength`: AU 索引字段位数（默认 3）
  - `indexdeltalength`: AU 索引增量字段位数（默认 3）
  - `profile-level-id`: AAC Profile Level（默认 1）
- **当前简化版本**：固定支持 48kHz 立体声 AAC-LC，避免复杂的动态协商逻辑，优先打通基本功能。

## 2. 支持范围

### 2.1 编解码类型

| AAC 类型          | Object Type | 说明                         | 支持状态 |
| ----------------- | ----------- | ---------------------------- | -------- |
| AAC-LC            | 2           | 最常见的低复杂度 AAC        | ✅ (仅 48kHz)       |
| HE-AAC (LC+SBR)   | 5           | 带谱带复制，双倍采样率      | ❌ 待后续支持       |
| HE-AAC v2 (LC+PS) | 29          | 带 Parametric Stereo 扩展   | ❌ 待后续支持       |

- 解析逻辑位于 `internal/protocols/webrtc/aac_fmtp.go`
- 当 `fmtp` 缺少 `config` 时自动回退 AAC-LC 默认配置，保证协商成功

### 2.2 采样率支持

**当前仅支持：48 kHz**

- 如果客户端发送其他采样率（如 44.1kHz、16kHz 等），服务器会返回明确错误
- 入站验证位于 `internal/protocols/webrtc/to_stream.go:160-163`
- 后续版本可根据需求添加其他采样率支持

### 2.3 声道策略

- **固定为 2 声道（立体声）**
- 所有 AAC 流默认按 2 声道处理

## 3. 模块改动概览

### 3.1 静态 Codec 注册

- `internal/protocols/webrtc/incoming_track.go:237-245`
  - 在 `incomingAudioCodecs` 数组中注册固定的 48kHz AAC codec
  - PayloadType 固定为 123
  - fmtp 参数：`streamtype=5;mode=AAC-hbr;config=1190;profile-level-id=1;sizelength=13;indexlength=3;indexdeltalength=3`
  - **config=1190 解析**：
    - 十六进制 `0x1190` = 二进制 `0001 0001 1001 0000`
    - AAC ObjectType: `00010` = 2 (AAC-LC)
    - 采样率索引: `0011` = 3 (48000 Hz)
    - 声道配置: `0010` = 2 (立体声)
  - 不再使用动态 codec 注册机制

### 3.2 公共 fmtp 工具

- `internal/protocols/webrtc/aac_fmtp.go`
  - `ParseMPEG4AudioFMTP` (71-142 行)：解析 SDP fmtp 字符串
    - 提取 `sizelength`, `indexlength`, `indexdeltalength`（默认 13, 3, 3）
    - 解码 `config` 十六进制为 `AudioSpecificConfig`
    - 容错处理：参数缺失时使用默认值
  - `buildMPEG4AudioFMTPLine` (18-59 行)：生成 RFC 3640 fmtp 字符串
    - 序列化 `AudioSpecificConfig` 为十六进制
    - 组装 `streamtype=5;mode=AAC-hbr;config=<hex>;...` 格式
    - 参数顺序固定，确保跨浏览器兼容性

### 3.3 流 → WebRTC（发布/WHEP）

- `internal/protocols/webrtc/from_stream.go:656-730`
  - 检测到 `format.MPEG4Audio` 时，构建固定 48kHz 的 `OutgoingTrack`
  - 使用 `buildMPEG4AudioFMTPLine()` 生成 RFC 3640 fmtp
  - 固定 `ClockRate=48000`、`Channels=2`
  - 通过 `rtpmpeg4audio.Encoder` 将 AAC Access Units 封装为 RTP
  - **RTP 时间戳推进公式** (726-730 行)：
    ```go
    curTimestamp += uint32(len(tunit.AUs)) * mpeg4audio.SamplesPerAccessUnit
    // SamplesPerAccessUnit = 1024 (AAC 标准常量)
    // 例如：收到 3 个 AU → timestamp += 3 * 1024 = 3072 samples
    //       3072 samples / 48000 Hz = 64ms
    ```
  - **NTP 时间戳计算** (721-722 行)：
    ```go
    ntp := u.GetNTP().Add(timestampToDuration(
        int64(pkt.Timestamp - u.GetRTPPackets()[0].Timestamp), 48000))
    // 基于 48kHz 时钟将 RTP timestamp delta 转换为时长
    ```

### 3.4 WebRTC → 流（拉流/WHIP）

- `internal/protocols/webrtc/to_stream.go:137-188`
  - 针对 `audio/mpeg4-generic` MimeType，调用 `ParseMPEG4AudioFMTP` 解析 fmtp
  - **采样率验证**（160-163 行）：只接受 48kHz，其他采样率返回错误
  - 提取 `SizeLength`、`IndexLength`、`IndexDeltaLength`、`AudioSpecificConfig` 写入 `format.MPEG4Audio`
  - 缺省 `config` 时按照 48kHz、2 声道生成 AAC-LC 默认配置
  - 设置 RTP packet 回调，使用 `rtptime.GlobalDecoder` 进行时间戳转换

### 3.5 会话管理

- `internal/servers/webrtc/session.go`
  - **关键流程调整**：将 Offer SDP 的解析移到 PeerConnection 创建**之前**（157-166, 303-312 行）
  - 这样 `filterOfferSDP()` 可以在 PeerConnection 初始化前清理不兼容的 AAC codec
  - 确保 PeerConnection 只处理经过过滤的 Offer SDP

### 3.6 SDP 协商过滤（关键机制）

- `internal/protocols/webrtc/peer_connection.go`

**Offer SDP 过滤** (`filterOfferSDP`, 652-783 行)：
- **目的**：移除客户端 Offer 中不支持的 AAC codec，防止协商到错误配置
- **过滤规则**：
  1. 解析所有 `audio/mpeg4-generic` 的 rtpmap 和 fmtp
  2. 从 fmtp 中提取 `objectType` 参数
  3. 移除 `objectType=1`（AAC Main Profile，已废弃）
  4. 移除非 48kHz 的 AAC codec
- **实现细节**：
  - 构建 PT → codec 信息映射（包括 clockRate, channels, objectType）
  - 从 m= line 的 formats 中移除 bad PT
  - 移除对应的 rtpmap 和 fmtp 属性
  - 记录日志："removed X incompatible AAC codec(s)"
- **典型场景**：Safari/iOS 的 Offer 可能包含多个 AAC codec（44.1kHz, 48kHz, objectType=1 等），必须过滤否则可能协商到不支持的配置

**Answer SDP 修复** (`fixAACFmtp`, 558-587 行)：
- **目的**：确保 Answer 中的 AAC fmtp 与静态注册的 codec 完全一致
- **实现逻辑**：
  1. 查找 `mpeg4-generic/48000` 的 rtpmap，提取 payload type
  2. 强制替换对应的 fmtp 为固定值：`streamtype=5;mode=AAC-hbr;config=1190;profile-level-id=1;sizelength=13;indexlength=3;indexdeltalength=3`
- **为什么需要**：pion/webrtc 可能生成略有差异的 fmtp，强制替换确保与客户端期望一致

**执行时机** (`CreateFullAnswer`, 697-700 行)：
```
1. filterOfferSDP(offer)        // 清理 Offer
2. SetRemoteDescription(offer)   // 设置远端描述
3. CreateAnswer()                // 生成 Answer
4. filterLocalDescription()      // 调用 fixAACFmtp 修复 Answer
5. SetLocalDescription(answer)   // 返回修复后的 Answer
```

## 4. SDP 协商与兼容性处理

### 4.1 问题背景

WebRTC 客户端（特别是 Safari/iOS）在 Offer SDP 中可能包含多个 AAC codec，例如：
- `mpeg4-generic/48000/2` with `objectType=1` (AAC Main)
- `mpeg4-generic/48000/2` with `objectType=2` (AAC-LC)
- `mpeg4-generic/44100/2` with `objectType=2`

如果不进行过滤，SDP 协商可能选中 MediaMTX 不支持的配置（如 AAC Main 或 44.1kHz），导致：
- 音频无法播放（编解码器不兼容）
- RTP 时间戳错误（时钟率不匹配）
- 浏览器控制台报错但无明确提示

### 4.2 Offer SDP 过滤机制

**实现位置**：`internal/protocols/webrtc/peer_connection.go:652-783`

**执行时机**：`session.go` 在创建 PeerConnection **之前**先解析 Offer，然后 `CreateFullAnswer()` 第一步调用 `filterOfferSDP()`

**过滤步骤**：

1. **解析阶段** - 构建 codec 信息映射
   ```go
   // 从 rtpmap 提取：PT → {payloadType, clockRate, channels}
   // 例如："96 mpeg4-generic/48000/2"

   // 从 fmtp 提取：PT → objectType
   // 例如："96 ...;objectType=1;..." → objectType="1"
   ```

2. **判定阶段** - 识别不兼容 codec
   ```go
   if objectType == "1" {
       // AAC Main Profile 已废弃，标记为 bad
   }
   if clockRate != 48000 {
       // 当前仅支持 48kHz，标记为 bad
   }
   ```

3. **清理阶段** - 从 SDP 中移除
   - 从 `m=audio` 的 formats 列表中删除 bad PT
   - 移除对应的 `a=rtpmap:<PT> ...` 属性
   - 移除对应的 `a=fmtp:<PT> ...` 属性

4. **日志输出**
   ```
   [INFO] cleaned offer SDP: removed 2 incompatible AAC codec(s)
   ```

**实际案例**：

过滤前 Offer（Safari 生成）：
```sdp
m=audio 9 UDP/TLS/RTP/SAVPF 96 97 98
a=rtpmap:96 mpeg4-generic/48000/2
a=fmtp:96 streamtype=5;objectType=1;...
a=rtpmap:97 mpeg4-generic/48000/2
a=fmtp:97 streamtype=5;objectType=2;...
a=rtpmap:98 mpeg4-generic/44100/2
a=fmtp:98 streamtype=5;objectType=2;...
```

过滤后 Offer：
```sdp
m=audio 9 UDP/TLS/RTP/SAVPF 97
a=rtpmap:97 mpeg4-generic/48000/2
a=fmtp:97 streamtype=5;objectType=2;...
```

### 4.3 Answer SDP 修复机制

**实现位置**：`internal/protocols/webrtc/peer_connection.go:558-587`

**执行时机**：`filterLocalDescription()` 在生成 Answer 后、返回给客户端前调用

**修复逻辑**：

1. 查找 Answer 中的 AAC codec
   ```go
   // 遍历 a=rtpmap 查找 "mpeg4-generic/48000"
   // 提取对应的 payload type
   ```

2. 强制替换 fmtp
   ```go
   // 将 a=fmtp:<PT> ...
   // 替换为固定值：
   // streamtype=5;mode=AAC-hbr;config=1190;profile-level-id=1;
   // sizelength=13;indexlength=3;indexdeltalength=3
   ```

**为什么需要修复**：
- pion/webrtc 生成的 fmtp 可能缺少某些参数或顺序不同
- 某些客户端严格校验 fmtp 参数
- 统一使用静态注册的 fmtp 确保一致性

### 4.4 完整协商流程

```
┌─────────────────┐
│ WebRTC Client   │
│ (Safari/iOS)    │
└────────┬────────┘
         │ 1. POST /path/whep
         │    Offer SDP (多个 AAC codec)
         ▼
┌─────────────────────────────────────┐
│ session.go:runRead()                │
│ ① 提前解析 Offer SDP                │
│ ② 创建 PeerConnection               │
│ ③ pc.CreateFullAnswer(offer)        │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│ peer_connection.go:CreateFullAnswer │
│ ① filterOfferSDP(offer)             │
│    - 移除 objectType=1              │
│    - 移除非 48kHz codec             │
│ ② SetRemoteDescription(filteredOffer)│
│ ③ CreateAnswer()                    │
│ ④ filterLocalDescription(answer)    │
│    - fixAACFmtp() 修复 fmtp         │
│ ⑤ SetLocalDescription(answer)       │
└────────┬────────────────────────────┘
         │ Answer SDP (仅 48kHz AAC-LC)
         ▼
┌─────────────────┐
│ WebRTC Client   │
│ 协商成功，音频  │
│ 使用 48kHz AAC  │
└─────────────────┘
```

### 4.5 调试技巧

**查看过滤日志**：
```bash
# MediaMTX 日志中搜索
grep "cleaned offer SDP" mediamtx.log
grep "removing AAC" mediamtx.log
```

**典型日志输出**：
```
[WARN] removing AAC Main Profile (objectType=1) from offer: PT=96, 48000Hz, 2ch
[DEBUG] removing non-48kHz AAC codec from offer: PT=98, 44100Hz
[INFO] cleaned offer SDP: removed 2 incompatible AAC codec(s)
```

**手动检查 SDP**：
在浏览器控制台启用 WebRTC 日志，查看 Offer/Answer SDP：
```javascript
// Chrome DevTools → Console
// 设置 chrome://webrtc-internals/
```

## 5. 协商流程（含 SDP 过滤）

完整的 WebRTC AAC 协商流程包含以下步骤：

### 5.1 客户端发布场景（WHIP）

```
┌──────────────┐
│ 1. 客户端    │ 发送 Offer SDP (包含 AAC track)
│   准备发布   │ POST /path/whip
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 2. session.go:runPublish()           │
│    ① 提前解析和验证 Offer SDP        │
│    ② 创建 PeerConnection             │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 3. peer_connection.CreateFullAnswer  │
│    ① filterOfferSDP() 清理不兼容codec│
│    ② SetRemoteDescription(offer)     │
│    ③ CreateAnswer()                  │
│    ④ fixAACFmtp() 修复 Answer        │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 4. to_stream.ToStream()              │
│    ① 解析 AAC fmtp 参数              │
│    ② 验证采样率 = 48kHz              │
│    ③ 创建 format.MPEG4Audio          │
│    ④ 设置 RTP packet 回调            │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 5. RTP 接收                          │
│    ① 客户端发送 AAC RTP packets      │
│    ② rtpmpeg4audio.Decoder 解析 AU   │
│    ③ rtptime.GlobalDecoder 转换 PTS  │
│    ④ 写入 MediaMTX stream            │
└──────────────────────────────────────┘
```

**关键验证点**（`to_stream.go:160-163`）：
```go
if sampleRate != 48000 {
    return nil, fmt.Errorf("only 48kHz AAC is supported, got %dHz", sampleRate)
}
```

### 5.2 客户端播放场景（WHEP）

```
┌──────────────┐
│ 1. 客户端    │ 发送 Offer SDP (请求 AAC)
│   请求拉流   │ POST /path/whep
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 2. session.go:runRead()              │
│    ① 提前解析 Offer SDP              │
│    ② 创建 PeerConnection             │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 3. peer_connection.CreateFullAnswer  │
│    ① filterOfferSDP() 清理           │
│       - 移除 objectType=1            │
│       - 移除非 48kHz codec           │
│    ② SetRemoteDescription(offer)     │
│    ③ CreateAnswer()                  │
│    ④ fixAACFmtp() 修复               │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 4. from_stream.FromStream()          │
│    ① 检测 format.MPEG4Audio          │
│    ② buildMPEG4AudioFMTPLine()       │
│       生成固定 48kHz fmtp            │
│    ③ 创建 OutgoingTrack              │
│    ④ 初始化 rtpmpeg4audio.Encoder    │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 5. RTP 发送                          │
│    ① MediaMTX stream → AAC AUs       │
│    ② Encoder.Encode(AUs) → RTP pkts  │
│    ③ timestamp += AU_count * 1024    │
│    ④ 计算 NTP (基于 48kHz)           │
│    ⑤ track.WriteRTPWithNTP()         │
└──────────────────────────────────────┘
```

**时间戳计算**（`from_stream.go:726-730`）：
```go
curTimestamp += uint32(len(tunit.AUs)) * mpeg4audio.SamplesPerAccessUnit
// SamplesPerAccessUnit = 1024 (AAC 标准)
// 例如：2个AU = 2048 samples = 42.67ms @ 48kHz
```

### 5.3 SDP 协商细节

**Offer SDP 示例**（Safari 原始）：
```sdp
v=0
o=- 123456 2 IN IP4 192.168.1.100
s=-
t=0 0
m=audio 9 UDP/TLS/RTP/SAVPF 96 97 98 111
a=rtpmap:96 mpeg4-generic/48000/2
a=fmtp:96 streamtype=5;mode=AAC-hbr;objectType=1;config=1190;...
a=rtpmap:97 mpeg4-generic/48000/2
a=fmtp:97 streamtype=5;mode=AAC-hbr;objectType=2;config=1190;...
a=rtpmap:98 mpeg4-generic/44100/2
a=fmtp:98 streamtype=5;mode=AAC-hbr;objectType=2;config=1208;...
a=rtpmap:111 opus/48000/2
...
```

**过滤后 Offer**：
```sdp
m=audio 9 UDP/TLS/RTP/SAVPF 97 111
a=rtpmap:97 mpeg4-generic/48000/2
a=fmtp:97 streamtype=5;mode=AAC-hbr;objectType=2;config=1190;...
a=rtpmap:111 opus/48000/2
```
（移除了 PT 96 的 objectType=1 和 PT 98 的 44.1kHz）

**Answer SDP**（MediaMTX 生成）：
```sdp
m=audio 9 UDP/TLS/RTP/SAVPF 97
a=rtpmap:97 mpeg4-generic/48000/2
a=fmtp:97 streamtype=5;mode=AAC-hbr;config=1190;profile-level-id=1;sizelength=13;indexlength=3;indexdeltalength=3
a=sendrecv
```
（fmtp 已通过 `fixAACFmtp()` 修复为固定值）

### 5.4 协商失败场景

**场景 1：客户端只支持 44.1kHz**
```
Offer: mpeg4-generic/44100/2
↓
filterOfferSDP() 移除所有 AAC codec
↓
Answer: 不包含 AAC (可能降级到 Opus)
```

**场景 2：客户端只提供 AAC Main**
```
Offer: objectType=1 (AAC Main Profile)
↓
filterOfferSDP() 移除
↓
日志: "removing AAC Main Profile (objectType=1)"
```

**场景 3：fmtp 缺失 config**
```
to_stream.go 自动生成默认 config:
  Type: AAC-LC
  SampleRate: 48000
  ChannelCount: 2
```

## 6. 配置指引

最简 `mediamtx.yml` 片段：

```yaml
webrtc: yes

paths:
  aac-test:
    sourceOnDemand: yes
```

- 保证 WebRTC 功能开启
- `paths` 名称与 WebRTC URL（WHEP/WHIP）对应
- 若需常驻信源，可改用 `source: rtsp://...`、`source: rtmp://...` 等

## 7. 测试与验证

### 7.1 单元测试

```bash
# 运行 AAC 相关测试
go test ./internal/protocols/webrtc -run 'TestToStream/aac.*' -v
go test ./internal/protocols/webrtc -run 'TestFromStream/aac.*' -v

# 完整 To/FromStream 回归
go test ./internal/protocols/webrtc -run 'Test(To|From)Stream' -v -timeout 5m
```

当前测试覆盖：
- 48kHz 立体声 AAC-LC
- SDP fmtp 解析和格式转换
- RTP timestamp 正确性

**注意**：HE-AAC 和 HE-AAC v2 的测试已被移除，因为当前版本不支持这些格式。

### 7.2 端到端测试

使用 FFmpeg 推送 AAC 流并通过 WebRTC 播放：

```bash
# 推送 RTSP 流（48kHz AAC）
ffmpeg -re \
  -f lavfi -i testsrc=size=1280x720:rate=30 \
  -f lavfi -i sine=frequency=1000:sample_rate=48000 \
  -c:v libx264 -preset veryfast -tune zerolatency \
  -c:a aac -b:a 128k -ar 48000 -ac 2 \
  -f rtsp rtsp://127.0.0.1:8554/aac-test

# 通过 WHEP 拉取并验证
# 在浏览器中打开：http://127.0.0.1:8889/aac-test
```

### 7.3 烟雾测试脚本

如果项目包含自动化脚本（如 `scripts/WebRTC-iOS-AAC-Decoder-Extension-smoke.sh`）：

```bash
WHEP_URL=http://127.0.0.1:8889/aac-test/whep \
PUBLISH_URL=rtsp://127.0.0.1:8554/aac-test \
bash scripts/WebRTC-iOS-AAC-Decoder-Extension-smoke.sh
```

## 8. 常见问题

### 8.1 浏览器无法播放

- **原因**：并非所有浏览器都支持 WebRTC AAC
  - Safari：支持较好
  - Chrome：需要特定版本或实验性功能
  - Firefox：支持有限
- **解决**：建议使用 Safari 测试，或确认目标浏览器的 AAC 支持情况

### 8.2 非 48kHz 流无法工作

- **原因**：当前版本仅支持 48kHz
- **表现**：服务器返回错误 "only 48kHz AAC is supported, got XXXHz"
- **解决**：
  - 使用 FFmpeg 转码为 48kHz：`-ar 48000`
  - 等待后续版本支持更多采样率

### 8.3 RTP 时间戳不连续

- 确认上游源是否正确设置 AAC 编码参数
- 检查是否存在空 AU（Access Unit）
- MediaMTX 已在编码阶段按 AU 数递增 Timestamp（每 AU = 1024 samples）

### 8.4 音频声道数显示不正确

- 当前版本固定为双声道
- 如果播放器显示单声道，可能是播放器解析问题
- 可通过 ffprobe 验证实际输出：`ffprobe -show_streams dump.aac`

### 8.5 为什么日志显示"removed X incompatible AAC codec(s)"？

- **原因**：客户端 Offer 包含 MediaMTX 不支持的 AAC 配置
- **常见情况**：
  - Safari 可能发送 `objectType=1`（AAC Main Profile）
  - iOS 设备可能包含 44.1kHz 配置
- **是否正常**：这是**正常行为**，说明 SDP 过滤机制正在工作
- **日志示例**：
  ```
  [WARN] removing AAC Main Profile (objectType=1) from offer: PT=96, 48000Hz, 2ch
  [INFO] cleaned offer SDP: removed 1 incompatible AAC codec(s)
  ```

### 8.6 协商成功但音频无声

**可能原因 1：fmtp 参数不匹配**
- 检查 Answer SDP 中的 `config` 参数是否正确
- 确认 `sizelength`, `indexlength`, `indexdeltalength` 是否一致
- MediaMTX 使用 `fixAACFmtp()` 强制修复，通常不会出现此问题

**可能原因 2：上游源问题**
- 验证上游 RTSP/RTMP 流的 AAC 配置
- 使用 ffprobe 检查源流：
  ```bash
  ffprobe -v quiet -show_streams rtsp://source/stream
  # 确认 codec_name=aac, sample_rate=48000
  ```

**可能原因 3：浏览器 codec 不支持**
- 检查浏览器控制台是否有解码错误
- 尝试在 Safari 中测试（AAC 支持最好）

### 8.7 SDP 协商失败，返回 406 Not Acceptable

- **原因**：Offer 中的所有 AAC codec 都被过滤掉了
- **场景**：客户端只支持 44.1kHz 或只提供 AAC Main Profile
- **解决**：
  1. 检查客户端 Offer SDP，确认包含 48kHz AAC-LC
  2. 如果客户端无法发送 48kHz，考虑使用 Opus（WebRTC 默认音频 codec）
  3. 未来版本将支持更多采样率

### 8.8 如何调试 SDP 协商问题？

**步骤 1：启用详细日志**
```yaml
# mediamtx.yml
logLevel: debug
```

**步骤 2：查看 Offer/Answer**
- 使用浏览器 WebRTC 内部工具：
  - Chrome: `chrome://webrtc-internals/`
  - Firefox: `about:webrtc`
- 查找 `setLocalDescription` 和 `setRemoteDescription` 事件

**步骤 3：分析 MediaMTX 日志**
```bash
# 查找过滤相关日志
grep -E "(filterOfferSDP|removing AAC|cleaned offer)" mediamtx.log

# 查找协商错误
grep -E "(CreateFullAnswer|SetRemoteDescription)" mediamtx.log
```

**步骤 4：手动验证 codec 匹配**
- Offer 中的 AAC PT 是否在 Answer 中？
- fmtp 参数是否完全一致？
- clockRate 是否为 48000？

## 9. 设计决策

### 9.1 为什么选择简化实现？

1. **快速打通链路**：固定配置避免复杂的动态协商，优先确保基本功能可用
2. **降低复杂度**：移除了约 500 行动态 codec 注册代码，代码更易维护
3. **聚焦常见场景**：48kHz 是最常见的 WebRTC 音频采样率
4. **便于调试**：固定配置使问题排查更简单

### 9.2 为什么移除 HE-AAC 支持？

- HE-AAC 涉及 SBR（Spectral Band Replication）扩展，需要处理双倍采样率
- HE-AAC v2 额外包含 PS（Parametric Stereo），声道处理更复杂
- 浏览器对 HE-AAC 的 WebRTC 支持不统一
- 先实现基础 AAC-LC，后续根据需求再扩展

### 9.3 为什么固定 PayloadType 123？

- 避免与常见 codec 冲突（96-122 通常用于动态分配）
- 简化实现，无需动态分配逻辑
- 保持与标准 WebRTC codec 的兼容性

### 9.4 为什么需要 SDP 过滤机制？

**核心问题**：WebRTC 客户端（特别是 Safari/iOS）会在 Offer 中列出所有支持的 codec 变体，包括 MediaMTX 不支持的配置。

**不过滤的后果**：
1. **协商到错误 codec**：SDP 协商可能选中 AAC Main Profile 或 44.1kHz 配置
2. **音频播放失败**：客户端发送的音频 MediaMTX 无法解码
3. **时间戳错误**：时钟率不匹配导致音视频不同步
4. **难以调试**：浏览器控制台只显示模糊错误，不明确指出 codec 问题

**解决方案**：
- **主动过滤**：在协商前移除不支持的 codec，强制客户端使用兼容配置
- **早期拒绝**：如果所有 AAC codec 都不兼容，返回 406 错误，避免建立无效连接
- **明确日志**：记录具体移除了哪些 codec 及原因，便于排查

**实际案例**：
Safari 15.x 在 Offer 中同时包含：
- PT 96: `mpeg4-generic/48000/2`, `objectType=1` (AAC Main)
- PT 97: `mpeg4-generic/48000/2`, `objectType=2` (AAC-LC)
- PT 98: `mpeg4-generic/44100/2`, `objectType=2`

如果不过滤，SDP 协商可能优先选择 PT 96（AAC Main），导致音频无法播放。通过 `filterOfferSDP()` 移除 PT 96 和 PT 98，强制使用 PT 97（AAC-LC 48kHz）。

### 9.5 为什么需要 Answer fmtp 修复？

**问题**：pion/webrtc 库生成的 Answer SDP 中，fmtp 参数可能：
- 缺少某些可选参数（如 `profile-level-id`）
- 参数顺序与客户端期望不同
- `config` 的十六进制编码格式略有差异

**影响**：
- 某些严格的 WebRTC 客户端（如旧版 Safari）可能拒绝不完整的 fmtp
- 参数顺序不同可能导致指纹匹配失败
- 即使协商成功，解码器初始化可能失败

**解决方案**：
- `fixAACFmtp()` 强制替换为经过验证的固定 fmtp 字符串
- 与静态注册的 codec 保持完全一致
- 确保跨浏览器兼容性

### 9.6 为什么不支持动态协商？

**动态协商的复杂性**：
1. **Offer 解析**：需要提取所有 AAC codec 的参数（采样率、声道数、ObjectType、config）
2. **动态注册**：为每个配置调用 `MediaEngine.RegisterCodec()`，管理 PT 分配
3. **格式转换**：根据不同 config 初始化不同的编解码器
4. **时间戳处理**：不同采样率需要不同的时钟计算
5. **测试覆盖**：需要测试各种组合（3种采样率 × 3种ObjectType × 2种声道）

**简化方案的优势**：
- **代码量**：静态注册 ~50 行，动态协商需要 ~500 行
- **维护性**：固定配置易于理解和调试
- **性能**：无需运行时解析和动态注册
- **稳定性**：减少边界情况和潜在 bug

**后续扩展路径**：
- 如需支持更多采样率，增加静态 codec 定义即可（每个采样率 ~10 行代码）
- 不需要重新引入动态协商的复杂性

## 10. 后续工作

### 10.1 扩展采样率支持

未来可添加其他常见采样率：
- 44.1 kHz（音乐场景）
- 16 kHz（语音场景）
- 24 kHz、32 kHz（中等质量）

实现步骤：
1. 在 `incoming_track.go` 中为每个采样率添加 codec 定义
2. 修改 `to_stream.go` 移除 48kHz 限制
3. 更新 `from_stream.go` 使用实际采样率
4. 添加对应测试用例

### 10.2 HE-AAC 支持

如需支持 HE-AAC：
1. 实现 SBR 扩展的采样率计算（48kHz → 24kHz core）
2. 处理 `AudioSpecificConfig` 中的 SBR 标志
3. 调整 RTP 时钟率匹配
4. 验证浏览器兼容性

### 10.3 动态 Codec 协商

如果需要支持客户端提供的任意 AAC 配置：
1. 恢复 Offer 解析逻辑
2. 实现动态 `MediaEngine.RegisterCodec()`
3. 处理不同 `config`（AudioSpecificConfig）
4. 测试各种边界情况

## 11. 关键代码位置

| 功能 | 文件路径 | 行号 | 说明 |
|------|---------|------|------|
| **Codec 注册** | | | |
| 静态 AAC Codec 注册 | `internal/protocols/webrtc/incoming_track.go` | 237-245 | 固定 48kHz AAC-LC 定义，PT=123 |
| **SDP 协商过滤** | | | |
| Offer SDP 过滤 | `internal/protocols/webrtc/peer_connection.go` | 652-783 | 移除 objectType=1 和非 48kHz codec |
| Answer fmtp 修复 | `internal/protocols/webrtc/peer_connection.go` | 558-587 | 强制替换为固定 fmtp 字符串 |
| 协商入口（过滤调用） | `internal/protocols/webrtc/peer_connection.go` | 697-700 | CreateFullAnswer 中调用 filterOfferSDP |
| 会话流程调整 | `internal/servers/webrtc/session.go` | 157-166, 303-312 | Offer 解析前置到 PC 创建之前 |
| **流转换** | | | |
| 入站 AAC 解析 | `internal/protocols/webrtc/to_stream.go` | 137-188 | 解析 fmtp，验证 48kHz，创建 format |
| 入站采样率验证 | `internal/protocols/webrtc/to_stream.go` | 160-163 | 拒绝非 48kHz 流 |
| 出站 AAC 编码 | `internal/protocols/webrtc/from_stream.go` | 656-730 | RTP 封装和时间戳处理 |
| 时间戳推进 | `internal/protocols/webrtc/from_stream.go` | 726-730 | timestamp += AU_count * 1024 |
| **工具函数** | | | |
| fmtp 生成 | `internal/protocols/webrtc/aac_fmtp.go` | 18-59 | buildMPEG4AudioFMTPLine |
| fmtp 解析 | `internal/protocols/webrtc/aac_fmtp.go` | 71-142 | ParseMPEG4AudioFMTP |
| **测试** | | | |
| ToStream 测试 | `internal/protocols/webrtc/to_stream_test.go` | 335-365 | AAC 48kHz 测试用例 |
| FromStream 测试 | `internal/protocols/webrtc/from_stream_test.go` | - | AAC 48kHz 测试用例 |

### 代码修改摘要

**新增文件**：
- `internal/protocols/webrtc/aac_fmtp.go` (143 行) - fmtp 参数处理工具

**主要修改**：
- `incoming_track.go`: +12 行（AAC codec 定义）
- `peer_connection.go`: +180 行（SDP 过滤和修复逻辑）
- `from_stream.go`: +80 行（AAC 编码和 RTP 封装）
- `to_stream.go`: +55 行（AAC 解析和验证）
- `session.go`: ~20 行（流程调整）
- 测试文件: +30 行（AAC 测试用例）

**总计新增代码**: ~380 行（不含注释和空行）

---

如需调整实现策略或遇到兼容性问题，建议先查看 `internal/protocols/webrtc` 下的最新代码，并使用上述测试流程复现后再定位。
