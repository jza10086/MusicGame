# M06 霓虹节拍　A　依赖 G01，专用音频按 G03

来源：2026-11-07 架构审查及其最后实施记录。整理日期：2026-11-14。下列待办保留原状态；实施前核对本包源码与工作区，不以历史检查代替本次验收。

[共享 G01–G03 任务](../../../protocols/godot_party_default_protocol/doc/godot_party_default_protocol_development.md) · [包说明](gp_rhythm_game_guide.md)


包：`gp_rhythm_game`。定位：[rhythm_backend.gd](../rhythm_backend.gd) 的 `preview_settings_path()`、DEFAULTS、`_load_settings()`、`_save_settings()`；[music_game.gd](../music_game.gd) 的 `_ready()`；`party_round.gd`。

本包 M06 代码改造已落地：正式使用 `settings.gd` / PartyConfig，作者设置独立保存，固定播放器见 `ui/playback_audio.tscn`。共享 G01、G03 未在本包会话中修改，仍待统一处理。已通过定向运行检查：声明/翻译、PartyConfig 注入、JSON 按键、固定播放器、输入释放、重复停止清理与原生预览初始化；未重跑跨进程联机与真机听感验收。

验证：真实音频设备上的短音/长按/校准、菜单与失焦释放、试听结束清理；两端准备至结算以及观战房主。音频时间精度需要人工听感/操作验收。

## 人工验收待办

保留自 2026-11-05 场景审查，后续记录未明确关闭的人工事项：真机音频与按键手感待人工验收。
