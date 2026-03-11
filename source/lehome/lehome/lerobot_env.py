from __future__ import annotations

import importlib
from dataclasses import dataclass, field
from typing import Any, Callable

import gymnasium as gym
import numpy as np
import torch
from gymnasium.envs.registration import register, registry as gym_registry

from lerobot.configs.types import FeatureType, PolicyFeature
from lerobot.envs.configs import EnvConfig
from lerobot.policies.xvla.configuration_xvla import XVLAConfig
from lerobot.utils.constants import ACTION, OBS_IMAGES, OBS_STATE

LEHOME_LEROBOT_GYM_ID = "LeHome-Lerobot-Garment-v0"
DEFAULT_LEHOME_TASK = "LeHome-BiSO101-Direct-Garment-v2"
DEFAULT_TASK_DESCRIPTION = "fold the garment on the table"


def _visual_feature(shape: tuple[int, int, int]) -> PolicyFeature:
    return PolicyFeature(type=FeatureType.VISUAL, shape=shape)


def _state_feature(shape: tuple[int, ...]) -> PolicyFeature:
    return PolicyFeature(type=FeatureType.STATE, shape=shape)


def _action_feature(shape: tuple[int, ...]) -> PolicyFeature:
    return PolicyFeature(type=FeatureType.ACTION, shape=shape)


class LeHomeTaskAdapter(gym.Wrapper):
    def __init__(self, env: gym.Env, task: str, task_description: str):
        super().__init__(env)
        self._task = task
        self._task_description = task_description

    @property
    def task(self) -> str:
        return self._task

    @property
    def task_description(self) -> str:
        return self._task_description

    def reset(self, *, seed: int | None = None, options: dict[str, Any] | None = None):
        observation, info = self.env.reset(seed=seed, options=options)
        return self._normalize_observation(observation), info

    def step(self, action):
        observation, reward, terminated, truncated, info = self.env.step(action)
        return self._normalize_observation(observation), reward, terminated, truncated, info

    @staticmethod
    def _normalize_observation(observation: dict[str, Any]) -> dict[str, Any]:
        normalized: dict[str, Any] = {}
        for key, value in observation.items():
            if isinstance(value, torch.Tensor):
                normalized[key] = value.detach().cpu().numpy()
            else:
                normalized[key] = value
        return normalized


class IdentityProcessor:
    def __call__(self, data):
        return data


@EnvConfig.register_subclass("lehome")
@dataclass
class LeHomeEnvConfig(EnvConfig):
    task: str = DEFAULT_LEHOME_TASK
    task_description: str = DEFAULT_TASK_DESCRIPTION
    garment_name: str = "Top_Long_Unseen_0"
    garment_version: str = "Release"
    garment_cfg_base_path: str = "Assets/objects/Challenge_Garment"
    particle_cfg_path: str = "source/lehome/lehome/tasks/bedroom/config_file/particle_garment_cfg.yaml"
    use_random_seed: bool = False
    random_seed: int = 42
    fps: int = 30
    max_parallel_tasks: int = 1
    disable_env_checker: bool = True
    features: dict[str, PolicyFeature] = field(
        default_factory=lambda: {
            ACTION: _action_feature((12,)),
            OBS_STATE: _state_feature((12,)),
            "top_rgb": _visual_feature((480, 640, 3)),
            "left_rgb": _visual_feature((480, 640, 3)),
            "right_rgb": _visual_feature((480, 640, 3)),
        }
    )
    features_map: dict[str, str] = field(
        default_factory=lambda: {
            ACTION: ACTION,
            OBS_STATE: OBS_STATE,
            "top_rgb": f"{OBS_IMAGES}.top_rgb",
            "left_rgb": f"{OBS_IMAGES}.left_rgb",
            "right_rgb": f"{OBS_IMAGES}.right_rgb",
        }
    )

    @property
    def package_name(self) -> str:
        return "lehome.lerobot_env"

    @property
    def gym_id(self) -> str:
        return LEHOME_LEROBOT_GYM_ID

    @property
    def gym_kwargs(self) -> dict[str, Any]:
        return {"cfg": self}


