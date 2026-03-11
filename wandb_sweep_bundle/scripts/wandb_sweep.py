#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import importlib
import json
import os
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

import wandb
import yaml

from wandb_repro import (
    bind_reproducibility_artifacts,
    build_repro_bundle,
    inject_reproducibility_parameters,
    validate_dataset_hash,
    validate_environment_hash,
    validate_git_state,
)

MODEL_ALIASES = {
    "act": "act",
    "diffusion": "diffusion",
    "dp": "diffusion",
    "smolvla": "smolvla",
    "xvla": "xvla",
}

MODEL_CONFIGS = {
    "act": "configs/train_act.yaml",
    "diffusion": "configs/train_dp.yaml",
    "smolvla": "configs/train_smolvla.yaml",
    "xvla": "configs/train_xvla.yaml",
}

MODEL_POLICY_IMPORTS = {
    "act": "lerobot.policies.act.configuration_act",
    "diffusion": "lerobot.policies.diffusion.configuration_diffusion",
    "smolvla": "lerobot.policies.smolvla.configuration_smolvla",
    "xvla": "lerobot.policies.xvla.configuration_xvla",
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
            "policy_optimizer_lr": {
                "arg_name": "policy.optimizer_lr",
                "distribution": "log_uniform_values",
                "min": 5e-6,
                "max": 1e-4,
            },
            "policy_optimizer_weight_decay": {
                "arg_name": "policy.optimizer_weight_decay",
                "values": [0.0, 1e-4, 5e-4],
            },
            "policy_scheduler_warmup_steps": {
                "arg_name": "policy.scheduler_warmup_steps",
                "values": [500, 1000, 2000],
            },
        },
    },
}

RUN_NAME_KEYS = [
    "batch_size",
    "steps",
    "policy_optimizer_lr",
    "policy_optimizer_weight_decay",
    "policy_scheduler_warmup_steps",
    "log_freq",
]

SAFE_KEY_TARGETS = {
    "policy_optimizer_lr": "policy.optimizer_lr",
    "policy_optimizer_weight_decay": "policy.optimizer_weight_decay",
    "policy_scheduler_warmup_steps": "policy.scheduler_warmup_steps",
}


@dataclass
class ParsedTrainArgs:
    cli_args: list[str] = field(default_factory=list)
    manual_overrides: dict[str, Any] = field(default_factory=dict)
    explicit_job_name: str | None = None
    has_output_override: bool = False
    has_resume: bool = False


@dataclass
class RuntimeContext:
    model: str
    project: str
    args: argparse.Namespace
    mapping: dict[str, str]
    repo_root: Path
    base_config_path: Path
    parsed_train_args: ParsedTrainArgs
    repro_cache: dict[str, Any] = field(default_factory=dict)


