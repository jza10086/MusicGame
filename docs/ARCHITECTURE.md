# MusicGame architecture

- `music_game.tscn` / `music_game.gd`: menu, two-lane stage, chart selection, HUD, results and calibration entry.
- `rhythm_prototype.gd`: shared playback clock, input edges, judgement, calibration and explicit settings persistence. Its `.tscn` is the calibration lab, not another visual theme.
- `rhythm_timing.gd`: judgement windows, compensation, visual time and calibration statistics.
- `rhythm_audio.gd`: original PCM metronome and practice audio.
- `rhythm_chart.gd`: strict version 2 chart loading and validation; `charts/bad_apple/` contains the three converted charts, original SM and matching OGG.
- `skins/neon.gd`: perspective rendering, continuous edges, full-width longitudinal lane highlight, consumed-note animation and hit effects. It never owns timing or score.
- `convert_sm.py`: deterministic StepMania-to-2K conversion including BPM, stops, offset, simultaneous taps and hold heads.

The audio player position plus time since mix minus output latency is the common clock. Input compensation and visual compensation remain independent. Visual travel is constant in track depth, perspective-projected on screen. Losing focus stops the round; restarting creates a fresh audio clock. Only Apply writes local configuration. No framework autoload, MCP plugin, network service or copied user settings is required.

Neon is the only current presentation. Earlier pixel/aurora skins and the old synthetic UI-only session implementation have been removed; Git history preserves them.
