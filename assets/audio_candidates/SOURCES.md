# 音游敲击音效候选与来源

2026-10-26：新增 [FluidR3 代表器乐 WAV](fluid_r3/SOURCES.md)，191 个候选覆盖键盘、吉他、贝斯、弦乐、铜管、木管、民族乐器、合成器及小打击，部分乐器提供多个代表音区。已接入五类敲击音效的选择、试听、保存与 Web 预览；完整列表见 [器乐目录](fluid_r3/CATALOG.md)。新 WAV 已做响度处理，以下“原始素材未归一化”的描述只针对旧候选素材。

2026-10-26：新增 [FluidR3 代表器乐 WAV](fluid_r3/SOURCES.md)，191 个候选覆盖键盘、吉他、贝斯、弦乐、铜管、木管、民族乐器、合成器及小打击，部分乐器提供多个代表音区。已接入五类敲击音效的选择、试听、保存与 Web 预览；完整列表见 [器乐目录](fluid_r3/CATALOG.md)。新 WAV 已做响度处理，以下“原始素材未归一化”的描述只针对旧候选素材。

整理日期：2026-10-22。首批 8 个候选作者为 Kenney；新增架子鼓采样来自 Versilian Studios 与 Karoryfer Samples。当前默认仍为自行合成的敲击声；12 个架子鼓候选已接入音效设置，8 个 Kenney 候选已从选择与播放目录移除，仅保留原始素材与来源记录，可分别用于成功敲击和空敲击。原始素材未剪辑、未归一化。

## 来源与授权