def ensure_lehome_python_path(repo_root: Path | None = None) -> None:
    resolved_root = repo_root or Path(__file__).resolve().parent.parent
    source_root = resolved_root / "source" / "lehome"
    source_root_str = str(source_root)
    if source_root.is_dir() and source_root_str not in sys.path:
        sys.path.insert(0, source_root_str)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create and run W&B sweeps for LeHome training.")
    parser.add_argument("--model", default="xvla", help="act / diffusion / dp / smolvla / xvla")
    parser.add_argument("--config-file", default=None, help="Optional JSON/YAML sweep spec overlay")
    parser.add_argument(
        "--train-config",
        default=os.environ.get("TRAIN_CONFIG_PATH"),
        help="Optional train config path override. Defaults to the model baseline config.",
    )
    parser.add_argument("--project", default=None, help="W&B project name override")
    parser.add_argument("--entity", default=None, help="W&B entity/team")
    parser.add_argument("--api-key-env", default="WANDB_API_KEY", help="Environment variable holding the W&B API key")
    parser.add_argument("--base-url", default=None, help="Optional W&B server URL, e.g. https://api.wandb.ai")
    parser.add_argument("--count", type=int, default=20, help="Maximum number of runs for the agent")
    parser.add_argument("--method", default="bayes", choices=["bayes", "random", "grid"])
    parser.add_argument("--metric-name", default=None, help="Sweep target metric name")
    parser.add_argument("--metric-goal", default=None, choices=["minimize", "maximize"])
    parser.add_argument("--steps", type=int, default=None, help="Override fixed training steps in the sweep")
    parser.add_argument("--min-iter", type=int, default=3, help="Hyperband minimum iterations")
    parser.add_argument("--name", default=None, help="Sweep display name")
    parser.add_argument("--wandb-mode", default="online", choices=["online", "offline", "disabled"])
    parser.add_argument("--disable-artifact", action="store_true", default=os.environ.get("WANDB_DISABLE_ARTIFACT", "false").lower() in {"1", "true", "yes", "on"}, help="Disable model artifact upload during training")
    parser.add_argument("--job-name", default=None, help="Fixed job name for all sweep runs")
    parser.add_argument("--notes", default=None, help="Optional W&B notes passed to runs")
    parser.add_argument("--train-arg", action="append", default=[], help="Extra argument token forwarded to training config")
    parser.add_argument("--create-only", action="store_true", help="Create the sweep but do not start an agent")
    parser.add_argument("--dry-run", action="store_true", help="Print the generated sweep config and exit")
    parser.add_argument("--print-project", action="store_true", help="Print the resolved W&B project and exit")
    parser.add_argument("--sweep-id", default=None, help="Attach to an existing sweep id instead of creating a new one")
    parser.add_argument(
        "--repro-mode",
        default=os.environ.get("REPRO_MODE", "off"),
        choices=["off", "strict"],
        help="Formal scientific reproducibility mode. strict=freeze code/data/env and validate them on every agent.",
    )
    parser.add_argument(
        "--allow-dirty",
        action="store_true",
        default=os.environ.get("REPRO_ALLOW_DIRTY", "false").lower() in {"1", "true", "yes", "on"},
        help="Allow strict mode to snapshot a dirty working tree. For debugging only; not recommended for formal experiments.",
    )
    return parser.parse_args()




def resolve_workspace_root(bundle_root: Path) -> Path:
    env_root = os.environ.get("LEHOME_WORKSPACE_ROOT")
    candidates: list[Path] = []
    if env_root:
        candidates.append(Path(env_root))
    candidates.extend([Path.cwd(), *Path.cwd().parents, bundle_root, *bundle_root.parents])

    seen: set[str] = set()
    for candidate in candidates:
        resolved = candidate.resolve()
        key = str(resolved)
        if key in seen:
            continue
        seen.add(key)
        if (resolved / "pyproject.toml").exists():
            return resolved

    raise SystemExit(
        "Unable to resolve LEHOME workspace root. Set LEHOME_WORKSPACE_ROOT to the repository root that contains pyproject.toml."
    )

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
    forbidden_keys = {"command", "program"}
    overlap = forbidden_keys.intersection(data)
    if overlap:
        keys = ", ".join(sorted(overlap))
        raise SystemExit(f"Sweep config overlay must not override {keys}; official function-mode sweeps do not use command/program.")
    return data


def normalize_sweep_parameters(raw_parameters: dict[str, Any]) -> tuple[dict[str, Any], dict[str, str]]:
    normalized_parameters: dict[str, Any] = {}
    mappings: dict[str, str] = {}

    for original_name, raw_config in raw_parameters.items():
        if not isinstance(raw_config, dict):
            raise SystemExit(f"Sweep parameter '{original_name}' must map to a config object.")

        config = copy.deepcopy(raw_config)
        metadata_only = bool(config.pop("metadata_only", False))
        target_path = config.pop("arg_name", SAFE_KEY_TARGETS.get(original_name, original_name))
        sweep_name = config.pop("wandb_name", re.sub(r"[^0-9A-Za-z_]+", "_", original_name).strip("_"))
        if not sweep_name:
            raise SystemExit(f"Sweep parameter '{original_name}' resolves to an empty W&B name.")
        if sweep_name in normalized_parameters:
            raise SystemExit(
                f"Sweep parameter '{original_name}' collides with an existing W&B parameter name '{sweep_name}'."
            )

        normalized_parameters[sweep_name] = config
        if not metadata_only:
            mappings[sweep_name] = target_path

    return normalized_parameters, mappings


