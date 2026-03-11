#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent


def ensure_lehome_python_path(repo_root: Path | None = None) -> None:
    resolved_root = repo_root or REPO_ROOT
    source_root = resolved_root / "source" / "lehome"
    source_root_str = str(source_root)
    if source_root.is_dir() and source_root_str not in sys.path:
        sys.path.insert(0, source_root_str)


def load_train_config(config_path: str | Path, cli_args: list[str]):
    ensure_lehome_python_path()
    from lerobot.configs.train import TrainPipelineConfig
    from lerobot.utils.import_utils import register_third_party_plugins

    register_third_party_plugins()
    importlib.import_module("lerobot.policies.xvla.configuration_xvla")
    importlib.import_module("lehome.lerobot_env")
    return TrainPipelineConfig.from_pretrained(str(config_path), cli_args=cli_args)


def train_with_isaaclab_app(cfg: Any, headless: bool = True) -> None:
    ensure_lehome_python_path()

    # Add project root to sys.path for scripts.utils import
    if str(REPO_ROOT) not in sys.path:
        sys.path.insert(0, str(REPO_ROOT))

    from isaaclab.app import AppLauncher

    launcher_parser = argparse.ArgumentParser(add_help=False)
    AppLauncher.add_app_launcher_args(launcher_parser)
    launcher_args = launcher_parser.parse_args([])
    if hasattr(launcher_args, "headless"):
        launcher_args.headless = headless

    from scripts.utils.common import close_app, launch_app_from_args

    simulation_app = launch_app_from_args(launcher_args)
    original_preprocess = None
    original_make_env_pre_post_processors = None

    try:
        importlib.import_module("lehome.tasks.bedroom")
        lehome_lerobot_env = importlib.import_module("lehome.lerobot_env")

        from lerobot.envs import utils as env_utils
        from lerobot.scripts import lerobot_eval, lerobot_train

        original_preprocess = env_utils.preprocess_observation

        def patched_preprocess(observations):
            return lehome_lerobot_env.preprocess_observation_with_lehome(
                observations,
                fallback=original_preprocess,
            )

        env_utils.preprocess_observation = patched_preprocess
        lerobot_eval.preprocess_observation = patched_preprocess

        original_make_env_pre_post_processors = lerobot_train.make_env_pre_post_processors

        def patched_make_env_pre_post_processors(env_cfg, policy_cfg):
            return lehome_lerobot_env.make_identity_env_processors(
                env_cfg,
                policy_cfg,
                fallback=original_make_env_pre_post_processors,
            )

        lerobot_train.make_env_pre_post_processors = patched_make_env_pre_post_processors
        lerobot_train.train(cfg)
    finally:
        if original_preprocess is not None:
            from lerobot.envs import utils as env_utils
            from lerobot.scripts import lerobot_eval

            env_utils.preprocess_observation = original_preprocess
            lerobot_eval.preprocess_observation = original_preprocess

        if original_make_env_pre_post_processors is not None:
            from lerobot.scripts import lerobot_train

            lerobot_train.make_env_pre_post_processors = original_make_env_pre_post_processors

        close_app(simulation_app)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train XVLA with IsaacLab-aware LeHome eval support.")
    parser.add_argument("--config-path", required=True, help="Path to the LeRobot train config file.")
    parser.add_argument(
        "--train-arg",
        action="append",
        default=[],
        help="Extra CLI override token forwarded to TrainPipelineConfig.",
    )
    parser.add_argument(
        "--headless",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Launch IsaacLab headlessly. Disable only for local debugging.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    cfg = load_train_config(args.config_path, list(args.train_arg))
    train_with_isaaclab_app(cfg, headless=args.headless)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