def _build_base_env_cfg(cfg: LeHomeEnvConfig):
    from lehome.tasks.bedroom.garment_bi_cfg_v2 import GarmentEnvCfg

    base_cfg = GarmentEnvCfg()
    base_cfg.garment_name = cfg.garment_name
    base_cfg.garment_version = cfg.garment_version
    base_cfg.garment_cfg_base_path = cfg.garment_cfg_base_path
    base_cfg.particle_cfg_path = cfg.particle_cfg_path
    base_cfg.use_random_seed = cfg.use_random_seed
    base_cfg.random_seed = cfg.random_seed
    return base_cfg


def make_lehome_lerobot_env(
    cfg: LeHomeEnvConfig,
    render_mode: str | None = None,
    disable_env_checker: bool | None = None,
    **_: Any,
):
    try:
        importlib.import_module("lehome.tasks.bedroom")
    except Exception as exc:  # pragma: no cover - depends on Isaac Sim runtime
        raise RuntimeError(
            "LeHome task import failed. Launch IsaacLab/Isaac Sim before creating env.type=lehome."
        ) from exc

    base_cfg = _build_base_env_cfg(cfg)
    env = gym.make(
        cfg.task,
        cfg=base_cfg,
        render_mode=render_mode,
        disable_env_checker=cfg.disable_env_checker if disable_env_checker is None else disable_env_checker,
    )
    return LeHomeTaskAdapter(env, task=cfg.task, task_description=cfg.task_description)


def register_lehome_gym_env() -> None:
    if LEHOME_LEROBOT_GYM_ID in gym_registry:
        return
    register(
        id=LEHOME_LEROBOT_GYM_ID,
        entry_point="lehome.lerobot_env:make_lehome_lerobot_env",
        disable_env_checker=True,
    )


def preprocess_observation_with_lehome(
    observations: dict[str, Any],
    fallback: Callable[[dict[str, Any]], dict[str, torch.Tensor]],
) -> dict[str, torch.Tensor]:
    if "observation.state" not in observations and not any(
        key.startswith("observation.images.") for key in observations
    ):
        return fallback(observations)

    converted: dict[str, torch.Tensor] = {}

    state = observations.get("observation.state")
    if state is not None:
        state_array = np.asarray(state, dtype=np.float32)
        state_tensor = torch.from_numpy(state_array)
        if state_tensor.dim() == 1:
            state_tensor = state_tensor.unsqueeze(0)
        converted[OBS_STATE] = state_tensor

    for image_key in (
        f"{OBS_IMAGES}.top_rgb",
        f"{OBS_IMAGES}.left_rgb",
        f"{OBS_IMAGES}.right_rgb",
    ):
        if image_key not in observations:
            continue

        image_array = np.asarray(observations[image_key])
        if image_array.dtype != np.uint8:
            image_array = np.clip(image_array, 0, 255).astype(np.uint8)

        image_tensor = torch.from_numpy(image_array)
        if image_tensor.dim() == 3:
            image_tensor = image_tensor.unsqueeze(0)

        if image_tensor.dim() != 4:
            raise ValueError(f"Expected image batch with 4 dims for {image_key}, got {tuple(image_tensor.shape)}")

        if image_tensor.shape[-1] in {3, 4}:
            image_tensor = image_tensor[..., :3].permute(0, 3, 1, 2).contiguous()
        elif image_tensor.shape[1] in {3, 4}:
            image_tensor = image_tensor[:, :3].contiguous()
        else:
            raise ValueError(f"Unsupported image shape for {image_key}: {tuple(image_tensor.shape)}")

        converted[image_key] = image_tensor.to(dtype=torch.float32) / 255.0

    return converted


def make_identity_env_processors(
    env_cfg: EnvConfig,
    policy_cfg: Any,
    fallback: Callable[[EnvConfig, Any], tuple[Any, Any]],
):
    if getattr(env_cfg, "type", None) != "lehome" or not isinstance(policy_cfg, XVLAConfig):
        return fallback(env_cfg, policy_cfg)

    return IdentityProcessor(), IdentityProcessor()


register_lehome_gym_env()