def build_sweep_config(args: argparse.Namespace) -> tuple[str, dict[str, Any], str, dict[str, str]]:
    model = normalize_model(args.model)
    spec = copy.deepcopy(DEFAULT_SPECS[model])
    if args.config_file:
        spec = deep_merge(spec, load_spec_overlay(args.config_file))
    if args.steps is not None:
        spec.setdefault("parameters", {})["steps"] = {"value": args.steps}

    project = args.project or spec["project"]
    metric_name = args.metric_name or spec["metric"]["name"]
    metric_goal = args.metric_goal or spec["metric"]["goal"]
    normalized_parameters, mappings = normalize_sweep_parameters(spec["parameters"])

    sweep_config: dict[str, Any] = {
        "name": args.name or spec.get("name") or f"{model}-sweep",
        "method": args.method if args.method is not None else spec.get("method", "bayes"),
        "metric": {"name": metric_name, "goal": metric_goal},
        "parameters": normalized_parameters,
    }
    if "early_terminate" in spec:
        sweep_config["early_terminate"] = spec["early_terminate"]
    elif args.min_iter > 0:
        sweep_config["early_terminate"] = {"type": "hyperband", "min_iter": args.min_iter}

    return model, sweep_config, project, mappings


def parse_bool(value: str | bool | None) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return True
    lowered = str(value).strip().lower()
    if lowered in {"1", "true", "yes", "on"}:
        return True
    if lowered in {"0", "false", "no", "off"}:
        return False
    raise SystemExit(f"Invalid boolean value: {value}")


def coerce_scalar(value: str | None) -> Any:
    if value is None:
        return True
    lowered = value.lower()
    if lowered in {"true", "false", "yes", "no", "on", "off", "1", "0"}:
        return parse_bool(lowered)
    if re.fullmatch(r"[-+]?\d+", value):
        return int(value)
    if re.fullmatch(r"[-+]?(?:\d+\.\d*|\d*\.\d+|\d+)(?:[eE][-+]?\d+)?", value):
        return float(value)
    return value


def split_option(tokens: list[str], index: int) -> tuple[str | None, str | None, list[str], int]:
    token = tokens[index]
    if not token.startswith("--"):
        return None, None, [token], index + 1
    if "=" in token:
        name, value = token.split("=", 1)
        return name, value, [token], index + 1
    if index + 1 < len(tokens) and not tokens[index + 1].startswith("--"):
        return token, tokens[index + 1], [token, tokens[index + 1]], index + 2
    return token, None, [token], index + 1


def parse_train_args(tokens: list[str]) -> ParsedTrainArgs:
    parsed = ParsedTrainArgs()
    index = 0
    while index < len(tokens):
        name, value, consumed, next_index = split_option(tokens, index)
        if name is None:
            parsed.cli_args.extend(consumed)
            index = next_index
            continue

        normalized = name[2:]
        if normalized.startswith("policy."):
            if value is None:
                raise SystemExit(f"Policy override requires a value: {name}")
            parsed.manual_overrides[normalized] = coerce_scalar(value)
        else:
            if normalized in {"job_name", "job-name"} and value is not None:
                parsed.explicit_job_name = str(value)
            elif normalized in {"output_dir", "output-dir"}:
                parsed.has_output_override = True
            elif normalized == "resume":
                parsed.has_resume = parse_bool(value)
            parsed.cli_args.extend(consumed)
        index = next_index

    return parsed


def import_model_policy(model: str) -> None:
    importlib.import_module(MODEL_POLICY_IMPORTS[model])


def resolve_train_config_path(repo_root: Path, model: str, explicit_path: str | None) -> Path:
    raw_path = explicit_path or MODEL_CONFIGS[model]
    path = Path(raw_path)
    if not path.is_absolute():
        path = repo_root / path
    return path


def load_train_config(model: str, config_path: str | Path, cli_args: list[str], repo_root: Path | None = None):
    from lerobot.configs.train import TrainPipelineConfig
    from lerobot.utils.import_utils import register_third_party_plugins

    ensure_lehome_python_path(repo_root)
    register_third_party_plugins()
    import_model_policy(model)
    try:
        importlib.import_module("lehome.lerobot_env")
    except ModuleNotFoundError:
        pass
    return TrainPipelineConfig.from_pretrained(str(config_path), cli_args=cli_args)


