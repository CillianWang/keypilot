#!/usr/bin/env python3
"""Verify identity continuity and negative cases on disposable bundles, never the installed app."""
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import signing

ROOT = Path(__file__).resolve().parents[1]

def result(args):
    return subprocess.run(args, capture_output=True, text=True)


def main():
    data = signing.load()
    source = ROOT / "dist/Keylian.app"
    signing.verify(source)
    with tempfile.TemporaryDirectory(prefix="keylian-signature-regression-") as tmp:
        tmp = Path(tmp)
        first, second, changed, foreign = [tmp / name for name in ["one.app", "two.app", "tampered.app", "foreign.app"]]
        for app in [first,second,changed,foreign]:
            shutil.copytree(source, app)
        (second / "Contents/Resources/LocalBuild.txt").write_text("Different build content\n")
        signing.sign(second)
        requirements=[]
        for app in [first,second]:
            signing.verify(app)
            output=result(["codesign","-d","-r-",str(app)])
            requirements.append(re.search(r"designated => (.*)", output.stdout+output.stderr).group(1))
        assert requirements[0] == requirements[1], "Changed build altered designated requirement"
        (changed / "Contents/Resources/LocalBuild.txt").write_text("tampered\n")
        tampered=result(["codesign","--verify","--strict",str(changed)])
        assert tampered.returncode != 0, "Tampered sealed resource was accepted"
        # This deliberately creates an unsigned-identity adversarial fixture only, never a deliverable.
        subprocess.run(["codesign","--force","--sign","-","--requirements",'=designated => identifier "dev.pingy.keypilot"',str(foreign)],check=True,capture_output=True)
        rejected=result(["codesign","--verify","--strict","-R","="+data["requirement"],str(foreign)])
        assert rejected.returncode != 0, "Same Bundle ID without pinned certificate was accepted"
        environment=dict(os.environ,KEYLIAN_SIGNING_CONFIG=str(tmp/"missing.json"))
        missing=subprocess.run(["python3",str(ROOT/"scripts/signing.py"),"check"],env=environment,capture_output=True,text=True)
        assert missing.returncode != 0 and not (tmp/"missing.json").exists(), "Missing config did not fail closed"
        report={"two_distinct_bundles_same_designated_requirement":True,"tampered_bundle_rejected":True,"same_bundle_id_without_pinned_certificate_rejected":True,"missing_config_rejected_without_creation":True,"different_certificate_signer":"not run: no second trusted signing identity; same-ID ad-hoc negative case passed"}
        (ROOT/"artifacts/signing-regression.json").write_text(json.dumps(report,indent=2)+"\n")
        print(json.dumps(report,indent=2))

if __name__ == "__main__":
    main()
