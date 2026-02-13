import argparse
import json
import subprocess
import sys
from pathlib import Path


def load_scenes(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        root = json.load(f)
    scenes = root.get("scenes")
    if not isinstance(scenes, dict):
        raise ValueError("invalid scenes file")
    return scenes


def ensure_exe(repo_root: Path, exe: Path) -> None:
    if exe.exists():
        return
    subprocess.check_call(["sh", "zig_build_simple.sh"], cwd=repo_root)
    if not exe.exists():
        raise RuntimeError(f"missing exe: {exe}")


def run_runner(
    repo_root: Path,
    exe: Path,
    lua_entry: str,
    app_module: str | None,
    width: int,
    height: int,
    pixel_width: int | None,
    pixel_height: int | None,
    screenshot_out: str,
) -> None:
    cmd = [
        str(exe),
        "--lua-entry",
        lua_entry,
    ]
    if app_module is not None:
        cmd.extend(["--app-module", app_module])
    cmd.extend([
        "--width",
        str(width),
        "--height",
        str(height),
        "--screenshot-auto",
        "--screenshot-out",
        screenshot_out,
    ])
    if pixel_width is not None:
        cmd.extend(["--pixel-width", str(pixel_width)])
    if pixel_height is not None:
        cmd.extend(["--pixel-height", str(pixel_height)])

    subprocess.check_call(cmd, cwd=repo_root)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenes", default="tools/layoutdump_scenes.json")
    parser.add_argument("--only", nargs="*")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    scenes_path = repo_root / args.scenes
    scenes = load_scenes(scenes_path)

    exe = repo_root / "zig-out" / "bin" / "luau-native-runner.exe"
    ensure_exe(repo_root, exe)

    selected = set(args.only) if args.only else None
    for scene_name in sorted(scenes.keys()):
        if selected is not None and scene_name not in selected:
            continue
        scene_cfg = scenes[scene_name]
        if not isinstance(scene_cfg, dict):
            raise ValueError(f"invalid scene config: {scene_name}")

        lua_entry = scene_cfg.get("luaEntry") if isinstance(scene_cfg.get("luaEntry"), str) else "luau/index.luau"
        app_module = scene_cfg.get("appModule") if isinstance(scene_cfg.get("appModule"), str) else None
        width = int(scene_cfg.get("width", 1280))
        height = int(scene_cfg.get("height", 720))
        pixel_width = scene_cfg.get("pixelWidth")
        pixel_height = scene_cfg.get("pixelHeight")
        pixel_width_i = int(pixel_width) if pixel_width is not None else None
        pixel_height_i = int(pixel_height) if pixel_height is not None else None

        screenshot_out = f"artifacts/{scene_name}.png"
        run_runner(repo_root, exe, lua_entry, app_module, width, height, pixel_width_i, pixel_height_i, screenshot_out)

        if not (repo_root / screenshot_out).exists():
            raise RuntimeError(f"missing screenshot: {screenshot_out}")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as e:
        sys.stderr.write(f"{e}\n")
        raise SystemExit(1)
