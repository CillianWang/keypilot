#!/usr/bin/env python3
"""Back up, gracefully quit, stage, verify, replace and check readiness at the fixed path."""
from datetime import datetime
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import time
import signing

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "dist/Keylian.app"
TARGET = signing.INSTALL
SUPPORT = Path.home() / "Library/Application Support/KeyPilot"

def replace_apps(staging, target, existing, backup, verify):
    """Move old installations into a backup and restore them if replacement fails."""
    archived = backup / "PreviousApps"
    archived.mkdir()
    moved = []
    installed = False
    try:
        for app in existing:
            destination = archived / app.name
            app.rename(destination)
            moved.append((app, destination))
        staging.rename(target)
        installed = True
        verify(target)
    except Exception:
        if installed:
            shutil.rmtree(target)
        for original, saved in reversed(moved):
            saved.rename(original)
        raise
    return {str(original): str(saved) for original, saved in moved}

def main():
    signing.verify(SOURCE)
    existing = signing.installed_apps()
    backup = SUPPORT / "Backups" / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup.mkdir(parents=True, exist_ok=False)
    prefs = subprocess.run(["defaults", "export", signing.BUNDLE_ID, "-"], capture_output=True)
    if prefs.returncode == 0:
        (backup / "preferences.plist").write_bytes(prefs.stdout)
    (backup / "signing.json").write_bytes(signing.CONFIG.read_bytes())
    # Include both names during migration; match only each installed app's own executable.
    pids = []
    for app in existing:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        executable = str(app / "Contents/MacOS" / info["CFBundleExecutable"])
        processes = subprocess.run(["pgrep", "-f", "^" + re.escape(executable) + "( |$)"], capture_output=True, text=True)
        pids.extend(int(p) for p in processes.stdout.split())
    if pids:
        subprocess.run(["osascript", "-e", f'tell application id "{signing.BUNDLE_ID}" to quit'], check=True)
        for _ in range(50):
            alive = subprocess.run(["ps", "-p", ",".join(map(str,pids)), "-o", "pid="], capture_output=True, text=True)
            if not alive.stdout.strip():
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("旧进程未正常退出，未替换安装。请先保存工作并从菜单退出 Keylian / KeyPilot。")
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    staging = TARGET.with_name("Keylian.staging.app")
    if staging.exists():
        raise RuntimeError(f"暂存目录已存在，请检查上次安装状态：{staging}")
    shutil.copytree(SOURCE, staging, symlinks=True)
    signing.verify(staging)
    migrated = replace_apps(staging, TARGET, existing, backup, signing.verify)
    (backup / "installations.json").write_text(json.dumps(migrated, ensure_ascii=False, indent=2) + "\n")
    ready = SUPPORT / "ready.json"
    ready.unlink(missing_ok=True)
    subprocess.run(["open", str(TARGET)], check=True)
    expected = plistlib.loads((TARGET / "Contents/Info.plist").read_bytes())["CFBundleVersion"]
    state = None
    for _ in range(80):
        if ready.exists():
            state = json.loads(ready.read_text())
            if state.get("build") == expected:
                break
        time.sleep(0.1)
    if not state or state.get("build") != expected:
        raise RuntimeError(f"安装完成，但未收到当前构建就绪状态。备份：{backup}")
    print(json.dumps({"installed":str(TARGET), "backup":str(backup), "previous_installations":migrated, "ready":state}, ensure_ascii=False, indent=2))
    if not state["trusted"]:
        print("需要用户完成：打开系统设置的辅助功能权限，添加并允许 ~/Applications/Keylian.app，再从菜单点“重新连接”。")
    elif state["enabled"] and not state["hotkeys"]:
        raise RuntimeError("已安装，但热键存在冲突；请检查 Keylian 设置。")

if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"安装检查失败：{error}", file=sys.stderr)
        sys.exit(1)