def set_attr_path(obj: Any, path: str, value: Any) -> None:
    target = obj
    parts = path.split(".")
    for part in parts[:-1]:
        target = getattr(target, part)
    setattr(target, parts[-1], value)


def resolve_unique_output_dir(output_dir: Path | str | None, has_output_override: bool, has_resume: bool) -> Path | None:
    if output_dir is None:
        return None
    path = Path(output_dir)
    if has_output_override or has_resume or not path.exists():
        return path
    suffix = 2
    while True:
        candidate = path.parent / f"{path.name}_{suffix}"
        if not candidate.exists():
            return candidate
        suffix += 1


def format_run_name_value(value: Any) -> str:
    if isinstance(value, float):
        return f"{value:.2e}".replace("+", "")
    return str(value)


def build_run_name(model: str, explicit_name: str | None, sweep_values: dict[str, Any]) -> str:
    if explicit_name:
        return explicit_name
    parts = [model]
    aliases = {
        "batch_size": "bs",
        "steps": "s",
        "log_freq": "log",
        "policy_optimizer_lr": "lr",
        "policy_optimizer_weight_decay": "wd",
        "policy_scheduler_warmup_steps": "warm",
    }
    for key in RUN_NAME_KEYS:
        if key not in sweep_values:
            continue
        parts.append(f"{aliases.get(key, key)}{format_run_name_value(sweep_values[key])}")
    return "_".join(parts)


def collect_sweep_values(run: wandb.sdk.wandb_run.Run, mapping: dict[str, str]) -> dict[str, Any]:
    values: dict[str, Any] = {}
    for sweep_name in mapping:
        if sweep_name in run.config:
            values[sweep_name] = run.config[sweep_name]
    return values


def reproducibility_mode(run: wandb.sdk.wandb_run.Run, args: argparse.Namespace) -> str:
    run_mode = run.config.get("repro_mode")
    if isinstance(run_mode, str) and run_mode:
        return run_mode
    return args.repro_mode


def resolve_repro_artifact_refs(context: RuntimeContext, run: wandb.sdk.wandb_run.Run) -> list[str]:
    setup_run_id = str(run.config['repro_setup_run_id'])
    cache_key = f'repro_setup_artifacts::{setup_run_id}'
    if cache_key in context.repro_cache:
        return context.repro_cache[cache_key]

    api = wandb.Api()
    entity = context.args.entity or wandb.run.entity
    api_run = api.run(f"{entity}/{context.project}/{setup_run_id}")
    refs = [artifact.qualified_name for artifact in api_run.logged_artifacts()]
    context.repro_cache[cache_key] = refs
    return refs


def validate_reproducibility(context: RuntimeContext, run: wandb.sdk.wandb_run.Run, cfg: Any) -> None:
    mode = reproducibility_mode(run, context.args)
    if mode != "strict":
        return

    validate_git_state(
        context.repo_root,
        expected_commit=str(run.config["repro_git_commit"]),
        expected_dirty=parse_bool(run.config["repro_git_dirty"]),
    )

    dataset_cache_key = f"dataset::{run.config['repro_dataset_hash']}"
    if dataset_cache_key not in context.repro_cache:
        context.repro_cache[dataset_cache_key] = validate_dataset_hash(
            context.repo_root,
            cfg.dataset.root,
            expected_hash=str(run.config["repro_dataset_hash"]),
            cache_dir=context.repo_root / ".cache" / "repro" / "dataset",
        )

    env_cache_key = f"env::{run.config['repro_env_hash']}"
    if env_cache_key not in context.repro_cache:
        context.repro_cache[env_cache_key] = validate_environment_hash(
            expected_hash=str(run.config["repro_env_hash"]),
            cache_dir=context.repo_root / ".cache" / "repro" / "environment",
        )

    artifact_refs = resolve_repro_artifact_refs(context, run)
    bind_reproducibility_artifacts(run, artifact_refs)
    run.summary["repro/verified"] = True
    run.summary["repro/git_commit"] = str(run.config["repro_git_commit"])
    run.summary["repro/dataset_hash"] = str(run.config["repro_dataset_hash"])
    run.summary["repro/environment_hash"] = str(run.config["repro_env_hash"])
    run.summary["repro/setup_run_id"] = str(run.config["repro_setup_run_id"])
    run.summary["repro/artifact_count"] = len(artifact_refs)


