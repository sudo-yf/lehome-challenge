#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import selectors
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import yaml


SUCCESS_GRACE_SECONDS = float(os.environ.get("LEHOME_SWEEP_SUCCESS_EXIT_GRACE_SECONDS", "15"))
TERMINATE_WAIT_SECONDS = float(os.environ.get("LEHOME_SWEEP_TERMINATE_WAIT_SECONDS", "10"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run one LeHome training trial from W&B sweep parameters.")
    parser.add_argument("--model", required=True, help="Model name passed to run_train.sh")
    parser.add_argument("--mapping-json", required=True, help="JSON mapping from W&B-safe parameter names to CLI arg names")
    parser.add_argument(
        "--sweep-param-path",
        default=None,
        help="Override WANDB_SWEEP_PARAM_PATH for local testing; defaults to env var set by wandb agent",
    )
    parser.add_argument("--train-arg", action="append", default=[], help="Static training args forwarded to run_train.sh")
    parser.add_argument("--print-only", action="store_true", help="Print the resolved command without executing it")
    return parser.parse_args()


def load_sweep_values(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"Sweep parameter file must be a mapping: {path}")

    values: dict[str, Any] = {}
    for key, raw in data.items():
        if key == "wandb_version":
            continue
        if isinstance(raw, dict) and "value" in raw:
            values[key] = raw["value"]
        else:
            values[key] = raw
    return values


def format_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def build_command(repo_root: Path, model: str, mapping: dict[str, str], train_args: list[str], sweep_values: dict[str, Any]) -> list[str]:
    command = ["bash", str(repo_root / "lehome" / "train.sh"), model]
    command.extend(train_args)

    for sweep_name, cli_name in mapping.items():
        if sweep_name not in sweep_values:
            continue
        command.append(f"--{cli_name}={format_value(sweep_values[sweep_name])}")

    return command


ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*m")


def strip_ansi(text: str) -> str:
    return ANSI_ESCAPE_RE.sub("", text)


def parse_output_dir(line: str) -> Path | None:
    plain_line = strip_ansi(line)
    prefix = "Output dir:"
    if prefix not in plain_line:
        return None
    value = plain_line.split(prefix, 1)[1].strip()
    return Path(value) if value else None


def coerce_steps(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def expected_checkpoint_dir(output_dir: Path, step_count: int) -> Path:
    return output_dir / "checkpoints" / f"{step_count:06d}"


def has_success_artifacts(repo_root: Path, output_dir: Path | None, step_count: int | None) -> bool:
    if output_dir is None or step_count is None:
        return False

    resolved_output_dir = output_dir if output_dir.is_absolute() else repo_root / output_dir
    checkpoint_dir = expected_checkpoint_dir(resolved_output_dir, step_count)
    config_path = checkpoint_dir / "pretrained_model" / "config.json"
    training_step_path = checkpoint_dir / "training_state" / "training_step.json"
    if not config_path.exists() or not training_step_path.exists():
        return False

    try:
        payload = json.loads(training_step_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return False
    return int(payload.get("step", -1)) >= step_count


def terminate_process_group(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return

    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return

    deadline = time.time() + TERMINATE_WAIT_SECONDS
    while time.time() < deadline:
        if process.poll() is not None:
            return
        time.sleep(0.5)

    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    process.wait(timeout=5)


def stream_command(repo_root: Path, command: list[str], step_count: int | None) -> int:
    process = subprocess.Popen(
        command,
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        preexec_fn=os.setsid,
    )

    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)

    output_dir: Path | None = None
    saw_end_of_training_at: float | None = None

    while True:
        events = selector.select(timeout=1.0)
        if events:
            for key, _ in events:
                line = key.fileobj.readline()
                if not line:
                    continue
                sys.stdout.write(line)
                sys.stdout.flush()

                parsed_output_dir = parse_output_dir(line)
                if parsed_output_dir is not None:
                    output_dir = parsed_output_dir
                if "End of training" in line and saw_end_of_training_at is None:
                    saw_end_of_training_at = time.time()

        return_code = process.poll()
        if return_code is not None:
            selector.unregister(process.stdout)
            process.stdout.close()
            return return_code

        if saw_end_of_training_at is None:
            continue

        grace_elapsed = time.time() - saw_end_of_training_at
        if grace_elapsed < SUCCESS_GRACE_SECONDS:
            continue

        if not has_success_artifacts(repo_root, output_dir, step_count):
            continue

        print(
            "Detected successful training artifacts after 'End of training', but process is still exiting; "
            "terminating the lingering process group.",
            flush=True,
        )
        terminate_process_group(process)
        selector.unregister(process.stdout)
        process.stdout.close()
        return 0


def main() -> int:
    args = parse_args()
    mapping = json.loads(args.mapping_json)
    if not isinstance(mapping, dict):
        raise SystemExit("--mapping-json must decode to an object.")

    param_path_str = args.sweep_param_path or os.environ.get("WANDB_SWEEP_PARAM_PATH")
    if not param_path_str:
        raise SystemExit("WANDB_SWEEP_PARAM_PATH is not set. This script is intended to run under wandb agent.")

    param_path = Path(param_path_str)
    if not param_path.exists():
        raise SystemExit(f"Sweep parameter file not found: {param_path}")

    repo_root = Path(__file__).resolve().parent.parent
    sweep_values = load_sweep_values(param_path)
    command = build_command(repo_root, args.model, mapping, list(args.train_arg), sweep_values)
    step_count = coerce_steps(sweep_values.get("steps"))

    print("Resolved sweep train command:")
    print(" ".join(command))

    if args.print_only:
        return 0

    return stream_command(repo_root, command, step_count)


if __name__ == "__main__":
    raise SystemExit(main())
