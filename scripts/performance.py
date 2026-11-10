#!/usr/bin/env python3
"""Summarize numeric local telemetry, without reading UI content or recording input text."""
import json
from pathlib import Path
import statistics

root=Path(__file__).resolve().parents[1]
path=Path.home()/"Library/Logs/KeyPilot/metrics.jsonl"
events=[]
if path.exists():
    for line in path.read_text().splitlines():
        try:
            event=json.loads(line)
            if event.get("event") == "navigation_enter":
                events.append([])
            if events:
                events[-1].append(event)
        except (ValueError,TypeError):
            pass

sessions=[]
for items in events[-20:]:
    entry={}
    for name in ["first_region","first_labels","all_labels","first_labels_drawn","all_labels_drawn"]:
        samples=[i.get("elapsed_ms") for i in items if i.get("event") == name]
        if samples:
            entry[name+"_ms"]=samples[0]
    scans=[i for i in items if i.get("event") == "scan_complete"]
    if scans:
        entry["first_scan"]={k:v for k,v in scans[0].items() if k not in ["event","uptime"]}
    entry["scroll_tick_samples"]=[{k:v for k,v in i.items() if k not in ["event","uptime"]} for i in items if i.get("event") == "scroll_ticks"]
    for name in ["codes","layout","publish"]:
        samples=sorted(i["ms"] for i in items if i.get("event") == name and "ms" in i)
        if samples:
            entry[name]={"samples":len(samples),"p50_ms":statistics.median(samples),"p95_ms":samples[min(len(samples)-1,int(len(samples)*0.95))],"max_ms":max(samples)}
    sessions.append(entry)
report={"sessions":sessions,"interpretation":{"first_region":"fresh region geometry accepted by control queue","first_labels":"layout ready, before main-thread paint; historical name","all_labels":"complete scan layout ready, before main-thread paint; historical name","drawn":"AppKit displayIfNeeded completed; does not measure compositor or target-app repaint","ax_ms":"measured AX calls including window/focus setup, not additive with scan_work_ms","scan_work_ms":"sliced traversal plus local region/dedupe work, includes traversal IPC","450_ms":"intentional release debounce, excluded from first activation","target_app_visual_scroll_update":"unknown; no screen capture permission or frame instrumentation","sample_classification":"application family and cold/warm/repeated classification require a controlled manual run; never inferred from timings"}}
(root/"artifacts/performance.json").write_text(json.dumps(report,indent=2)+"\n")
print(json.dumps(report,indent=2))