def prepare_cfg(context: RuntimeContext, run: wandb.sdk.wandb_run.Run):
    cfg = load_train_config(
        context.model,
        context.base_config_path,
        context.parsed_train_args.cli_args,
        repo_root=context.repo_root,
    )
    for path, value in context.parsed_train_args.manual_overrides.items():
        set_attr_path(cfg, path, value)

    sweep_values = collect_sweep_values(run, context.mapping)
    for sweep_name, target_path in context.mapping.items():
        if sweep_name in sweep_values:
            set_attr_path(cfg, target_path, sweep_values[sweep_name])

    explicit_job_name = context.args.job_name or context.parsed_train_args.explicit_job_name
    cfg.job_name = build_run_name(context.model, explicit_job_name, sweep_values)
    cfg.output_dir = resolve_unique_output_dir(
        cfg.output_dir,
        has_output_override=context.parsed_train_args.has_output_override,
        has_resume=context.parsed_train_args.has_resume or bool(cfg.resume),
    )

    cfg.wandb.enable = context.args.wandb_mode != "disabled"
    cfg.wandb.disable_artifact = bool(context.args.disable_artifact or cfg.wandb.disable_artifact)
    cfg.wandb.project = context.project
    cfg.wandb.entity = context.args.entity
    if context.args.notes is not None:
        cfg.wandb.notes = context.args.notes
    cfg.wandb.mode = context.args.wandb_mode
    cfg.wandb.run_id = run.id

    if cfg.output_dir is None:
        now = datetime.now()
        cfg.output_dir = Path("outputs/train") / f"{now:%Y-%m-%d}/{now:%H-%M-%S}_{cfg.job_name}"
        cfg.output_dir = resolve_unique_output_dir(
            cfg.output_dir,
            has_output_override=context.parsed_train_args.has_output_override,
            has_resume=context.parsed_train_args.has_resume or bool(cfg.resume),
        )

    cfg.validate()
    return cfg, sweep_values


def update_run_metadata(run: wandb.sdk.wandb_run.Run, cfg: Any, model: str, sweep_values: dict[str, Any]) -> None:
    run.name = cfg.job_name
    run.config.update({"sweep_model": model}, allow_val_change=True)
    run.config.update(sweep_values, allow_val_change=True)
    run.config.update(cfg.to_dict(), allow_val_change=True)


