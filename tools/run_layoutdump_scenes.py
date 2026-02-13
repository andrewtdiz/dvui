import argparse
import json
import os
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


def scene_baseline_path(repo_root: Path, scene_name: str, scene_cfg: dict) -> Path:
    baseline = scene_cfg.get("baseline")
    if isinstance(baseline, str) and baseline:
        return repo_root / baseline
    return repo_root / "snapshots" / f"{scene_name}.layout.json"


def ensure_exe(repo_root: Path, exe: Path) -> None:
    if exe.exists():
        return
    subprocess.check_call(["sh", "zig_build_simple.sh"], cwd=repo_root)
    if not exe.exists():
        raise RuntimeError(f"missing exe: {exe}")


def run_layout_dump(repo_root: Path, exe: Path, scenes_arg: str, scene_name: str, update_baseline: bool) -> None:
    cmd = [str(exe), "--scenes", scenes_arg, scene_name]
    if update_baseline:
        cmd.append("--update-baseline")
    subprocess.check_call(cmd, cwd=repo_root)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenes", default="tools/layoutdump_scenes.json")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--only", nargs="*")
    parser.add_argument("--init-baselines", action="store_true")
    parser.add_argument("--update-baselines", action="store_true")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    scenes_arg = args.scenes
    scenes_path = repo_root / scenes_arg
    scenes = load_scenes(scenes_path)

    exe = repo_root / "zig-out" / "bin" / "luau-layout-dump.exe"
    ensure_exe(repo_root, exe)

    selected = set(args.only) if args.only else None
    if selected is None and not args.all:
        selected = {name for name in scenes.keys() if name.startswith("docs_")}
    for scene_name in sorted(scenes.keys()):
        if selected is not None and scene_name not in selected:
            continue
        scene_cfg = scenes[scene_name]
        if not isinstance(scene_cfg, dict):
            raise ValueError(f"invalid scene config: {scene_name}")

        baseline_path = scene_baseline_path(repo_root, scene_name, scene_cfg)
        update = args.update_baselines or (args.init_baselines and not baseline_path.exists())
        run_layout_dump(repo_root, exe, scenes_arg, scene_name, update)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as e:
        sys.stderr.write(f"{e}\n")
        raise SystemExit(1)