| 标识 | 素材包 / 官方来源 | 官方许可 | 本地许可证 |
| --- | --- | --- | --- |
| interface | [Interface Sounds 1.0](https://kenney.nl/assets/interface-sounds) | CC0 | `assets/audio_candidates/interface/LICENSE.txt` |
| impact | [Impact Sounds 1.0](https://kenney.nl/assets/impact-sounds) | CC0 | `assets/audio_candidates/impact/LICENSE.txt` |
| ui | [UI Audio 1.0](https://kenney.nl/assets/ui-audio) | CC0 | `assets/audio_candidates/ui/LICENSE.txt` |

表格中的说明路径相对音游根目录，文件链接相对本文件所在目录。三包官网及压缩包许可证均已核对；原文允许个人、教育和商业项目使用，署名非强制，本项目仍保留作者与来源。许可原文：[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。

## 候选文件

长度读取 OGG 的采样率与末页 granule position，未以文件哈希验证。以下用途是按素材分类与时长给出的初筛建议，不代表已经在 Bad Apple 密集谱面中完成听感验收；时长包含原文件尾音或静音。

| 文件（点击打开） | 来源标识 | 原始长度 | 建议用途 |
| --- | --- | ---: | --- |
| [click_001.ogg](interface/click_001.ogg) | interface | 100 ms | 普通成功敲击的优先候选 |
| [tick_001.ogg](interface/tick_001.ogg) | interface | 23 ms | 空按、低存在感反馈候选 |
| [pluck_001.ogg](interface/pluck_001.ogg) | interface | 102 ms | 成功敲击的有音高候选，需检查与歌曲的协调 |
| [impactGeneric_light_000.ogg](impact/impactGeneric_light_000.ogg) | impact | 139 ms | 较有实体感的成功敲击候选 |
| [impactWood_light_000.ogg](impact/impactWood_light_000.ogg) | impact | 266 ms | 偏打击乐方向的替代候选 |
| [impactPlate_light_000.ogg](impact/impactPlate_light_000.ogg) | impact | 542 ms | 亮色叠加层候选，避免高频连击刺耳 |
| [click1.ogg](ui/click1.ogg) | ui | 94 ms | 普通短点击的替代候选 |
| [mouseclick1.ogg](ui/mouseclick1.ogg) | ui | 59 ms | 空按或机械按键风格候选 |

## 旧 Kenney 候选的历史初筛（已停用）

先对比 `click_001` 与 `click1` 作为成功敲击，`tick_001` 与 `mouseclick1` 作为空按；希望打击感更实体时再试 `impactWood_light_000`。`pluck_001` 和 `impactPlate_light_000` 可作为有音高或亮色的对照，不建议直接全音量用于密集谱面。

在同一段 Hard 谱面中对比，并分别测试单击、双押、快速连击与空按。关注起音前静音、长尾音堆叠、BGM 被遮盖和耳机高频刺激。需要裁切时保留原文件，另存加工版本并在此记录处理方式；最终播放音量以实际试听为准。

## 当前游戏音效设置

主菜单 → 音效设置：BGM / 校准节拍、成功敲击、空敲击分别为 0–100%；0% 静音。三路均可试听。成功敲击指实际命中音符（PERFECT / GOOD / OK），不包含自动 MISS；空按指逻辑按压未消费音符。长按、重复键与同轨别名不会连响。

调整只预览；“应用并保存”才写入本地 JSON。取消恢复打开前的音量并停止试听。声音反馈不参与谱面时间或判定计算。成功敲击、空敲击各有独立选择框：默认合成音 + 12 个架子鼓候选。试听与实战使用同一缓存采样，按各自音量播放；“应用并保存”持久化音效 ID 与音量，重新打开仍保留选择。取消恢复打开前的选择与音量；配置中无效的音效 ID 回退默认合成音。

## 新增：真实架子鼓单次采样（Virtuosity Drums）

整理日期：2026-10-22。来源：[官方介绍](https://versilian-studios.com/virtuosity-drums/) / [官方链接的源仓库](https://github.com/sfzinstruments/virtuosity_drums)。制作：Versilian Studios LLC. 与 Karoryfer Samples（Karoryfer Lecolds）；演奏：Austin McMahon。官方页面及仓库许可证为 CC0 1.0，原许可证已随素材保存为 `assets/audio_candidates/virtuosity/LICENSE.txt`。

选取统一 Mid 麦克风位置的 12 个单次敲击，保留原始 FLAC 内容，仅将本地文件名改为方便识别的名称；未剪辑、未压缩动态、未归一化。逐文件原始路径与下载链接见同目录 `sources.json`。这 12 个候选已加入成功敲击与空敲击的独立选择框，可试听并应用保存；原有默认音效保持不变。大于 5 秒的采样标注“长尾”。播放使用同目录 WAV 副本：通过 libsndfile 从 FLAC 解码成 PCM WAV，保持采样率、位深与完整帧数，以 (L + R) / 2 混合为单声道；不裁切、不归一化。原始 FLAC 和许可证仍保留。

长度取自 FLAC STREAMINFO 的采样数和采样率，包含完整衰减与可能的静音，并非有效响声长度。以下建议基于乐器类别和文件时长，尚未进行实际谱面听感验收。

| 素材（本地文件） | 原始长度 | 用途初筛 | 原始文件 |
| --- | ---: | --- | --- |
| [底鼓](virtuosity/kick.flac) | 2.161 s | 低频重击 | [来源](https://raw.githubusercontent.com/sfzinstruments/virtuosity_drums/master/Samples/mid/kick/mid_kick_snoff_vl3_rr1.flac) |
| [军鼓](virtuosity/snare.flac) | 1.671 s | 成功敲击主候选 | [来源](https://raw.githubusercontent.com/sfzinstruments/virtuosity_drums/master/Samples/mid/snare/mid_snare_center_vl24.flac) |
| [鼓边侧击](virtuosity/cross_stick.flac) | 2.823 s | 空按或清晰短击候选 | [来源](https://raw.githubusercontent.com/sfzinstruments/virtuosity_drums/master/Samples/mid/snare/mid_snare_crossstick_vl12.flac) |
| [高通鼓](virtuosity/high_tom.flac) | 1.809 s | 有鼓腔共鸣的击打 | [来源](https://raw.githubusercontent.com/sfzinstruments/virtuosity_drums/master/Samples/mid/htom/mid_htom_center_vl12.flac) |
| [低通鼓](virtuosity/low_tom.flac) | 4.737 s | 较低沉的击打 | [来源](https://raw.githubusercontent.com/sfzinstruments/virtuosity_drums/master/Samples/mid/ltom/mid_ltom_center_vl12.flac) |
| [闭合踩镲](virtuosity/closed_hat.flac) | 0.696 s | 空按或密集敲击候选 | [来源](https://raw.githubusercontent.com/sfzinstruments/virtuosity_drums/master/Samples/mid/hh/mid_hh_closed_vl3_rr1.flac) |
| [开放踩镲](virtuosity/open_hat.flac) | 9.562 s | 较亮的重击，留意尾音 | [来源](https://raw.githubusercontent.com/sfzinstruments/virtuosity_drums/master/Samples/mid/hh/mid_hh_open_vl3_rr1.flac) |
| [踩镲脚踏](virtuosity/pedal_hat.flac) | 1.950 s | 较轻的空按候选 | [来源](https://raw.githubusercontent.com/sfzinstruments/virtuosity_drums/master/Samples/mid/hh/mid_hh_pedal_vl2_rr1.flac) |
| [吊镲](virtuosity/crash.flac) | 12.624 s | 段落重音，避免连续叠加长尾 | [来源](https://raw.githubusercontent.com/sfzinstruments/virtuosity_drums/master/Samples/mid/crash/mid_crash_crash_vl2_rr1.flac) |
| [叮叮镲](virtuosity/ride.flac) | 8.445 s | 金属节奏音色 | [来源](https://raw.githubusercontent.com/sfzinstruments/virtuosity_drums/master/Samples/mid/ride/mid_ride_ride_vl2_rr1.flac) |
| [叮叮镲帽](virtuosity/ride_bell.flac) | 5.828 s | 更有音高的金属重音 | [来源](https://raw.githubusercontent.com/sfzinstruments/virtuosity_drums/master/Samples/mid/ride/mid_ride_bell_vl2_rr1.flac) |
| [平顶叮叮镲](virtuosity/flat_ride.flac) | 8.166 s | 另一种镲片音色对照 | [来源](https://raw.githubusercontent.com/sfzinstruments/virtuosity_drums/master/Samples/mid/flatride/mid_flatride_ride_vl2_rr1.flac) |

优先试听组合：成功敲击用军鼓或鼓边侧击，空敲击用闭合踩镲或脚踏踩镲；希望更低沉可对比底鼓和通鼓。吊镲、开放踩镲、叮叮镲先作为音色参考：直接反复播放完整尾音容易堆叠，正式接入密集谱面时可另做短尾版本，保留原音并记录裁切、淡出和增益参数。接入只扩展音效目录，音画同步与判定逻辑不变。

音效下拉菜单最大高度为 320 像素，内容超出时通过内置滚动条浏览，支持滚轮和键盘选择。旧配置中的已停用 Kenney ID 按现有无效 ID 规则回退到默认合成音；应用保存后写入当前选择。

2026-10-23：游戏 WAV 已居中混为单声道，原始立体声 FLAC 保留。左右轨通过独立临时总线分别施加 -0.15 / +0.15 声像偏移，成功和空敲击一致，双押可独立叠加；试听居中，BGM 与判定时钟不变，场景退出时清理总线。

长按音效分为开始、Sub、结束三路，默认分别为军鼓、闭合踩镲、鼓边侧击；各自可选择素材、试听、调节音量和保存。沿用上述 CC0 来源，不新增外部音源。独立长按测试的 hold_test.wav 为项目原创合成节拍。


2026-10-23 响度补偿：游戏与试听统一使用 `rhythm_audio.gd` 中的 `TAP_GAIN_DB`。按源 WAV 最强连续 50ms RMS 计算增益（45ms 合成音使用全长），目标 -16dBFS，同时将单声采样峰值约束到 -1dBFS；用户音量继续线性相乘，0 仍为静音。此数值是短时电平指标，不是 LUFS 或主观等响保证。未改写原素材、尾音、声像或 BGM。

| 音色 ID | 补偿 dB | 补偿后短时 RMS dBFS |
| --- | ---: | ---: |
| drum_closed_hat | +27.49 | -16.01 |
| drum_crash | +15.56 | -16.01 |
| drum_cross_stick | +13.01 | -16.80 |
| drum_flat_ride | +29.77 | -16.01 |
| drum_high_tom | +2.84 | -16.01 |
| drum_kick | +12.21 | -16.00 |
| drum_low_tom | +1.64 | -16.00 |
| drum_open_hat | +24.93 | -16.00 |
| drum_pedal_hat | +21.54 | -16.00 |
| drum_ride | +27.50 | -17.63 |
| drum_ride_bell | +25.12 | -16.01 |
| drum_snare | +4.86 | -16.00 |
| synth | +2.65 | -18.15 |

新默认音量：成功/长按开始/结束 65%，空敲击 50%，sub 45%。已保存的用户音量不覆盖，但会自动获得素材增益补偿。单声峰值约束不等于多声部混音限幅；多条长尾镲片连续叠加仍需按听感降低对应音量。
