# FluidR3 代表器乐音效

2026-10-26：新增 **191 个 WAV**，覆盖 GM 1–120 的 120 种乐器、合奏、合成音色；其中 49 种提供第二个代表音区，另外提供 22 种独立小打击。GM 121–128 的电话、直升机等生活音效不收录。保留原有 12 种 Virtuosity 鼓、镲及合成短敲，总选择数为 204。

- 音源：Fluid (R3) GM v3.1，Frank Wen 与原库 README 中列出的贡献者。
- 来源仓库：https://github.com/pianobooster/fluid-soundfont
- 原始 SF2：https://github.com/pianobooster/fluid-soundfont/releases/download/v3.1/FluidR3_GM.sf2
- 原始许可证：https://github.com/pianobooster/fluid-soundfont/blob/main/COPYING
- 授权：MIT；完整副本见 [LICENSE.txt](LICENSE.txt)，作者与采样贡献说明见 [UPSTREAM_README.txt](UPSTREAM_README.txt)。
- 离线渲染：TinySoundFont v0.9，Bernhard Schelling，基于 Steve Folta 的 SFZero。https://github.com/schellingb/TinySoundFont
- 渲染器许可：[TinySoundFont_LICENSE.txt](TinySoundFont_LICENSE.txt)。游戏不依赖其动态库、可执行文件或 MIDI 播放器。

## 选择与用途

每个条目可分别用于普通成功、空按、长按开始、sub 和结束，继续使用既有试听与保存功能。钢琴、电钢琴、拨弦、贝斯、音高打击等提供两个音区；吉他还包括尼龙弦、钢弦、清音、闷音、过载、失真、泛音等不同 GM 音色。小打击包含拍手、铃鼓、牛铃、邦戈、康加、沙锤、刮瓜、响棒、三角铁等。

这里提供代表性声音，不是完整的键盘音域或多力度采样。名称中的 C4 按 MIDI 60 定义；贝斯等使用 C3，钟琴等使用较高音区。标为“慢起音”的铺底、合唱、效果音更适合长按/段落色彩，不建议用作需要清晰瞬态的主要敲击反馈。弓弦、吹管也保留乐器本身的起音包络，未添加人工点击声。各音色的听感仍需结合 BGM 人工选用。

逐项 WAV 链接见 [CATALOG.md](CATALOG.md)。[samples.json](samples.json) 保存每个文件的 bank、零起算 program、MIDI 音高、力度、note-on 时长、裁切、增益及测量结果，便于未来逐音符指定音效。

## 渲染处理

- 44,100 Hz，16-bit PCM WAV，单声道。渲染时居中混合立体声音色；播放时沿用轨道声像，试听居中。
- 统一力度 100/127。普通音色 note-on 280 ms、慢起音 650 ms、小打击 100 ms；之后发 note-off，保留 release，单个片段最多 3 s。
- 不额外叠加混响或合唱。TinySoundFont 不完整实现 SF2 的 modulator、reverb/chorus send，因此这些 WAV 是该渲染器的离线演绎，不保证与所有 SoundFont 播放器音色一致。
- 只去掉低于相对峰值 -70 dB 的首尾静音，头部保留约 0.5 ms，末尾 20 ms 淡出避免截断爆音；不会把渐起弦乐强行变成瞬时起音。
- 沿用现有音效的“最强 50 ms RMS = -16 dBFS、单声峰值不超过 -1 dBFS”目标，不压缩动态。增益已写入 WAV，运行时补偿为 0 dB，避免重复增益。沙锤与长刮瓜因瞬态峰值上限分别约为 -17.94/-18.69 dBFS RMS。
- 原有音效、用户音量、BGM、音画校准与判定逻辑不变。多音叠加和 200% 音量仍可能提高总输出电平。

## 重新渲染

工具只用于制作资产，不参与游戏运行。需要 Python、NumPy 和系统 GCC；先把上述 SF2、TinySoundFont 的 `tsf.h` 下载到宿主项目 `tmp/rhythm_instruments/`，完整原库不随游戏分发。

在宿主项目根目录执行（包可移动，按实际相对路径修改命令前缀）：

```powershell
python games/minigame/gp_rhythm_game/authoring/render_instruments.py --soundfont tmp/rhythm_instruments/FluidR3_GM.sf2 --tsf-header tmp/rhythm_instruments/tsf.h --work tmp/rhythm_instruments/render --catalog-output tmp/rhythm_instruments/rhythm_audio.gd
```

脚本生成本目录 WAV、测量清单和目录，另生成待审阅的 `rhythm_audio.gd` 候选，包含原有音效及新增条目。将候选应用到包内同名脚本后刷新 Godot 资源。重新运行原生编辑器或游戏即可使用；无需修改判定或添加运行时插件。
