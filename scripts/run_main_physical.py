"""Run the frozen main PNR and check its actual physical artifacts (no hardware I/O).

Only a fresh run name is accepted. --verify-dir reads an existing run without
changing it and writes a new review beneath this project's physical reports.
There is deliberately no EDA execution timeout. Python 3.10+, standard library.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import time
import traceback

BASE = "D2_keyboard_leds"
DEFAULT_MANIFEST = "reports/integration_20261101/synthesis_initial/netlist_manifest.json"
DEFAULT_TOOL = "C:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe"
SUFFIXES = (".fs", ".tr", ".tr.html", ".rpt.txt", ".rpt.html", ".sdf",
            ".pin.html", ".pin", ".log", ".power.html")
REQUIRED = (".fs", ".tr", ".rpt.txt", ".sdf", ".pin.html", ".log")
EXTRA = ("src/keyboard.cst", "src/keyboard.sdc", "scripts/build_keyboard.tcl",
         "scripts/inspect_timing.py", "scripts/check_lcd_clock_timing.py")
SOURCE_EXT = {".sv", ".svh", ".hex"}
CORE_CLOCKS = {"ref_clk": 50.0, "audio_clk": 61.44, "pixel_clk": 35.0}


def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_json(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def read_text(path):
    p = Path(path)
    return p.read_text(encoding="utf-8", errors="replace") if p.is_file() else ""


def local_path(root, name):
    name = str(name).replace("\\", "/")
    p = (root / name).resolve()
    if not p.is_relative_to(root):
        raise ValueError("Input escapes project: " + name)
    return p


def describe(path):
    info = path.stat()
    return dict(bytes=info.st_size, sha256=digest(path), mtime_ns=info.st_mtime_ns,
                mtime_utc=dt.datetime.fromtimestamp(info.st_mtime, dt.timezone.utc).isoformat())


def source_inventory(root):
    files = [p for p in (root / "src").rglob("*") if p.is_file() and p.suffix.lower() in SOURCE_EXT]
    files.extend(root.glob("*.gprj"))
    if not files or not (root / "keyboard_adsr.gprj").is_file():
        raise ValueError("Missing src inventory or keyboard_adsr.gprj")
    return {p.relative_to(root).as_posix(): digest(p) for p in sorted(files)}


def normalize_hashes(raw):
    if not isinstance(raw, dict) or not raw:
        raise ValueError("Manifest source_files must be a nonempty hash map")
    result = {}
    for name, value in raw.items():
        key = str(name).replace("\\", "/")
        if key in result:
            raise ValueError("Duplicate normalized source path: " + key)
        value = value.get("sha256") if isinstance(value, dict) else value
        if not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", value):
            raise ValueError("Invalid SHA256: " + key)
        result[key] = value.lower()
    return result


def compare_hashes(root, expected):
    differences = []
    for name, hash_value in expected.items():
        try:
            p = local_path(root, name)
            actual = digest(p) if p.is_file() else None
            if actual != hash_value:
                differences.append(dict(path=name, expected=hash_value, actual=actual))
        except Exception as e:
            differences.append(dict(path=name, error=repr(e)))
    return differences


def check_frozen(root, manifest, inventory, extra):
    current = source_inventory(root)
    return dict(source_differences=compare_hashes(root, manifest),
                inventory_added=sorted(set(current) - set(inventory)),
                inventory_removed=sorted(set(inventory) - set(current)),
                inventory_changed=sorted(k for k in set(current) & set(inventory) if current[k] != inventory[k]),
                extra_differences=compare_hashes(root, extra))


def frozen_pass(check):
    return all(not value for value in check.values())


def snapshot_inputs(root, output, hashes):
    for name, expected in hashes.items():
        source = local_path(root, name)
        target = output / "frozen_inputs" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        if digest(target) != expected:
            raise ValueError("Input changed while copying: " + name)


def artifact_paths(directory):
    return [directory / (BASE + suffix) for suffix in SUFFIXES]


def clean_old_pnr(root, output):
    """Remove exact known output files, never a tree, database or synthesis file."""
    pnr = root / "impl/pnr"
    if pnr.resolve() != root / "impl/pnr":
        raise ValueError("impl/pnr is redirected; refusing cleanup")
    old = {}
    for p in artifact_paths(pnr):
        if not p.exists():
            continue
        if not p.is_file() or p.is_symlink() or p.resolve().parent != pnr.resolve():
            raise ValueError("Unsafe PNR output: " + str(p))
        archive = output / "preexisting" / p.name
        archive.parent.mkdir(exist_ok=True)
        old[p.name] = describe(p)
        shutil.copy2(p, archive)
        if digest(archive) != old[p.name]["sha256"]:
            raise ValueError("Preexisting archive copy mismatch: " + p.name)
        p.chmod(stat.S_IREAD | stat.S_IWRITE)
        p.unlink()
    write_json(output / "preexisting_manifest.json", old)


def capture_synthesis(root, directory):
    """Record the VG and synthesis reports as a coherent, hash-checked snapshot."""
    directory.mkdir(exist_ok=True)
    synth = root / "impl/gwsynthesis"
    vg = synth / (BASE + ".vg")
    before = digest(vg)
    files = {}
    for name in (BASE + ".vg", BASE + "_syn.rpt.html", BASE + ".log", BASE + ".prj"):
        p = synth / name
        if not p.is_file():
            continue
        info = describe(p)
        shutil.copy2(p, directory / name)
        if digest(directory / name) != info["sha256"]:
            raise ValueError("Synthesis artifact changed while copying: " + name)
        files[name] = info
    if before != digest(vg) or files.get(BASE + ".vg", {}).get("sha256") != before:
        raise ValueError("Netlist changed during physical-input capture")
    return files


def parse_pins(cst_path, rpt_path):
    text = re.sub(r"/\*.*?\*/", "", read_text(cst_path), flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    entries = re.findall(r'\bIO_LOC\s+"([^"\n]+)"\s+([A-Z]+\d+)\s*;', text)
    pins = dict(entries)
    issues = []
    if len(entries) != 69 or len(pins) != 69 or len(set(pins.values())) != 69:
        issues.append("Expected exactly 69 distinct ports and 69 distinct balls")
    banned = re.compile(r"(?:^S[0-3]$|^key(?:\[|$)|DBG|matrix|row|col)", re.I)
    forbidden = sorted(port for port in pins if banned.search(port))
    if forbidden:
        issues.append("Removed interface remains in CST: " + ", ".join(forbidden))
    rpt = read_text(rpt_path)
    sections = re.split(r"(?m)^\s*7\.\s+Pinout by Port Name\s*$", rpt)
    section = sections[-1].split("8.", 1)[0] if len(sections) > 1 else ""
    actual = {}
    duplicates = []
    for m in re.finditer(r"^\s*([^|\n]+?)\s*\|\s*[^|\n]*\|\s*([A-Z]+\d+)/\d+\s*\|\s*([YN])\s*\|", section, re.M):
        port = m[1].strip()
        if port in actual:
            duplicates.append(port)
        actual[port] = dict(ball=m[2], locked=m[3])
    if len(actual) != 69 or len({v["ball"] for v in actual.values()}) != 69 or duplicates:
        issues.append("Actual pin report must have exactly 69 unique ports/balls without duplicate rows")
    mismatches = []
    for port, ball in pins.items():
        if actual.get(port) != dict(ball=ball, locked="Y"):
            mismatches.append(dict(port=port, expected_ball=ball, actual=actual.get(port)))
    unexpected = sorted(set(actual) - set(pins))
    if unexpected or mismatches:
        issues.append("Actual pin rows differ from frozen CST or contain unlocked ports")
    report_forbidden = sorted(port for port in actual if banned.search(port))
    if report_forbidden:
        issues.append("Removed interface remains in actual report: " + ", ".join(report_forbidden))
    usage = re.search(r"^\s*I/O Port\s*\|\s*(\d+)/", rpt, re.M)
    if not usage or int(usage[1]) != 69:
        issues.append("PnR I/O Port usage is missing or differs from 69")
    return dict(passed=not issues, expected_count=69, cst_count=len(entries), report_count=len(actual),
                issues=issues, mismatches=mismatches, unexpected_ports=unexpected,
                duplicate_report_ports=duplicates, pins={k: dict(expected_ball=v, actual=actual.get(k)) for k, v in pins.items()})


def adapt_legacy_observation(root, archive, start, old_result, observed, manifest):
    """Translate the old observe_netlist.py evidence without inventing provenance.

    The old observer saved a timestamp and VG hash, but no separate artifact
    hash list. Report hashes below are explicitly computed at reverification.
    Capture is accepted only inside the original tool lifetime, with matching
    source manifests and the exact tool-log netlist path.
    """
    if "captured_during_process" in observed:
        return observed
    result = dict(observed)
    captured = dt.datetime.fromisoformat(observed["observed_utc"])
    beginning = dt.datetime.fromisoformat(start["start_utc"])
    ending = dt.datetime.fromisoformat(old_result["finished_utc"])
    text = read_text(archive / "tool.log")
    paths = re.findall(r'Reading netlist file:\s*"([^"\n]+)"', text)
    expected_vg = root / "impl/gwsynthesis" / (BASE + ".vg")
    path_ok = bool(paths and Path(paths[-1]).resolve() == expected_vg.resolve())
    result["captured_during_process"] = bool(beginning <= captured <= ending and observed.get("capture_timing") == "during physical run")
    matching_sources = normalize_hashes(observed["source_files"]) == normalize_hashes(manifest["source_files"])
    result["input_check_passed"] = matching_sources and path_ok
    result["physical_netlist_path_matches"] = path_ok
    result["files"] = {p.name: describe(p) for p in (archive / "automatic_synthesis").glob(BASE + ".*") if p.is_file()}
    report = archive / "automatic_synthesis" / (BASE + "_syn.rpt.html")
    if report.is_file():
        result["files"][report.name] = describe(report)
    # VG must still equal the hash recorded by the observer at placement time.
    archived_vg = archive / "automatic_synthesis" / (BASE + ".vg")
    result["input_check_passed"] &= archived_vg.is_file() and digest(archived_vg) == observed["netlist_sha256"]
    result["legacy_evidence_adapter"] = dict(adapted_utc=utc(), original_capture_timing=observed.get("capture_timing"),
                                             source_manifests_match=matching_sources,
                                             synthesis_report_hashes_recorded_at="reverification",
                                             netlist_hash_recorded_at="original_observer")
    return result


def load_inspector(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    if not spec or not spec.loader:
        raise ValueError("Cannot load inspector: " + str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.inspect


def timing_review(root, artifact_dir):
    tr = artifact_dir / (BASE + ".tr")
    sdf = artifact_dir / (BASE + ".sdf")
    timing = load_inspector(root / "scripts/inspect_timing.py", "main_physical_timing")(tr)
    body = read_text(tr).split("Note:Core Timing Report")[-1]
    detailed = [float(m[1]) for m in re.finditer(r"^\s*Slack\s*:\s*(-?\d+(?:\.\d+)?)", body, re.M)]
    setup_rows = sum(len(rows) for title, rows in timing["path_tables"].items() if "Setup" in title)
    hold_rows = sum(len(rows) for title, rows in timing["path_tables"].items() if "Hold" in title)
    coverage = {(row["clock"], row["analysis"]) for row in timing["tns"]}
    expected_coverage = {(clock, analysis) for clock in CORE_CLOCKS for analysis in ("setup", "hold")}
    checks = dict(zero_setup_hold=bool(timing.get("setup_hold_pass")),
                  nonempty_setup_hold_tables=bool(setup_rows and hold_rows),
                  tns_covers_all_core_clocks=expected_coverage <= coverage,
                  all_reported_paths_nonnegative=bool(timing.get("all_reported_paths_nonnegative")) and bool(detailed) and min(detailed) >= 0,
                  nonempty_pulse_width_nonnegative=bool(timing["pulse_width_slacks"]) and min(timing["pulse_width_slacks"]) >= 0,
                  internal_margin_at_least_0_5ns=all(timing["internal_wns"].get(clock, -1) >= .5 for clock in CORE_CLOCKS),
                  clocks_not_relaxed=all(abs(timing["fmax"].get(clock, {}).get("target", -1) - mhz) < .0001 for clock, mhz in CORE_CLOCKS.items()))
    timing.update(strict_checks=checks, detailed_slack_count=len(detailed),
                  minimum_detailed_slack=min(detailed) if detailed else None,
                  passed=all(checks.values()))
    try:
        lcd = load_inspector(root / "scripts/check_lcd_clock_timing.py", "main_physical_lcd")(tr, sdf)
    except Exception as e:
        lcd = dict(passed=False, error=repr(e))
    return timing, lcd


def verify(root, artifact_dir, metadata, start, exit_code, expected_files=None):
    """Read-only verification of artifacts; never writes artifact_dir."""
    result = dict(checked_utc=utc(), qualified_bitstream=False, hardware_programmed=False,
                  artifact_directory=str(artifact_dir), checks={}, errors=[], files={})
    checks = result["checks"]
    manifest = metadata["manifest"]
    hashes = normalize_hashes(manifest["source_files"])
    inventory = metadata["inventory"]
    extra = metadata["extra"]
    frozen = check_frozen(root, hashes, inventory, extra)
    result["frozen_inputs"] = frozen
    checks["source_and_extra_inputs_unchanged"] = frozen_pass(frozen)
    checks["complete_manifest_inventory"] = set(inventory) <= set(hashes)
    checks["required_constraints_manifest_complete"] = set(EXTRA[:3]) <= set(extra)
    checks["tool_exit_zero"] = exit_code == 0
    start_time = dt.datetime.fromisoformat(start["start_utc"]).timestamp()
    stale, mismatched, missing = [], [], []
    for p in artifact_paths(artifact_dir):
        if not p.is_file():
            if p.name[len(BASE):] in REQUIRED:
                missing.append(p.name)
            continue
        info = describe(p)
        recorded = (expected_files or {}).get(p.name)
        origin_mtime = recorded.get("source_mtime_ns", recorded.get("mtime_ns")) if recorded else None
        if origin_mtime is None:
            origin_mtime = info["mtime_ns"]
        info["source_mtime_ns"] = origin_mtime
        info["fresh_for_run"] = origin_mtime / 1e9 >= start_time
        if not info["fresh_for_run"]:
            stale.append(p.name)
        if recorded and (info["sha256"] != recorded.get("sha256") or info["bytes"] != recorded.get("bytes")):
            mismatched.append(p.name)
        result["files"][p.name] = info
    result.update(missing_artifacts=missing, stale_artifacts=stale, artifact_hash_mismatches=mismatched)
    checks["required_artifacts_present_nonempty"] = not missing and all(v["bytes"] > 0 for v in result["files"].values())
    checks["artifacts_fresh"] = not stale
    checks["artifact_hashes_match_archive"] = not mismatched
    log = read_text(artifact_dir / "tool.log") + "\n" + read_text(artifact_dir / (BASE + ".log"))
    result["errors"] = re.findall(r"^.*\b(?:ERROR|FATAL)\b.*$", log, re.M | re.I)
    checks["no_tool_errors"] = not result["errors"]
    checks["routing_completed"] = "Placement and routing completed" in log and "Routing Phase 3 completed" in log
    counts = [int(v) for v in re.findall(r"(?:total\s+)?(\d+)\s+unrouted nets", log, re.I)]
    # This Gowin release omits a zero-unrouted line on success. Its PNR-completed
    # plus final routing phase/bitstream completion is its zero-unrouted evidence.
    checks["zero_unrouted_nets"] = all(v == 0 for v in counts) and checks["routing_completed"]
    result["unrouted_nets"] = max(counts) if counts else (0 if checks["zero_unrouted_nets"] else None)
    result["unrouted_evidence"] = "explicit_log_counts" if counts else "Gowin successful full-route completion markers"
    result["tool_log"] = describe(artifact_dir / "tool.log") if (artifact_dir / "tool.log").is_file() else None
    checks["tool_log_present"] = bool(result["tool_log"] and result["tool_log"]["bytes"])
    checks["bitstream_generation_completed"] = "Bitstream generation completed" in log
    checks["power_analysis_completed"] = bool(re.search(r"\[100%\]\s+Power analysis completed", log))
    fs = artifact_dir / (BASE + ".fs")
    with fs.open("rb") if fs.is_file() else open(os.devnull, "rb") as f:
        header = f.read(4096).decode("ascii", errors="replace")
    checks["security_off"] = bool(re.search(r"//SecurityBit:\s+OFF\b", header))
    rpt = artifact_dir / (BASE + ".rpt.txt")
    result["pins"] = parse_pins(root / "src/keyboard.cst", rpt)
    checks["all_69_pins_correct_locked_unique"] = result["pins"]["passed"]
    try:
        result["timing"], result["lcd_clock"] = timing_review(root, artifact_dir)
    except Exception as e:
        result["timing"] = dict(passed=False, error=repr(e))
        result["lcd_clock"] = dict(passed=False, error="Timing/SDF validation incomplete")
    checks["strict_timing_pass"] = result["timing"]["passed"]
    checks["lcd_clock_sdf_pass"] = bool(result["lcd_clock"].get("passed"))
    observed = metadata.get("observed")
    checks["actual_physical_netlist_captured"] = bool(observed and observed.get("captured_during_process") and observed.get("input_check_passed"))
    if observed:
        expected_vg = observed["netlist_sha256"]
        actual_vg = root / "impl/gwsynthesis" / (BASE + ".vg")
        archived_vg = artifact_dir / "automatic_synthesis" / (BASE + ".vg")
        checks["observed_netlist_current_and_archived_match"] = bool(actual_vg.is_file() and archived_vg.is_file() and digest(actual_vg) == expected_vg and digest(archived_vg) == expected_vg)
        synth_files = observed.get("files", {})
        checks["actual_synthesis_reports_captured"] = BASE + "_syn.rpt.html" in synth_files and BASE + ".log" in synth_files
        checks["actual_synthesis_archive_hashes_match"] = all((artifact_dir / "automatic_synthesis" / name).is_file() and digest(artifact_dir / "automatic_synthesis" / name) == info["sha256"] for name, info in synth_files.items())
        result["netlist_sha256"] = expected_vg
        result["launch_netlist_sha256"] = manifest["netlist_sha256"]
        result["tool_autoresynthesis"] = observed.get("tool_autoresynthesis", False)
        if observed.get("legacy_evidence_adapter"):
            result["legacy_evidence_adapter"] = observed["legacy_evidence_adapter"]
    else:
        checks["observed_netlist_current_and_archived_match"] = False
        checks["actual_synthesis_reports_captured"] = False
    rpt_text = read_text(rpt)
    result["resources"] = {}
    for key in ("Logic", "Register", "CLS", "BSRAM", "DSP", "PLL", "PRIMARY", "LW"):
        m = re.search(r"^\s*" + key + r"\s*\|\s*(\d+(?:\.\d+)?)/(\d+)", rpt_text, re.M)
        if m:
            result["resources"][key] = dict(used=float(m[1]), available=int(m[2]))
    elapsed = re.search(r"Total Time and Memory Usage:.*?Elapsed time = ([^,\n]+)", rpt_text, re.S)
    result["tool_elapsed"] = elapsed[1] if elapsed else None
    result["fully_routed"] = bool(checks["tool_exit_zero"] and checks["no_tool_errors"] and checks["routing_completed"] and checks["zero_unrouted_nets"])
    result["final_frozen_inputs"] = check_frozen(root, hashes, inventory, extra)
    checks["source_and_extra_inputs_unchanged"] &= frozen_pass(result["final_frozen_inputs"])
    result["qualified_bitstream"] = all(checks.values())
    result["failed_checks"] = sorted(k for k, value in checks.items() if not value)
    result["status"] = "physical_pass" if result["qualified_bitstream"] else "physical_failed"
    return result


def run(root, output, args, result):
    manifest_path = local_path(root, args.manifest)
    manifest = read_json(manifest_path)
    hashes = normalize_hashes(manifest["source_files"])
    inventory = source_inventory(root)
    missing = sorted(set(inventory) - set(hashes))
    if missing:
        raise ValueError("Synthesis manifest does not cover all src sv/svh/hex + GPRJ: " + repr(missing))
    differences = compare_hashes(root, hashes)
    if differences:
        raise ValueError("Sources differ from synthesis manifest: " + json.dumps(differences))
    vg = root / "impl/gwsynthesis" / (BASE + ".vg")
    if digest(vg) != manifest["netlist_sha256"]:
        raise ValueError("Launch netlist differs from synthesis manifest")
    cst = re.sub(r"/\*.*?\*/|//[^\n]*", "", read_text(root / "src/keyboard.cst"), flags=re.S)
    pin_entries = re.findall(r'\bIO_LOC\s+"([^"\n]+)"\s+([A-Z]+\d+)\s*;', cst)
    if len(pin_entries) != 69 or len(dict(pin_entries)) != 69 or len({ball for _, ball in pin_entries}) != 69:
        raise ValueError("Launch CST must contain exactly 69 unique ports and balls")
    extra = {name: digest(root / name) for name in EXTRA}
    metadata = dict(manifest=manifest, inventory=inventory, extra=extra)
    write_json(output / "netlist_manifest.json", manifest)
    write_json(output / "source_inventory.json", inventory)
    write_json(output / "extra_inputs.json", extra)
    snapshot_inputs(root, output, {**hashes, **extra})
    write_json(output / "launch_synthesis_manifest.json", capture_synthesis(root, output / "launch_synthesis"))
    clean_old_pnr(root, output)
    tool = Path(args.tool).resolve()
    command = [str(tool), str(root / "scripts/build_keyboard.tcl"), "pnr"]
    start = dict(start_utc=utc(), pid=None, command=command, project_root=str(root),
                 profile="default", place_option=3, route_option=2, route_maxfan=23,
                 timeout_seconds=None, netlist_sha256=manifest["netlist_sha256"],
                 driver_sha256=digest(Path(__file__)), manifest_path=str(manifest_path))
    result.update(start_utc=start["start_utc"], command=command, profile="default")
    write_json(output / "start.json", start)
    with (output / "tool.log").open("wb", buffering=0) as log:
        proc = subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT)
        start["pid"] = proc.pid
        result["pid"] = proc.pid
        write_json(output / "start.json", start)
        print("STARTED " + json.dumps(dict(pid=proc.pid, output=str(output))), flush=True)
        attempted = False
        while True:
            text = read_text(output / "tool.log")
            if not attempted and "Reading netlist file:" in text and "Running placement" in text:
                attempted = True
                try:
                    frozen = check_frozen(root, hashes, inventory, extra)
                    files = capture_synthesis(root, output / "automatic_synthesis")
                    read_paths = re.findall(r'Reading netlist file:\s*"([^"\n]+)"', text)
                    path_ok = bool(read_paths and Path(read_paths[-1]).resolve() == vg.resolve())
                    observed = dict(observed_utc=utc(), captured_during_process=proc.poll() is None,
                                    tool_autoresynthesis="GowinSynthesis start" in text,
                                    launch_netlist_sha256=manifest["netlist_sha256"],
                                    netlist_sha256=files[BASE + ".vg"]["sha256"],
                                    actual_netlist_path=read_paths[-1] if read_paths else None,
                                    input_check_passed=frozen_pass(frozen) and path_ok,
                                    frozen_inputs=frozen, physical_netlist_path_matches=path_ok, files=files)
                    metadata["observed"] = observed
                    write_json(output / "observed_netlist_manifest.json", observed)
                    print("CAPTURED " + json.dumps(dict(netlist_sha256=observed["netlist_sha256"], automatic_synthesis=observed["tool_autoresynthesis"], inputs_match=observed["input_check_passed"])), flush=True)
                except Exception as e:
                    write_json(output / "observation_error.json", dict(error=repr(e), traceback=traceback.format_exc(), utc=utc()))
            code = proc.poll()
            if code is not None:
                break
            # Poll interval only: no maximum lifetime and no timeout termination.
            time.sleep(2)
    result["exit_code"] = code
    result["finished_utc"] = utc()
    result["wall_seconds"] = (dt.datetime.fromisoformat(result["finished_utc"]) - dt.datetime.fromisoformat(start["start_utc"])).total_seconds()
    files = {}
    for p in artifact_paths(root / "impl/pnr"):
        if p.is_file():
            files[p.name] = describe(p)
            files[p.name]["source_mtime_ns"] = files[p.name]["mtime_ns"]
            shutil.copy2(p, output / p.name)
            if digest(output / p.name) != files[p.name]["sha256"]:
                raise ValueError("Physical artifact changed while archiving: " + p.name)
    write_json(output / "artifact_manifest.json", files)
    review = verify(root, output, metadata, start, code, files)
    result.update(review)
    # Check again after expensive SDF inspection to detect changes during review.
    end_check = check_frozen(root, hashes, inventory, extra)
    result["final_frozen_inputs"] = end_check
    if not frozen_pass(end_check):
        result["checks"]["source_and_extra_inputs_unchanged"] = False
        result["qualified_bitstream"] = False
        result["status"] = "physical_failed"
        result["failed_checks"] = sorted(k for k, v in result["checks"].items() if not v)
    write_json(output / "verification.json", result)


def reverify(root, output, args, result):
    archive = (root / args.verify_dir).resolve()
    if archive == output or not archive.is_dir():
        raise ValueError("--verify-dir must be an existing different artifact directory")
    manifest = read_json(archive / "netlist_manifest.json")
    inventory_path = archive / "source_inventory.json"
    inventory = read_json(inventory_path) if inventory_path.is_file() else source_inventory(root)
    extra = read_json(archive / "extra_inputs.json")
    metadata = dict(manifest=manifest, inventory=inventory, extra=normalize_hashes(extra))
    old_result = read_json(archive / "result.json") if (archive / "result.json").is_file() else {}
    expected_path = archive / "artifact_manifest.json"
    expected = read_json(expected_path) if expected_path.is_file() else old_result.get("files")
    start = read_json(archive / "start.json")
    observed_path = archive / "observed_netlist_manifest.json"
    if observed_path.is_file():
        metadata["observed"] = adapt_legacy_observation(root, archive, start, old_result, read_json(observed_path), manifest)
        write_json(output / "observed_netlist_manifest_review.json", metadata["observed"])
    if expected and not expected_path.is_file():
        # Old run_closure used copyfile (not copy2), losing original mtimes.
        # Recover provenance only from an unchanged live PNR output whose hash
        # matches the old run's recorded hash; a copied archive's new mtime is
        # never substituted for the EDA file's generation time.
        expected = {name: dict(info) for name, info in expected.items()}
        for name, info in expected.items():
            live = root / "impl/pnr" / name
            if live.is_file() and digest(live) == info.get("sha256"):
                info["source_mtime_ns"] = live.stat().st_mtime_ns
            elif "source_mtime_ns" not in info and "mtime_ns" not in info:
                info["source_mtime_ns"] = 0
        write_json(output / "legacy_artifact_manifest_review.json", expected)
    result.update(mode="verify_only", original_start_utc=start["start_utc"], original_pid=start.get("pid"))
    result.update(verify(root, archive, metadata, start, old_result.get("exit_code"), expected))
    write_json(output / "verification.json", result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="New report directory name, never reused")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--manifest", default=DEFAULT_MANIFEST, help="Project-relative synthesis manifest (run mode)")
    parser.add_argument("--tool", default=DEFAULT_TOOL, help="gw_sh.exe path; used only in run mode")
    parser.add_argument("--verify-dir", type=Path, help="Only recheck an existing archive; never launch EDA")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,100}", args.name) or ".." in args.name:
        parser.error("--name must be a simple new directory name without '..'")
    root = args.root.resolve()
    output = root / "reports/integration_20261101/physical" / args.name
    if output.exists():
        parser.error("Report directory exists; choose a new --name")
    output.mkdir(parents=True)
    result = dict(status="preflight_failed", qualified_bitstream=False, hardware_programmed=False,
                  report_directory=str(output), project_root=str(root), driver_sha256=digest(Path(__file__)),
                  mode="verify_only" if args.verify_dir else "pnr", created_utc=utc(), files={}, errors=[], checks={})
    try:
        if args.verify_dir:
            reverify(root, output, args, result)
        else:
            run(root, output, args, result)
    except BaseException as e:
        result.update(status="interrupted" if isinstance(e, KeyboardInterrupt) else "verification_or_tool_failed",
                      qualified_bitstream=False, exception=repr(e), traceback=traceback.format_exc())
    finally:
        result["reported_utc"] = utc()
        write_json(output / "result.json", result)
    print(json.dumps({k: result.get(k) for k in ("status", "mode", "qualified_bitstream", "hardware_programmed", "wall_seconds", "failed_checks", "exception", "report_directory")}, indent=2), flush=True)
    return 0 if result["qualified_bitstream"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
