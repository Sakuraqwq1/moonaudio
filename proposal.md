# `moonaudio` 项目申报书

**基本信息**

- 项目名称：moonaudio — 纯 MoonBit 音频解码与 DSP 工具库
- 参赛者：Sakuraqwq1
- 联系方式：见报名问卷
- GitHub 仓库：<https://github.com/Sakuraqwq1/moonaudio>（提交记录 35 个，均为本轮开发）
- 项目方向：MoonBit 原生多媒体基础库 / 音频处理基础设施
- 是否移植：否。原创实现，仅参照公开的格式规范文本

## 项目价值与生态定位

MoonBit 现在同时面向 wasm 与 native，但音频这条链路是断的。生态里的音频包分两类：一类是浏览器或 C 库的**绑定**（`mizchi/audio`、`Milky2018/moon_rodio`、`moon_cpal`），只能播放、必须带宿主运行时；另一类是**单格式解析器**（`bw448/moon-wav`、`Ridge-Lab/moonwavkit`、`Xcsa-ee/moonflac`），各自定义采样表示，解出来的数据接不上任何分析代码。缺的是中间那层：把字节变成统一的归一化浮点采样，让人能直接做分析、变换和再编码。

因此本项目不是又一个 WAV 解析器的竞品，而是把「读文件 → 归一化 → 分析与处理 → 再编码」做成一条闭合的链，且零依赖、可离线、wasm-gc 与 native 同源。与上述包的重合仅限 WAV/FLAC 解码这一小段——而这段必须自持，否则链路不闭合，也无法保证错误语义和 CRC 校验的一致。差异化落在四容器 + 统一 `AudioBuffer` + 编码 + 重采样 + DSP + CLI 的完整度上。

## 预期使用场景

1. **离线音频批处理。** 素材目录里混着 WAV / AIFF / AU / FLAC，需要统一成 48 kHz、24-bit WAV，并出一份峰值与 RMS 报告。用 CLI 逐条转换，不引入 FFmpeg、不启动浏览器，可放进 CI，报告是 Markdown，直接贴进构建日志。
2. **浏览器内做音频分析（wasm-gc）。** 用户拖入一个文件，前端把 `Bytes` 交给 `decode`，再用 `spectrogram(...).to_svg()` 内联成灰度频谱图。整个过程不依赖 WebAudio、不需要 JS sidecar，适合教学演示、听力训练、插件里的波形速览。
3. **确定性测试数据与回归基线。** 用内置正弦合成器与显式种子的 xorshift 白噪声生成固定采样，配合 FFT 峰值、biquad 通带响应做断言，为播放器、编解码器或 DSP 库提供 golden test 输入；相比随机波形，这种输入可复现、可解释、频带可控。

## 核心功能范围

已交付（细节见 README 与 `docs/format-support.md`）：

- **解码**：WAV（RIFF/RIFX、`WAVE_FORMAT_EXTENSIBLE`、μ-law/A-law）、AIFF/AIFC（含 80-bit 扩展浮点采样率）、Sun `.au`、FLAC（LPC、Rice 分区、中-边去相关、逐帧 CRC-8/CRC-16）；
- **统一表示**：`AudioBuffer`（交织 `Double`，归一化到 `[-1, 1]`）、六种采样格式互转、dBFS；
- **编码**：WAV / AIFF / AU；
- **DSP**：窗函数、基-2 FFT 与实 FFT、幅度谱、频谱图（CSV/SVG）、RBJ biquad 七种滤波、统计、静音裁剪、淡入淡出、混音、测试音；
- **重采样**：线性、Catmull-Rom、窗函数 sinc；
- **CLI 与示例**：`demo` / `info` / `stats` / `spectrum` / `spectrogram` / `convert` / `tone`，输出 Markdown 报告；两个可直接 `moon run` 的示例（`examples/basic`、`examples/tour`）。

**明确不做**：播放与设备 IO、Ogg/Vorbis/Opus、文件系统读取（由宿主传入 `Bytes`）、多线程与 SIMD 加速。

## 实现路径

- 所有解码器共用一套错误模型（`Truncated`/`Unsupported`/`Invalid`/`OutOfRange`），越界读取显式返回错误而不 trap，畸形文件只报错、不崩进程；
- 采样统一归一化为 `Double` 再进 DSP，整数位深无损表示，避免中间精度损失；
- FLAC 走完整位流路径并逐帧验 CRC；测试用仓库内独立实现的位流写入器合成符合规范的流，覆盖每种帧、子帧与声道组合；
- 零第三方依赖，只依赖 `moonbitlang/core`，保证离线可构建、结果可复现。

## 交付现状

- **规模**：44 个 `.mbt`，10,307 行（实现 6,608、测试 3,699）；
- **测试**：`moon check --deny-warn` 零告警，`moon test --deny-warn` 138/138 通过；
- **CI**：Linux / macOS / Windows 三平台 check、test、fmt、接口一致性，加 wasm-gc 与 native 构建和 CLI 冒烟；
- **文档**：README、`docs/architecture.md`、`docs/format-support.md`、`docs/flac.md`、`CHANGELOG.md`、`CONTRIBUTING.md`；
- **合规**：Apache-2.0；未复制第三方源码，测试向量由仓库内位流写入器生成；AI 参与代码与文档起草，设计取舍、测试与验收由本人负责。

## 路线图

FLAC 编码器、官方 `flac-test-files` 交叉验证、流式解码 API。
