# WebRTC AAC Patches

本目录包含为 WebRTC 添加 AAC 解码器支持所需的所有修改。

## Patch 文件

### 修改现有文件的 Patches

1. **0001-add-aac-to-build.patch**
   - 修改 `api/audio_codecs/BUILD.gn`
   - 添加 AAC 模块到构建系统

2. **0002-register-aac-decoder.patch**
   - 修改 `api/audio_codecs/builtin_audio_decoder_factory.cc`
   - 在默认音频解码器工厂中注册 AAC 解码器

3. **0003-add-aac-api.patch**
   - 新增 AAC API 头文件示例

### 源文件归档

- **aac-source-files.tar.gz**
  - 包含所有新增的 AAC 源文件
  - API 层：`api/audio_codecs/aac/`
  - 实现层：`modules/audio_coding/codecs/aac/`

## 应用 Patches

### 自动应用（推荐）

```bash
cd /Users/professional/Dev/WebRTC-AAC-Kit
./scripts/apply_patches.sh
```

### 手动应用

```bash
cd src

# 应用修改补丁
git apply ../patches/0001-add-aac-to-build.patch
git apply ../patches/0002-register-aac-decoder.patch

# 解压源文件
cd ..
tar xzf patches/aac-source-files.tar.gz -C src/
```

## 验证

应用 patches 后，验证以下文件存在：

```
src/api/audio_codecs/aac/
├── BUILD.gn
├── audio_decoder_aac.h
└── audio_decoder_aac.cc

src/modules/audio_coding/codecs/aac/
├── BUILD.gn
├── aac_format.h
├── format/
├── decoder/
└── ios/
```

## 版本兼容性

这些 patches 基于 WebRTC **M142** (2025-10-11)。

对于不同的 WebRTC 版本，可能需要手动调整 patches。
