# moonaudio 自查报告

按 `osc2026-guide` skill 的 Review Mode 执行。证据均为本机实际运行结果（2026-10-21，Windows）。

## 总体判断

**项目本身达到可提交、可通过验收的技术条件，但两件事必须在提交前由你完成：发布到 mooncakes.io、推送公开仓库并让 CI 真正跑一次。** 这两项属于「材料/账号」而不是「代码」，我无法代办。

分级结论：

| 维度 | 状态 | 依据 |
| --- | --- | --- |
| 有效性（是合法 MoonBit 项目） | ✅ | `moon check --deny-warn` 通过，9 个包全部参与编译 |
| 构建/测试 | ✅ | `moon test --deny-warn`：130/130 通过；`--target wasm-gc` 130/130；`moon build --target wasm-gc` 与 `--target native` 均成功 |
| 工程结构 | ✅ | 7 个功能包 + 门面 + CLI + 2 个示例，`moon.mod` 元数据完整 |
| 文档 | ✅ | README（含与生态现有包的区别、格式矩阵、API 示例、CLI 实测输出）、`docs/architecture.md`、`docs/format-support.md`、`docs/flac.md`、`docs/publishing.md`、`CONTRIBUTING.md`、`CHANGELOG.md` |
| 可运行示例 | ✅ | `moon run examples/basic`、`moon run examples/tour`、`moon run cmd/main -- demo` 均已实跑 |
| 测试覆盖 | ✅（有一处已知缺口） | 8 个测试文件、3,834 行；FLAC 用合成流覆盖所有子帧类型，但**未用真实 .flac 文件交叉验证** |
| 开源合规 | ✅ | 根目录 Apache-2.0；未复制第三方源码；README/申报书列明参考的标准文本 |
| 提交历史 | ✅（时间戳集中） | 31 个提交，全部为本次开发，消息可读、粒度合理 |
| CI | ⚠️ 已配置未执行 | `.github/workflows/ci.yml` 已写，但仓库还没有 remote，Actions 从未运行 |
| mooncakes.io 发布 | ❌ 未发布 | 需要 `moon login`（浏览器 OAuth），我无法代做 |

代码规模：MoonBit 源码 **11,394 行**（实现 7,560 + 测试 3,834），有效实现规模落在章程给的 4~10k 参考区间内偏上。

## 提交前需要处理的问题

1. **发布到 mooncakes.io（硬性验收项）。** 活动说明的验收要求里有「按要求发布至 mooncakes.io」。执行：
   ```bash
   cd moonaudio
   moon login          # 浏览器里用 GitHub 授权
   moon publish        # 发布 0.3.0
   ```
   如果 mooncakes 账号名不是 `Sakuraqwq1`，需要同时改 `moon.mod` 的 `name` 和各 `moon.pkg` 里本地包的导入路径。详见 `docs/publishing.md`。

2. **推送公开仓库并跑绿 CI（硬性验收项）。** 当前仓库没有任何 remote：
   ```bash
   git remote add github https://github.com/Sakuraqwq1/moonaudio
   git push github main
   ```
   推送后到 Actions 页面确认 `CI` 工作流三条 job 全绿。特别留意 `moon fmt --check`：本机无法执行它（该命令会从 mooncakes 拉取 `moonbitlang/parser/cmd/moonfmt`，本机 HTTPS 不通），我是用工具链自带的 `moonfmt -w` 格式化的，**格式器版本差异可能导致 CI 的格式检查失败**。若 CI 报格式问题，在本地有网环境跑一次 `moon fmt` 再提交即可。

3. **FLAC 只用合成流验证过。** 本机无法访问 `raw.githubusercontent.com`，官方 `flac-test-files` 下不下来，所以解码器是用仓库内独立实现的位流写入器构造的规范流来测的（覆盖 constant/verbatim/fixed 0-4/LPC、Rice 分区与 escape、wasted bits、左/右/中-边、12/16/20/24-bit、变长块、超长帧号、CRC 失败、截断）。位流路径、CRC、分区逻辑都被覆盖，但**真实编码器的差异（例如极端 LPC 阶数、非常规分区、8 声道 192kHz）没有被真文件验证**。建议在有网环境补一次交叉验证（见「建议改进」第 2 条）。

4. **申报书篇幅。** `proposal.md` 共 56 行。黑客松要求「一页左右的 Markdown」——一页 Markdown 通常指 40~60 行，够用；但如果你最终参加的是 OSC2026 主赛（其规则要求 Markdown 申报书 ≤30 行），需要压缩到 30 行内或转成 1 页 PDF。

## 需要进一步确认的问题

1. **你要投的是哪一轮？** 按 skill 内置的两份规则文件，OSC2026 主赛的申报截止是 2026-07-10、验收 7/11–7/17；8 月黑客松报名截止 2026-08-24。今天是 2026-10-21，两轮窗口都已关闭。如果赛事方开了新一轮或有延期，请告诉我具体规则，我再调材料（比如申报书格式、是否需要 Gitlink、提交记录日期要求）。
2. **mooncakes 账号名是否为 `Sakuraqwq1`？** 若不是，包命名空间需要一起改。
3. **仓库最终放在个人账号还是组织下？** 章程允许 `moonbit-community/...` 这类组织仓库，但 `moon.mod` 的命名空间与仓库 owner 不必一致（skill 明确允许）。
4. **是否需要我一并准备 Gitlink 侧材料？** OSC2026 要 GitHub + Gitlink 双仓，黑客松只要 GitHub。

