#!/usr/bin/env python3
"""Persistent, certificate-bound local signing. Never creates an identity or falls back to ad-hoc."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

BUNDLE_ID = "dev.pingy.keypilot"
CONFIG = Path(os.environ.get("KEYPILOT_SIGNING_CONFIG", str(Path.home() / "Library/Application Support/KeyPilot/signing.json")))
INSTALL = Path.home() / "Applications/KeyPilot.app"

def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)

def identities():
    output = run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True).stdout
    return dict(re.findall(r'([A-Fa-f0-9]{40}) "([^"]+)"', output))

def installed_identity(app):
    with tempfile.TemporaryDirectory(prefix="keypilot-certificate-") as temp:
        prefix = str(Path(temp) / "certificate")
        run(["codesign", "-d", "--extract-certificates=" + prefix, str(app)], capture_output=True)
        leaf = Path(prefix + "0")
        if not leaf.exists():
            raise RuntimeError("现有安装没有证书签名；不能静默更换身份。")
        return hashlib.sha1(leaf.read_bytes()).hexdigest().upper()

def load():
    if not CONFIG.exists():
        raise RuntimeError(f"固定签名配置缺失：{CONFIG}。请显式运行 signing.py init；不会生成新身份或降级签名。")
    data = json.loads(CONFIG.read_text())
    if data["bundle_id"] != BUNDLE_ID or data["identity"] not in identities():
        raise RuntimeError("固定证书不可用或配置的 Bundle ID 不匹配；请在钥匙串恢复原身份。")
    if INSTALL.exists() and installed_identity(INSTALL) != data["identity"]:
        raise RuntimeError("现有安装与固定证书不同，已拒绝替换。")
    return data

def initialize(identity=None):
    if CONFIG.exists():
        data = load()
        if identity and identity.upper() != data["identity"]:
            raise RuntimeError("固定配置已存在，拒绝改换证书。")
        print(f"已验证现有配置：{CONFIG}")
        return
    valid = identities()
    if INSTALL.exists():
        installed = installed_identity(INSTALL)
        if identity and identity.upper() != installed:
            raise RuntimeError("指定证书不同于已安装 App。")
        identity = installed
    if not identity:
        raise RuntimeError("首次初始化需显式 --identity SHA1；用 security find-identity -v -p codesigning 查看。新机器应在钥匙串创建本机代码签名身份。")
    identity = identity.upper()
    if identity not in valid:
        raise RuntimeError("证书及私钥未在本机钥匙串中形成有效代码签名身份。")
    requirement = f'identifier "{BUNDLE_ID}" and certificate leaf = H"{identity}"'
    if INSTALL.exists():
        # Verify the certificate binding before preserving the installed designated requirement.
        run(["codesign", "--verify", "--strict", "-R", "=" + requirement, str(INSTALL)])
        output = run(["codesign", "-d", "-r-", str(INSTALL)], capture_output=True)
        match = re.search(r"designated => (.*)", output.stdout + output.stderr)
        if match:
            requirement = match.group(1)
    data = {"bundle_id": BUNDLE_ID, "identity": identity, "requirement": requirement, "identity_name": valid[identity]}
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    with CONFIG.open("x") as stream:
        json.dump(data, stream, indent=2)
        stream.write("\n")
    CONFIG.chmod(0o600)
    print(f"固定签名配置已保存：{CONFIG}（只含非私密证书信息；私钥仍在钥匙串）")

def verify(app, data=None):
    data = data or load()
    run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", "-R", "=" + data["requirement"], str(app)])
    if installed_identity(app) != data["identity"]:
        raise RuntimeError("证书指纹不匹配。")

def sign(app):
    data = load()
    run(["codesign", "--force", "--sign", data["identity"], "--timestamp=none", "--requirements", "=designated => " + data["requirement"], str(app)])
    verify(app, data)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["init", "check", "sign", "verify"])
    parser.add_argument("app", nargs="?", type=Path)
    parser.add_argument("--identity")
    args = parser.parse_args()
    if args.action == "init":
        initialize(args.identity)
    elif args.action == "check":
        load(); print("固定签名证书及配置可用")
    elif args.app is None:
        parser.error("sign/verify 需要 .app 路径")
    elif args.action == "sign":
        sign(args.app)
    else:
        verify(args.app)

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, OSError, KeyError) as error:
        print(f"签名失败：{error}", file=sys.stderr)
        sys.exit(1)
