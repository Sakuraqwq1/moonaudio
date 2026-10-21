# `moonaudio` 项目申报书

**基本信息**

- 项目名称：moonaudio — 纯 MoonBit 音频解码与 DSP 工具库
- 参赛者：Sakuraqwq1
- GitHub 仓库：https://github.com/Sakuraqwq1/moonaudio
- 项目方向：MoonBit 原生音频基础库 / 多媒体基础设施
- 是否移植项目：否（原创实现，规格参照公开标准文本，见下）

## 项目简介

MoonBit 生态缺少一个不依赖任何宿主平台、可以直接跑在 wasm 与 native 上的音频基础库：现有音频包多为浏览器或 C 库的绑定，无法在纯 MoonBit 环境里解析文件、做频谱分析或重采样。`moonaudio` 用纯 MoonBit 实现「读文件 → 解码为归一化浮点采样 → DSP 分析 → 重新编码」的完整链路，面向命令行工具、浏览器/插件的音频处理、以及需要确定性音频测试数据生成的项目。

## 现有基础

仓库当前已实现并测试通过（`moon test` 全部通过）：

- `src/audio`：`AudioBuffer`（交织双精度采样）、六种采样格式、量化/反量化、dBFS、G.711 μ-law/A-law、带边界检查的大小端读取器。
- `src/wav`：RIFF/WAVE 解码与编码，覆盖 PCM 8/16/24/32、IEEE float 32/64、`WAVE_FORMAT_EXTENSIBLE`、RIFX 大端、μ-law/A-law 解码、`LIST/INFO` 元数据、多 `data` 块。
- `src/flac`：原生 FLAC 解码器，包含 MSB 优先位读取器、CRC-8/CRC-16 校验、元数据块、帧头、constant/verbatim/fixed/LPC 子帧、Rice 分区与 escape、wasted bits、左/右/中-边声道去相关。
- 门面 API：`sniff` / `decode` / `decode_detected` / `describe`。

## 本次计划新增

1. AIFF/AIFC 解码与编码（含 80-bit 扩展浮点采样率）；Sun `.au` 解码与编码（含 μ-law/A-law）。
2. `src/dsp`：窗函数（Hann/Hamming/Blackman/Blackman-Harris/Kaiser）、基-2 FFT 与实序列 FFT、幅度谱、频谱图（CSV/SVG 输出）、RBJ biquad 滤波器、统计分析、静音裁剪、淡入淡出、混音、测试音与确定性白噪声。
3. `src/resample`：线性、Catmull-Rom 三次、窗函数 sinc 三种采样率转换。
4. `cmd/moonaudio`：`info` / `decode` / `convert` / `stats` / `spectrogram` / `tone` 子命令，输出 Markdown/JSON 报告。
5. `examples/`：至少三个可直接 `moon run` 的最小示例（读文件统计、生成正弦并做 FFT 峰值检测、重采样往返）。

## 技术路线

- 全部解码器共享同一套错误类型（`Truncated`/`Unsupported`/`Invalid`/`OutOfRange`），所有越界读取显式报错而不 trap，因此畸形文件不会导致进程崩溃。
- 采样统一归一化为 `[-1.0, 1.0]` 的 `Double`，整数位深通过 `double` 精确表示，DSP 阶段再做量化，避免中间精度损失。
- FLAC 走完整的位流解析路径，并在每帧校验 CRC-8/CRC-16；测试用独立实现的位流写入器合成符合规范的流，覆盖每一种子帧与声道组合。
- 无第三方依赖，只依赖 `moonbitlang/core`，保证 `moon check` / `moon test` 在离线环境可复现。

## 预期交付

- 4 个容器（WAV/AIFF/AU/FLAC）+ DSP + 重采样 + CLI + 示例，有效 MoonBit 代码约 5k 行。
- 每个包都有 `_wbtest.mbt` 测试，覆盖正常路径与错误路径；CI 在 Linux/macOS/Windows 上跑 `moon check --deny-warn`、`moon test --deny-warn`、`moon fmt --check` 与接口一致性检查。
- README（安装、快速开始、格式支持矩阵、API 示例）、`docs/architecture.md`、`docs/format-support.md`、`CHANGELOG.md`。

## 参考与许可证

- 实现依据公开标准文本：RIFF/WAVE（Microsoft）、AIFF/AIFC（Apple）、Sun `.au`、FLAC 格式规范（Xiph.Org，RFC 9639）。
- 未复制任何第三方源码；测试向量由仓库内独立实现的位流写入器生成。
- 本项目采用 Apache License 2.0。
