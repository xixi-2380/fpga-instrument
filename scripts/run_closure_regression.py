"""Reproduce the targeted 2026-11-01 timing-structure comparisons.

Requires Icarus Verilog. Does not run Gowin or program hardware. For the
complete core comparison use run_envelope_precalc_tests.py --suite core.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def trace_hash(path):
    """Compare the complete observable trace, ignoring only its date header."""
    digest = hashlib.sha256()
    skip = False
    with path.open("rb") as stream:
        for line in stream:
            if line.startswith(b"$date"):
                skip = True
            if skip:
                if b"$end" in line:
                    skip = False
                continue
            digest.update(line)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path)
    parser.add_argument("--tool-bin", type=Path)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--suite", choices=["all", "dds", "limiter-width", "aip"], default="all")
    parser.add_argument("--keep-traces", action="store_true", help="Retain the large VCD files after comparison")
    args = parser.parse_args()
    test_root = Path(__file__).resolve().parents[1]
    root = (args.root or test_root).resolve()
    out = args.out_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    suffix = ".exe" if os.name == "nt" else ""
    if args.tool_bin:
        tool_bin = args.tool_bin.resolve()
        env["PATH"] = str(tool_bin) + os.pathsep + env.get("PATH", "")
        iv, vv = [str(tool_bin / (name + suffix)) for name in ["iverilog", "vvp"]]
    else:
        iv, vv = [shutil.which(name) for name in ["iverilog", "vvp"]]
    if not iv or not vv:
        parser.error("Icarus Verilog and vvp are required; supply --tool-bin if needed")
    results = []

    def save():
        (out / "validation.json").write_text(json.dumps(dict(
            tests=results,
            total_checks=sum(test.get("checks", 0) for test in results),
            hardware_programmed=False,
            sta_passed=False,
        ), indent=2) + "\n", encoding="utf-8")

    def run(stem, top, files, parameters=None, definitions=None, extra_tops=None, plusargs=None):
        before = {str(path): sha(path) for path in files}
        # ROM files are runtime inputs, so include them in the input manifest.
        before.update({str(path): sha(path) for path in (root / "src/rom").glob("*.hex")})
        started = time.monotonic()
        binary = out / (stem + ".vvp")
        command = [iv, "-g2012", "-grelative-include", "-I" + (root / "src").as_posix(),
                   "-I" + (test_root / "sim").as_posix(), "-s", top, "-o", binary.as_posix()]
        for name in extra_tops or []:
            command += ["-s", name]
        command += ["-P" + top + "." + key + "=" + str(value) for key, value in (parameters or {}).items()]
        command += ["-D" + key + "=" + value for key, value in (definitions or {}).items()]
        command += [path.as_posix() for path in files]
        compilation = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True, encoding="utf-8")
        (out / (stem + "_compile.log")).write_text(compilation.stdout + compilation.stderr, encoding="utf-8")
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        execution = subprocess.run([vv, binary.as_posix()] + (plusargs or []), cwd=root, env=env,
                                   capture_output=True, text=True, encoding="utf-8", timeout=900)
        log = execution.stdout + execution.stderr
        (out / (stem + ".log")).write_text(log, encoding="utf-8")
        if execution.returncode or "PASS " + top not in log or "FAIL" in log:
            raise RuntimeError(log)
        if not all(sha(Path(name)) == digest for name, digest in before.items()):
            raise RuntimeError("Inputs changed during simulation")
        match = re.search(r"checks=(\d+)", log)
        item = dict(name=stem, passed=True, checks=int(match[1]) if match else 0,
                    parameters=parameters or {}, seconds=round(time.monotonic() - started, 3),
                    source_sha256=before, compile_command=command, output=log)
        results.append(item)
        save()
        print(next(line for line in log.splitlines() if line.startswith("PASS ")), flush=True)
        return item

    try:
        if args.suite in ["all", "dds"]:
            files = [root / "src/dds_sine.sv", test_root / "sim/reference_dds_sine_c6352fa.sv",
                     test_root / "sim/structural/tb_dds_context_equivalence.sv"]
            for voices in [1, 32]:
                run("dds_voices" + str(voices), "tb_dds_context_equivalence", files, dict(VOICES=voices))
        if args.suite in ["all", "limiter-width"]:
            files = [root / "src/audio_limiter.sv", test_root / "sim/reference_audio_limiter_c6352fa.sv",
                     test_root / "sim/structural/tb_limiter_width_equivalence.sv"]
            configs = [dict(PRE_GAIN=g, WINDOW_LOG2=2, FIXED=0, HOLD=0) for g in range(1, 33)]
            configs += [dict(PRE_GAIN=24, WINDOW_LOG2=6, FIXED=1, HOLD=240),
                        dict(PRE_GAIN=32, WINDOW_LOG2=6, FIXED=1, HOLD=0)]
            for config in configs:
                run("limiter_" + "_".join(str(v) for v in config.values()),
                    "tb_limiter_width_equivalence", files, config)
        if args.suite in ["all", "aip"]:
            fields = ["keys", "online", "report", "fault", "cfg_ready", "cfg_done", "cfg_error",
                      "data_valid", "applied_config", "observed_config", "diagnostic", "scl", "sda"]
            files = [root / "src/aip5916_keyboard.sv", root / "src/i2c_register_master.sv",
                     test_root / "sim/reference_aip5916_keyboard_close.sv"]
            for top, params in [("tb_aip5916_keyboard", dict(HALF=4)),
                                ("tb_aip5916_keyboard", dict(HALF=8)), ("tb_pcb_keyboard_runtime", {})]:
                stem = top + "".join("_" + key + str(value) for key, value in params.items())
                source = (test_root / "sim" / (top + ".sv")).read_text(encoding="utf-8")
                if source.count("aip5916_keyboard #(") != 1:
                    raise RuntimeError("Expected one AiP5916 DUT in " + top)
                bench = out / (stem + ".sv")
                bench.write_text(source.replace("aip5916_keyboard #(", "`AIP_DUT #(", 1), encoding="utf-8")
                observer = out / (stem + "_trace.sv")
                observer.write_text('module trace_observer; reg [8191:0] file; initial begin '
                                    'if(!$value$plusargs("TRACE=%s",file))$fatal(1,"missing TRACE");'
                                    '$dumpfile(file);$dumpvars(0,' +
                                    ",".join(top + ".dut." + name for name in fields) +
                                    ');end endmodule\n', encoding="utf-8")
                pair = []
                for mode, module in [("reference", "reference_aip5916_keyboard_close"),
                                     ("candidate", "aip5916_keyboard")]:
                    trace = out / (stem + "_" + mode + ".vcd")
                    item = run(stem + "_" + mode, top, files + [bench, observer], params,
                               dict(AIP_DUT=module), ["trace_observer"], ["+TRACE=" + trace.as_posix()])
                    item["trace_sha256_without_date"] = trace_hash(trace)
                    pair.append((item, trace))
                equal = pair[0][0]["trace_sha256_without_date"] == pair[1][0]["trace_sha256_without_date"]
                for item, _ in pair:
                    item["observable_traces_identical"] = equal
                save()
                if not equal:
                    raise RuntimeError("Observable VCD traces differ: " + stem)
                if not args.keep_traces:
                    for _, trace in pair:
                        trace.unlink()
    finally:
        save()


if __name__ == "__main__":
    main()
