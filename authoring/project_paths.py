"""Locate the containing development project without assuming package depth/name."""
from pathlib import Path


def find_project_root(start=None):
    directory = Path(start or __file__).resolve()
    if directory.is_file():
        directory = directory.parent
    for candidate in (directory, *directory.parents):
        if (candidate / 'project.godot').is_file():
            return candidate
    raise FileNotFoundError('请将音游目录放入 Godot 工程后启动制谱工具（未找到 project.godot）。')