## 建议改进

1. **把 CLI 抽成可测函数。** 现在 `cmd/main/main.mbt` 的参数解析与命令分派没有单元测试（`main` 无法直接测）。把 `parse_command` 提出来返回一个 `Command` 枚举，就能用表驱动测试覆盖全部子命令与错误分支，成本约半小时。
2. **CI 增加真实 FLAC 一致性 job。** 在 GitHub Actions（有网）里下载 `ietf-wg-cellar/flac-test-files` 的 subset，用 CLI 解码后比对 `STREAMINFO` 的总样本数与 CRC 是否全部通过；这能补上当前最大的验证缺口。
3. **补 FLAC 编码器或明确移除路线图依赖。** 目前 FLAC 只解码，README 已如实标注；如果验收方期待「编解码对称」，可以在申报书里把编码器写成第二阶段目标。
4. **报告里做性能基线。** `moon bench` 或简单的 `now()` 计时，给出「解码 1 分钟 44.1kHz 立体声 WAV/FLAC 耗时」，展示性能不是短板。
5. **提交记录时间分布。** 31 个提交全部在同一天，虽然真实（本次开发确实在一天内完成），但评审若看「开发过程可追踪」会觉得偏集中。后续的真实验证、修 bug、加文档请照常单独提交，不要再 squash。

## 已检查的证据

```text
$ moon version --all
moon 0.1.20261020 (2284bd2 2026-10-20)
moonc v0.10.16+b1a0e846e (2026-10-16)
moonrun 0.1.20261020 (2284bd2 2026-10-20)

$ moon check --deny-warn
Finished. moon: no work to do                       # 0 errors, 0 warnings

$ moon test --deny-warn
Total tests: 130, passed: 130, failed: 0.

$ moon test --target wasm-gc
Total tests: 130, passed: 130, failed: 0.

$ moon build --target wasm-gc / --target native
Finished. moon: ... now up to date

$ git rev-list --count HEAD   → 31
$ git log --oneline（节选）
e89f52c docs: record the delivered feature set in the proposal
03f1a42 docs: document the delivered 0.3.0 feature set and completion status
620102a feat(dsp): add windows, FFT, spectra, spectrogram, biquad filters and statistics
31bbe9e feat(cli): add spectrum and spectrogram commands and DSP powered stats
febdb82 test(facade): verify container sniffing and dispatch; document FLAC internals
a05b354 ci: check, test, format and interface freshness on three platforms
95e1e56 chore: initialise the moonaudio MoonBit module
```

其他已核实项：

- 根目录 `LICENSE` = Apache License 2.0；`moon.mod` 的 `license = "Apache-2.0"` 一致。
- `moon.mod`：`name = "Sakuraqwq1/moonaudio"`、`version = "0.3.0"`、`repository`、`readme`、`keywords`、`description` 均已填写。
- 每个包都有 `pkg.generated.mbti` 且已提交（CI 会校验其新鲜度）。
- `.gitignore` 覆盖 `_build/`、`target/`、`.mooncakes/`、`.moonagent/`；工作区干净（`git status` 无未跟踪的构建产物）。
- `.github/workflows/ci.yml`：3 OS × (check/test/fmt/info 一致性) + wasm-gc 构建 + native 构建 + CLI 冒烟。
- 实测输出：`moon run cmd/main -- demo`（11 行 Markdown 报告，含 FFT 峰值、频谱图维度、滤波前后电平）、`moon run examples/tour`（合成/分析/滤波/重采样/容器五节）、`moon run cmd/main -- tone|info|stats|convert`（tone → WAV base64 → info → stats → 转 48k/24bit AIFF → info，全链路通过）。
- 未在仓库中发现个人敏感信息；`.par/`、`.tools/`、`.skill-stage/` 等脚手架目录都在仓库之外。

## 可选环境建议

- 工具链 `moon 0.1.20261020 / moonc 0.10.16`，高于 skill 要求的 0.10.7，无需升级。
- `moonbitlang/skills` 未安装；对本项目不是必需，但如果你想继续用 AI 维护 MoonBit 代码，建议装上（`moon add` 或按该仓库 README 安装）。
- 本机 `moon fmt` 依赖联网拉取格式器；如果长期离线开发，建议把 `moonfmt.exe -w` 写进 `.githooks/pre-commit`（当前 hook 只跑 `moon check`）。
- 本机没有安装 git 的全局配置，仓库使用局部 `user.name=Sakuraqwq1`、`user.email=Sakuraqwq1@users.noreply.github.com`；推送前确认邮箱与 GitHub 账号匹配，否则提交不会关联到你的贡献图。
