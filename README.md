# moonaudio

[![CI](https://github.com/Sakuraqwq1/moonaudio/actions/workflows/ci.yml/badge.svg)](https://github.com/Sakuraqwq1/moonaudio/actions/workflows/ci.yml)

纯 MoonBit 实现的音频解码与 DSP 工具库：不依赖任何宿主平台、不依赖任何第三方包，在 wasm、wasm-gc 与 native 上跑同一份代码。

```moonbit
let bytes = read_your_file()               // 由宿主提供 Bytes（见「关于文件 IO」）
let audio  = @moonaudio.decode(bytes)      // 自动识别 WAV / AIFF / AU / FLAC
println(audio.sample_rate)                 // 44100
println(audio.frames())                    // 采样帧数
println(audio.peak_dbfs())                 // 峰值电平
```

- 输入：RIFF/WAVE（含 RIFX、`WAVE_FORMAT_EXTENSIBLE`、μ-law/A-law）、AIFF/AIFC（含 80-bit 扩展浮点采样率）、Sun `.au`、原生 FLAC（含 LPC / Rice / 中-边声道去相关 / CRC 校验）。
- 处理：`AudioBuffer`（交织 `Double`，归一化到 `[-1, 1]`）、采样格式转换、G.711、dBFS、重采样（线性 / 三次 / 窗函数 sinc）、FFT 与频谱图、RBJ biquad 滤波器、统计与静音裁剪。
- 输出：WAV / AIFF / AU 编码，以及频谱图 CSV/SVG、Markdown 报告。
- 安全：每一次多字节读取都做边界检查，畸形文件只报错不崩溃；FLAC 逐帧校验 CRC-8/CRC-16。

## 特性

| 能力 | 说明 |
| --- | --- |
| 四个容器解码 | WAV、AIFF/AIFC、Sun `.au`、FLAC |
| 三个容器编码 | WAV、AIFF/AIFC、`.au`（FLAC 目前仅解码） |
| 采样格式 | u8 / s16 / s24 / s32 / f32 / f64 |
| DSP | 窗函数、基-2 FFT 与实 FFT、幅度谱、频谱图、biquad 滤波、统计、淡入淡出、混音、测试音、确定性白噪声 |
| 重采样 | 线性、Catmull-Rom 三次、窗函数 sinc（带抗混叠截止） |
| 依赖 | 仅 `moonbitlang/core`，无外部包 |
| 测试 | 138 个单元测试，覆盖正常路径与错误路径 |
| CI | Linux / macOS / Windows 三平台 `check`、`test`、`fmt`、接口一致性检查，另有真实 FLAC 文件的一致性任务 |

格式支持细节与明确不支持项见 [`docs/format-support.md`](docs/format-support.md)，架构说明见 [`docs/architecture.md`](docs/architecture.md)。

### 与生态中现有音频包的区别

选题前在 mooncakes.io 上检索过 `audio` / `wav` / `flac` / `ogg` 等关键词，现有包大致分三类，`moonaudio` 的定位与它们都不重合：

| 现有包 | 它们的定位 | `moonaudio` 的不同之处 |
| --- | --- | --- |
| `mizchi/audio`、`Milky2018/moon_rodio`、`moon_cpal` | 浏览器 / C 音频库的**绑定**，负责播放与设备 IO | 纯 MoonBit、零绑定，只做「字节 ↔ 采样 ↔ 分析」的纯函数处理，可离线、可在 wasm-gc 里跑 |
| `bw448/moon-wav`、`Ridge-Lab/moonwavkit`、`Xcsa-ee/moonflac` 等 | 单一格式的最小解析器 | 四个容器 + 统一 `AudioBuffer` + 编码 + 重采样 + DSP + CLI，格式之间可以互相喂给同一条分析流水线 |
| 各家的 DSP / FFT 小包 | 单点算法 | 与容器解码共用同一套归一化采样与错误模型，`analyse`/`spectrogram`/`Biquad` 直接吃解码结果 |

也就是说，本项目不是一个格式解析器的又一个实现，而是把「读文件 → 归一化 → 分析/处理 → 再编码」这条链路做完整，并保持无依赖、可离线复现。

## 快速开始

### 安装

```bash
# 安装 MoonBit 工具链（已安装可跳过）
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash   # macOS / Linux
# Windows: irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
```

把 `moonaudio` 加进项目（发布到 mooncakes.io 后）：

```bash
moon add Sakuraqwq1/moonaudio
```

本地开发时也可以直接克隆仓库：

```bash
git clone https://github.com/Sakuraqwq1/moonaudio
cd moonaudio
moon check
moon test
```

### 解码

```moonbit
let audio = @moonaudio.decode(bytes)
println("\{audio.sample_rate} Hz, \{audio.channels} ch, \{audio.frames()} frames")
println("peak: \{audio.peak_dbfs()} dBFS, rms: \{audio.rms_dbfs()} dBFS")
```

### 编码

```moonbit
// 16-bit PCM WAV
let wav = @wav.encode(audio)
// 24-bit AIFF
let aiff = @aiff.encode(audio, format=@audio.I24)
// 32-bit float .au
let au = @au.encode(audio, format=@audio.F32)
```

### 处理

```moonbit
let loud = audio.copy()
loud.normalize(target=0.9)                  // 峰值归一到 0.9
let mono = loud.remix(1)                    // 立体声下混
let resampled = @resample.resample(mono, 48000)
let filtered = @dsp.Biquad::new(
  @dsp.LowPass, 48000, 4000.0,
).apply_buffer(resampled)
```

### 分析

```moonbit
let stats = @dsp.analyse(audio)
println(stats.to_lines())                   // key=value 列表，顺序稳定

let spec = @dsp.spectrogram(audio, fft_size=1024, hop=256)
println(spec.to_csv())
println(spec.to_svg())                      // 直接可放进网页的灰度频谱图
```

### 容器探测

```moonbit
match @moonaudio.sniff(bytes) {
  Some(container) => println(container.to_name())   // "wav" | "aiff" | "au" | "flac"
  None => println("unrecognised")
}
```

## 命令行 demo

MoonBit 核心库没有可移植的文件系统 API，因此仓库自带的 CLI 通过 **base64 参数或环境变量**传递二进制数据，方便在任意宿主上验证整条链路：

```bash
# 端到端自检：生成 → 编码 → 解码 → 分析 → 重采样，输出 Markdown 报告
moon run cmd/main -- demo

# 生成 440 Hz 正弦波 WAV（base64）
moon run cmd/main -- tone --freq 440 --ms 500 > tone.b64

# 小文件可以直接当参数传
moon run cmd/main -- info "$(cat tone.b64)"
moon run cmd/main -- stats "$(cat tone.b64)"

# 大一点的用环境变量，绕开命令行长度限制
export AUDIO_B64="$(cat tone.b64)"
moon run cmd/main -- convert @AUDIO_B64 --rate 48000 --format s24 --container aiff
```

`demo` 的真实输出：

```text
# moonaudio demo

- module version: `0.3.0`
- generated: 1.000 s of 440 Hz at 44.1 kHz, peak 0.800
- encoded: 88244 byte WAV, sniffed as wav
- header: 44100 Hz, 1 ch, 16 bit (s16), pcm, 44100 frames
- roundtrip: 44100 frames, peak -1.938 dBFS, rms -4.949 dBFS, crest 1.414
- AIFF 24-bit: 132354 bytes, decoded peak 0.800
- AU float64: 352824 bytes, decoded peak 0.800
- resampled 44.1 kHz -> 48 kHz: 48000 frames, peak 0.800
- FFT peak: 441.431 Hz for the 440 Hz tone (10.767 Hz per bin)
- spectrogram: 170 frames x 513 bins, bin width 43.066 Hz, frame 0 peak 430.664 Hz
- high pass 200 Hz: peak 0.824, rms 0.554
```

真实项目里文件读取由宿主负责（浏览器用 `File`/`fetch`，native 用 `moonbitlang/x/fs` 或自己的 FFI），库本身只接收 `Bytes`。

## 示例

两个示例都是可以直接 `moon run` 的独立包：

```bash
moon run examples/basic    # 20 行：生成正弦 → WAV 编码 → 门面解码 → 打印电平
moon run examples/tour     # 分节导览：合成、分析、滤波、重采样、容器往返
```

`examples/tour` 的实际输出（节选）：

```text
== synthesis ==
  tone 440 Hz : 22050 frames, peak 0.4
  mixed       : peak 0.666, rms 0.354
  deterministic: true

== analysis ==
  fft peak at bin 128: 1000 Hz (input 1000 Hz)
  spectrogram: 31 frames x 257 bins, 15.625 Hz per bin
  frame 0 peak: 1000 Hz

== resampling ==
  ratio 44100:48000 reduces to 147:160
  expected frames: 4800
  actual frames  : 4800

== containers ==
  wav: 4454 bytes — 22050 Hz, 1 ch, 16 bit (s16), pcm, 2205 frames
  aiff: 6670 bytes — 22050 Hz, 1 ch, 24 bit (s24), AIFF NONE, 2205 frames
```

## 包结构

| 包 | 职责 |
| --- | --- |
| `Sakuraqwq1/moonaudio` | 门面：`sniff` / `decode` / `decode_detected` / `describe` / `version` |
| `src/audio` | `AudioBuffer`、采样格式、量化、dBFS、G.711、字节读取器 |
| `src/wav` | RIFF/WAVE 解码与编码 |
| `src/aiff` | AIFF/AIFC 解码与编码 |
| `src/au` | Sun `.au` 解码与编码 |
| `src/flac` | FLAC 解码（位流、帧、子帧、Rice、CRC） |
| `src/dsp` | 窗函数、FFT、频谱、滤波器、统计 |
| `src/resample` | 采样率转换 |

## 测试

```bash
moon check --deny-warn
moon test  --deny-warn
moon fmt --check
moon info          # 接口若有变化会更新 pkg.generated.mbti
```

测试覆盖：

- **audio**：缓冲区几何、峰值/RMS、声道转换、切片拼接、量化与反量化、float32 位模式、G.711 往返、字节读取边界。
- **wav**：8/16/24/32-bit 与 float 往返、`LIST/INFO` 元数据、`WAVE_FORMAT_EXTENSIBLE`、RIFX 大端、奇数长度 padding、错误路径。
- **aiff**：AIFF/AIFC、`sowt` 小端、float、80-bit 采样率精确值、元数据、SSND 偏移、畸形输入。
- **au**：8/16/24/32-bit、float、μ-law/A-law、annotation、截断与不支持编码。
- **flac**：用仓库内**独立实现的位流写入器**合成符合规范的数据流，覆盖 constant/verbatim/fixed 0-4/LPC、Rice 分区与 escape、wasted bits、左/右/中-边声道、多帧、12/16/20/24-bit、变长块、超长帧号、CRC 校验失败与截断。
- **dsp**：FFT 与朴素 DFT 对照、逆变换、Parseval、正弦峰值 bin、窗函数性质、频谱图尺寸与峰值频率、滤波器通带/阻带、统计量、淡入淡出、混音。
- **resample**：三种核的音高与幅度、往返长度、比例约简、非法采样率。

> 说明：FLAC 测试向量由仓库内的合成器生成，未导入官方 `flac-test-files` 数据（它们体积较大且无法在离线 CI 中获取）。解码器的位流路径、Rice 分区、escape 与 CRC 均被覆盖；后续可用官方测试集做交叉验证，见路线图。

## 设计要点

- **单一采样表示**：所有容器解码成同一种 `AudioBuffer`（交织 `Double`，范围 `[-1, 1]`），因此任意容器都能无缝进入任意 DSP 阶段。
- **显式错误**：`AudioError` 只有四种（`Truncated` / `Unsupported` / `Invalid` / `OutOfRange`），调用方可以按语义决定重试、跳过还是提示用户。
- **无 panic 解码**：所有越界读取都返回 `Truncated`，不会 trap；FLAC 每帧校验 CRC，损坏的帧会被明确拒绝。
- **确定性**：FFT、重采样、噪声生成都是输入的纯函数，白噪声使用显式种子的 xorshift，测试可复现。
- **零依赖**：只依赖 `moonbitlang/core`，可以离线构建，也便于在受限环境（CI、沙箱、wasm 宿主）里使用。

## 路线图

- [ ] FLAC 编码器（含子帧选择与 Rice 参数搜索）
- [ ] 导入官方 `flac-test-files` 子集做一致性交叉验证
- [ ] Ogg 容器与 Vorbis/Opus 解码
- [ ] 流式 API（边读边解码，避免整文件驻留内存）
- [ ] 更多滤波器类型与多通道声像处理

## 许可证与参考

本项目采用 [Apache License 2.0](LICENSE)。

实现依据公开规范文本，未复制任何第三方源码：

- RIFF/WAVE：Microsoft RIFF 规范与 `WAVE_FORMAT_EXTENSIBLE` 说明
- AIFF/AIFC：Apple AIFF-C 规范（80-bit 扩展浮点采样率）
- Sun `.au`：Sun/NeXT 音频文件格式说明
- FLAC：Xiph.Org FLAC 格式规范 / RFC 9639

测试向量由仓库内的位流写入器生成（见 `src/flac/flac_wbtest.mbt`）。

## English summary

`moonaudio` is a dependency-free audio toolkit written in pure MoonBit. It decodes
WAV (RIFF/RIFX/extensible/mu-law/A-law), AIFF/AIFC (including 80-bit extended
sample rates), Sun `.au` and native FLAC (LPC, Rice partitions, stereo
decorrelation, per-frame CRC) into a single normalised `AudioBuffer`, then offers
resampling, FFT/spectrograms, biquad filters, statistics and WAV/AIFF/AU
encoding. Every multi-byte read is bounds checked, so malformed input raises a
typed error instead of trapping. Apache-2.0.