def train_trial(context: RuntimeContext) -> None:
    cfg_preview = load_train_config(
        context.model,
        context.base_config_path,
        context.parsed_train_args.cli_args,
        repo_root=context.repo_root,
    )
    preview_output_dir = resolve_unique_output_dir(
        cfg_preview.output_dir,
        has_output_override=context.parsed_train_args.has_output_override,
        has_resume=context.parsed_train_args.has_resume or bool(cfg_preview.resume),
    )
    run = wandb.init(
        project=context.project,
        entity=context.args.entity,
        notes=context.args.notes,
        job_type="train",
        dir=str(preview_output_dir or context.repo_root / "wandb"),
        mode=context.args.wandb_mode,
    )
    if run is None:
        raise RuntimeError("wandb.init() returned None; cannot start sweep trial.")

    try:
        cfg, sweep_values = prepare_cfg(context, run)
        validate_reproducibility(context, run, cfg)
        update_run_metadata(run, cfg, context.model, sweep_values)
        print("Resolved official W&B sweep trial:")
        print(
            json.dumps(
                {
                    "run_id": run.id,
                    "run_name": cfg.job_name,
                    "output_dir": str(cfg.output_dir),
                    "project": context.project,
                    "sweep_values": sweep_values,
                    "repro_mode": reproducibility_mode(run, context.args),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        if getattr(cfg.env, "type", None) == "lehome":
            trainer = importlib.import_module("scripts.lerobot_train_lehome")
            trainer.train_with_isaaclab_app(cfg, headless=True)
        else:
            from lerobot.scripts import lerobot_train

            lerobot_train.train(cfg)
    except BaseException:
        import traceback

        traceback.print_exc()
        run.finish(exit_code=1)
        raise
    else:
        run.finish(exit_code=0)


def build_resume_command(args: argparse.Namespace, model: str, sweep_id: str, script_path: str | None = None) -> str:
    script_entry = script_path or "scripts/wandb_sweep.py"
    parts = ["python", script_entry, "--model", model, "--sweep-id", sweep_id]
    if args.config_file:
        parts.extend(["--config-file", args.config_file])
    if args.train_config:
        parts.extend(["--train-config", args.train_config])
    if args.project:
        parts.extend(["--project", args.project])
    if args.entity:
        parts.extend(["--entity", args.entity])
    if args.base_url:
        parts.extend(["--base-url", args.base_url])
    if args.job_name:
        parts.extend(["--job-name", args.job_name])
    if args.notes:
        parts.extend(["--notes", args.notes])
    if args.disable_artifact:
        parts.append("--disable-artifact")
    if args.repro_mode != "off":
        parts.extend(["--repro-mode", args.repro_mode])
    if args.allow_dirty:
        parts.append("--allow-dirty")
    if args.count != 20:
        parts.extend(["--count", str(args.count)])
    return " ".join(parts)


def validate_mode_combinations(args: argparse.Namespace) -> None:
    if args.sweep_id and args.dry_run:
        raise SystemExit("--sweep-id and --dry-run cannot be used together.")
    if args.sweep_id and args.create_only:
        raise SystemExit("--sweep-id and --create-only cannot be used together.")
    if args.sweep_id and args.steps is not None:
        raise SystemExit("--steps only applies when creating a new sweep, not when attaching via --sweep-id.")
    if args.allow_dirty and args.repro_mode != "strict":
        raise SystemExit("--allow-dirty only applies with --repro-mode strict.")


def main() -> int:
    args = parse_args()
    validate_mode_combinations(args)
    model, sweep_config, project, mapping = build_sweep_config(args)
    parsed_train_args = parse_train_args(list(args.train_arg))
    bundle_root = Path(__file__).resolve().parent.parent
    workspace_root = resolve_workspace_root(bundle_root)
    os.chdir(workspace_root)
    train_config_path = resolve_train_config_path(bundle_root, model, args.train_config)

    if args.print_project:
        print(project)
        return 0

    if args.dry_run:
        print(json.dumps(sweep_config, indent=2, ensure_ascii=False))
        return 0

    configure_wandb_api(args)
    context = RuntimeContext(
        model=model,
        project=project,
        args=args,
        mapping=mapping,
        repo_root=workspace_root,
        base_config_path=train_config_path,
        parsed_train_args=parsed_train_args,
    )

    sweep_id = args.sweep_id
    if sweep_id is None:
        if args.repro_mode == "strict":
            cfg_preview = load_train_config(
                model,
                train_config_path,
                parsed_train_args.cli_args,
                repo_root=workspace_root,
            )
            bundle = build_repro_bundle(
                repo_root=workspace_root,
                project=project,
                entity=args.entity,
                model=model,
                dataset_root=cfg_preview.dataset.root,
                sweep_config=sweep_config,
                train_args=list(args.train_arg),
                allow_dirty=args.allow_dirty,
            )
            inject_reproducibility_parameters(sweep_config, bundle)
        sweep_id = wandb.sweep(sweep_config, project=project, entity=args.entity)
        print(f"Created sweep for {model}: {sweep_id}")
        if args.create_only:
            attach_script = str(bundle_root / "bin" / "attach_sweep.sh")
            print(
                f"Resume later with script: {build_resume_command(args, model, sweep_id, script_path=str(bundle_root / 'scripts' / 'wandb_sweep.py'))}"
            )
            print(
                f"Resume later with shell: SWEEP_ID={sweep_id} COUNT={args.count} bash {attach_script}"
            )
            return 0

    wandb.agent(
        sweep_id,
        function=lambda: train_trial(context),
        count=args.count,
        entity=args.entity,
        project=project,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
