#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import random
import wandb


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Lightweight W&B online preflight for LeHome sweep entrypoints.")
    parser.add_argument("--project", required=True, help="W&B project to validate against")
    parser.add_argument("--entity", default=None, help="Optional W&B entity/team")
    parser.add_argument("--api-key-env", default="WANDB_API_KEY", help="Environment variable holding the W&B API key")
    parser.add_argument("--base-url", default=None, help="Optional W&B server URL")
    parser.add_argument("--name", default="wandb-preflight", help="Run name")
    parser.add_argument("--notes", default=None, help="Optional run notes")
    parser.add_argument("--model", default="xvla", help="Model label stored in run config")
    parser.add_argument("--log-steps", type=int, default=3, help="How many tiny heartbeat steps to log")
    return parser.parse_args()


def configure_wandb_api(args: argparse.Namespace) -> None:
    if args.base_url:
        os.environ["WANDB_BASE_URL"] = args.base_url

    api_key = os.getenv(args.api_key_env)
    if api_key:
        wandb.login(key=api_key, relogin=True)


def log_heartbeat(run: wandb.sdk.wandb_run.Run, steps: int) -> None:
    offset = random.random() / 10
    for step in range(1, steps + 1):
        run.log(
            {
                "preflight/heartbeat": step,
                "preflight/loss": 1.0 / (step + 1) + offset,
                "preflight/acc": 1.0 - 1.0 / (step + 1) - offset,
            },
            step=step,
        )


def main() -> int:
    args = parse_args()
    configure_wandb_api(args)

    run = wandb.init(
        entity=args.entity,
        project=args.project,
        name=args.name,
        notes=args.notes,
        job_type="preflight",
        config={
            "kind": "sweep_preflight",
            "model": args.model,
            "log_steps": args.log_steps,
        },
    )
    try:
        log_heartbeat(run, args.log_steps)
        print(f"RUN_URL={run.url}")
        print(f"RUN_ID={run.id}")
        print(f"PROJECT={args.project}")
        print(f"ENTITY={args.entity or ''}")
    finally:
        run.finish()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
