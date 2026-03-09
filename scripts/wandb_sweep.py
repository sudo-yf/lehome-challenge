#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import json
import os
import re
from pathlib import Path
from typing import Any

import wandb
import yaml


MODEL_ALIASES = {
    "act": "act",
    "diffusion": "diffusion",
    "dp": "diffusion",
    "smolvla": "smolvla",
    "xvla": "xvla",
}


DEFAULT_SPECS: dict[str, dict[str, Any]] = {
    "act": {
        "project": "lehome_act_sweep",
        "metric": {"name": "train/loss", "goal": "minimize"},
        "parameters": {
            "batch_size": {"values": [8, 16, 32]},
            "steps": {"value": 30000},
            "log_freq": {"values": [200, 500, 1000]},
        },
    },
    "diffusion": {
        "project": "lehome_diffusion_sweep",
        "metric": {"name": "train/loss", "goal": "minimize"},
        "parameters": {
            "batch_size": {"values": [8, 16, 32]},
            "steps": {"value": 30000},
            "log_freq": {"values": [200, 500, 1000]},
        },
    },
    "smolvla": {
        "project": "lehome_smolvla_sweep",
        "metric": {"name": "train/loss", "goal": "minimize"},
        "parameters": {
            "batch_size": {"values": [16, 32]},
            "steps": {"value": 30000},
            "log_freq": {"values": [200, 500, 1000]},
        },
    },
    "xvla": {
        "project": "lehome_xvla_sweep",
        "metric": {"name": "train/loss", "goal": "minimize"},
        "parameters": {
            "batch_size": {"values": [4, 8]},
            "steps": {"value": 30000},
            "policy.optimizer_lr": {
                "distribution": "log_uniform_values",
                "min": 5e-6,
                "max": 1e-4,
            },
            "policy.optimizer_weight_decay": {"values": [0.0, 1e-4, 5e-4]},
            "policy.scheduler_warmup_steps": {"values": [500, 1000, 2000]},
        },
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create and run W&B sweeps for LeHome training.")
    parser.add_argument("--model", default="xvla", help="act / diffusion / dp / smolvla / xvla")
    parser.add_argument("--config-file", default=None, help="Optional JSON/YAML sweep spec overlay")
    parser.add_argument("--project", default=None, help="W&B project name override")
    parser.add_argument("--entity", default=None, help="W&B entity/team")
    parser.add_argument("--api-key-env", default="WANDB_API_KEY", help="Environment variable holding the W&B API key")
    parser.add_argument("--base-url", default=None, help="Optional W&B server URL, e.g. https://api.wandb.ai")
    parser.add_argument("--count", type=int, default=20, help="Maximum number of runs for the agent")
    parser.add_argument("--method", default="bayes", choices=["bayes", "random", "grid"])
    parser.add_argument("--metric-name", default=None, help="Sweep target metric name")
    parser.add_argument(
        "--metric-goal",
        default=None,
        choices=["minimize", "maximize"],
        help="Sweep target optimization goal",
    )
    parser.add_argument("--steps", type=int, default=None, help="Override fixed training steps in the sweep")
    parser.add_argument("--min-iter", type=int, default=3, help="Hyperband minimum iterations")
    parser.add_argument("--name", default=None, help="Sweep display name")
    parser.add_argument(
        "--wandb-mode",
        default="online",
        choices=["online", "offline", "disabled"],
        help="Training-side wandb mode passed to lerobot-train",
    )
    parser.add_argument("--disable-artifact", action="store_true", help="Pass --wandb.disable_artifact=true to training")
    parser.add_argument("--job-name", default=None, help="Override lerobot train job_name for all sweep runs")
    parser.add_argument("--notes", default=None, help="Optional W&B notes passed to training")
    parser.add_argument(
        "--train-arg",
        action="append",
        default=[],
        help="Extra argument forwarded to lehome/train.sh; may be repeated",
    )
    parser.add_argument("--create-only", action="store_true", help="Create the sweep but do not start an agent")
    parser.add_argument("--dry-run", action="store_true", help="Print the generated sweep config and exit")
    parser.add_argument("--print-project", action="store_true", help="Print the resolved W&B project and exit")
    return parser.parse_args()


def configure_wandb_api(args: argparse.Namespace) -> None:
    if args.base_url:
        os.environ["WANDB_BASE_URL"] = args.base_url

    api_key = os.getenv(args.api_key_env)
    if api_key:
        wandb.login(key=api_key, relogin=True)


def normalize_model(model: str) -> str:
    try:
        return MODEL_ALIASES[model.lower()]
    except KeyError as exc:
        raise SystemExit(f"Unsupported model: {model}. Choose from act / diffusion / dp / smolvla / xvla.") from exc


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    for key, value in override.items():
        if key == "parameters" and isinstance(base.get(key), dict) and isinstance(value, dict):
            for param_name, param_config in value.items():
                base[key][param_name] = copy.deepcopy(param_config)
            continue
        if isinstance(base.get(key), dict) and isinstance(value, dict):
            deep_merge(base[key], value)
        else:
            base[key] = value
    return base


def load_spec_overlay(path_str: str) -> dict[str, Any]:
    path = Path(path_str)
    if not path.exists():
        raise SystemExit(f"Sweep config file not found: {path}")

    with path.open("r", encoding="utf-8") as handle:
        if path.suffix.lower() in {".yaml", ".yml"}:
            data = yaml.safe_load(handle)
        elif path.suffix.lower() == ".json":
            data = json.load(handle)
        else:
            raise SystemExit(f"Unsupported sweep config extension: {path.suffix}. Use .json / .yaml / .yml")

    if not isinstance(data, dict):
        raise SystemExit(f"Sweep config overlay must be a mapping: {path}")
    if "command" in data or "program" in data:
        raise SystemExit("Sweep config overlay must not override program/command; use --train-arg for repo-specific train args.")
    return data




def normalize_sweep_parameters(raw_parameters: dict[str, Any]) -> tuple[dict[str, Any], list[tuple[str, str]]]:
    normalized_parameters: dict[str, Any] = {}
    cli_mappings: list[tuple[str, str]] = []

    for original_name, raw_config in raw_parameters.items():
        if not isinstance(raw_config, dict):
            raise SystemExit(f"Sweep parameter '{original_name}' must map to a config object.")

        config = copy.deepcopy(raw_config)
        cli_arg = config.pop("arg_name", original_name)
        sweep_name = config.pop("wandb_name", re.sub(r"[^0-9A-Za-z_]+", "_", original_name).strip("_"))
        if not sweep_name:
            raise SystemExit(f"Sweep parameter '{original_name}' resolves to an empty W&B name.")
        if sweep_name in normalized_parameters:
            raise SystemExit(
                f"Sweep parameter '{original_name}' collides with an existing W&B parameter name '{sweep_name}'."
            )

        normalized_parameters[sweep_name] = config
        cli_mappings.append((sweep_name, cli_arg))

    return normalized_parameters, cli_mappings

def build_sweep_config(args: argparse.Namespace) -> tuple[str, dict[str, Any], str | None]:
    model = normalize_model(args.model)
    spec = copy.deepcopy(DEFAULT_SPECS[model])
    if args.config_file:
        spec = deep_merge(spec, load_spec_overlay(args.config_file))
    if args.steps is not None:
        spec.setdefault("parameters", {})["steps"] = {"value": args.steps}

    project = args.project or spec["project"]
    metric_name = args.metric_name or spec["metric"]["name"]
    metric_goal = args.metric_goal or spec["metric"]["goal"]
    normalized_parameters, cli_mappings = normalize_sweep_parameters(spec["parameters"])

    command = [
        "bash",
        "lehome/train.sh",
        model,
        "--wandb.enable=true",
        f"--wandb.mode={args.wandb_mode}",
        f"--wandb.project={project}",
    ]
    if args.entity:
        command.append(f"--wandb.entity={args.entity}")
    if args.disable_artifact:
        command.append("--wandb.disable_artifact=true")
    if args.notes:
        command.append(f"--wandb.notes={args.notes}")
    if args.job_name:
        command.append(f"--job_name={args.job_name}")
    command.extend(args.train_arg)
    for sweep_name, cli_arg in cli_mappings:
        command.append(f"--{cli_arg}=${{{sweep_name}}}")

    sweep_config: dict[str, Any] = {
        "name": args.name or spec.get("name") or f"{model}-sweep",
        "method": args.method if args.method is not None else spec.get("method", "bayes"),
        "metric": {"name": metric_name, "goal": metric_goal},
        "parameters": normalized_parameters,
        "program": "lehome/train.sh",
        "command": command,
    }

    if "early_terminate" in spec:
        sweep_config["early_terminate"] = spec["early_terminate"]
    elif args.min_iter > 0:
        sweep_config["early_terminate"] = {"type": "hyperband", "min_iter": args.min_iter}

    return model, sweep_config, project


def main() -> int:
    args = parse_args()
    model, sweep_config, project = build_sweep_config(args)

    if args.print_project:
        print(project)
        return 0

    if args.dry_run:
        print(json.dumps(sweep_config, indent=2, ensure_ascii=False))
        return 0

    configure_wandb_api(args)
    sweep_id = wandb.sweep(sweep_config, project=project, entity=args.entity)
    print(f"Created sweep for {model}: {sweep_id}")

    if args.create_only:
        print(f"Start later with: wandb agent {sweep_id}")
        return 0

    wandb.agent(sweep_id, count=args.count, entity=args.entity, project=project)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
