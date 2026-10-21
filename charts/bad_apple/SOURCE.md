# Bad Apple!! 本地测试素材来源

- 歌曲：Bad Apple!! / Alstroemeria Records。
- 谱面：Gpop，Touhou Fujinya ~ Touhou Pad Pack Rebirth，dance-single / Easy、Medium、Hard。本项目将 Medium 显示为 Normal。
- 来源页面：https://zenius-i-vanisher.com/v5.2/viewsimfile.php?simfileid=9526
- 谱面原文件：https://zenius-i-vanisher.com/simfiles/Touhou%20Fujinya%20~%20Touhou%20Pad%20Pack%20Rebirth/Bad%20Apple!!/Bad%20Apple!!.sm
- 配套音源：https://zenius-i-vanisher.com/simfiles/Touhou%20Fujinya%20~%20Touhou%20Pad%20Pack%20Rebirth/Bad%20Apple!!/BAD%20APPLE!!.ogg
- 获取日期：2026-10-11。

原文件 source.sm 保留用于复现，音源重命名为 bad_apple.ogg。没有下载视频、背景或其他素材。

chart.json、normal.json、hard.json 均为 GodotParty 2K 格式版本 2：notes_ms 为从音源起点计时的毫秒，key_count=2、note_type=tap，lanes 为 0（左轨）或 1（右轨）。变速分段积分，计入音符之前的停顿，再减去 SM OFFSET（1.660 秒）；同拍停顿在击中该拍后发生。不修改音源或额外整体平移谱面。

| 显示难度 | 原谱难度 | 文件 | 单击数 | 原始起点 | 合并同时按键 |
| --- | --- | --- | ---: | ---: | ---: |
| Easy | Easy | chart.json | 287 | 288 | 1 |
| Normal | Medium | normal.json | 532 | 536 | 4 |
| Hard | Hard | hard.json | 704 | 705 | 1 |

三种难度均有 2 个长按仅保留起点，尾端不产生新音符。首音均为 13991.782 ms，末音均为 208774.391 ms。不会为降低难度再删掉密集音符；此双轨版本不等同于原四方向玩法。

复现（在项目根目录）：

```powershell
python convert_sm.py charts/bad_apple/source.sm charts/bad_apple/chart.json --mapper Gpop --source-url "https://zenius-i-vanisher.com/v5.2/viewsimfile.php?simfileid=9526"
```

生成 Normal 时将输出文件改为 normal.json 并添加 `--difficulty Medium`；生成 Hard 时改为 hard.json 并添加 `--difficulty Hard`。

作者与来源保持为原作者，不将该歌曲或谱面标为本项目原创。来源页未提供可确认的再发行许可证；当前按用户要求用于本地原型测试，正式发布前需另行确认音源与谱面的使用授权。

双轨映射：SM 列顺序为左、下、上、右，前两列映射左轨，后两列映射右轨。同轨同刻合并，跨轨同刻保留双押。Easy 左148/右139，Normal 左268/右264，Hard 左372/右332。时间点集合与原纯左轨转换一致，不改 BPM、停顿或 OFFSET。
