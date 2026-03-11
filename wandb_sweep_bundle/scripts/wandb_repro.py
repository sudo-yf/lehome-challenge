#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.metadata
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import wandb


EXCLUDED_CODE_PATHS = {
    '.git',
    '.venv',
    '.cache',
    'outputs',
    'wandb',
    'logs',
    'bak',
    '__pycache__',
}


@dataclass
class DatasetManifest:
    root: str
    hash: str
    file_count: int
    total_size: int
    manifest_path: Path


@dataclass
class EnvironmentManifest:
    hash: str
    manifest_path: Path


@dataclass
class ReproBundle:
    git_commit: str
    git_dirty: bool
    code_snapshot_path: Path
    dataset_manifest: DatasetManifest
    environment_manifest: EnvironmentManifest
    setup_run_url: str
    setup_run_id: str
    code_artifact_ref: str
    dataset_artifact_ref: str
    environment_artifact_ref: str
    sweep_manifest_artifact_ref: str


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def stable_json_dumps(payload: Any) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)


def sha256_bytes(data: bytes) -> str:
    digest = hashlib.sha256()
    digest.update(data)
    return digest.hexdigest()


def sha256_file(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def run_text(cmd: list[str], cwd: Path | None = None, allow_failure: bool = False) -> str:
    try:
        return subprocess.check_output(cmd, cwd=str(cwd) if cwd else None, text=True).strip()
    except subprocess.CalledProcessError:
        if allow_failure:
            return ''
        raise


def current_git_commit(repo_root: Path) -> str:
    return run_text(['git', 'rev-parse', 'HEAD'], cwd=repo_root)


def current_git_status(repo_root: Path) -> str:
    return run_text(['git', 'status', '--short'], cwd=repo_root, allow_failure=False)


def is_git_dirty(repo_root: Path) -> bool:
    return bool(current_git_status(repo_root).strip())


def dataset_root_path(repo_root: Path, dataset_root: str | Path) -> Path:
    path = Path(dataset_root)
    if not path.is_absolute():
        path = repo_root / path
    return path.resolve()


def build_dataset_manifest(repo_root: Path, dataset_root: str | Path, out_dir: Path) -> DatasetManifest:
    root = dataset_root_path(repo_root, dataset_root)
    if not root.exists():
        raise SystemExit(f'Dataset root does not exist: {root}')

    files: list[dict[str, Any]] = []
    total_size = 0
    digest = hashlib.sha256()
    for path in sorted(p for p in root.rglob('*') if p.is_file()):
        rel = path.relative_to(root).as_posix()
        file_hash = sha256_file(path)
        size = path.stat().st_size
        total_size += size
        files.append({'path': rel, 'size': size, 'sha256': file_hash})
        digest.update(rel.encode('utf-8'))
        digest.update(b'\0')
        digest.update(str(size).encode('utf-8'))
        digest.update(b'\0')
        digest.update(file_hash.encode('utf-8'))
        digest.update(b'\n')

    manifest = {
        'generated_at': utc_now(),
        'root': str(root),
        'file_count': len(files),
        'total_size': total_size,
        'aggregate_sha256': digest.hexdigest(),
        'files': files,
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = out_dir / 'dataset_manifest.json'
    manifest_path.write_text(stable_json_dumps(manifest) + '\n', encoding='utf-8')
    return DatasetManifest(
        root=str(root),
        hash=manifest['aggregate_sha256'],
        file_count=len(files),
        total_size=total_size,
        manifest_path=manifest_path,
    )


def gather_pip_freeze() -> list[str]:
    packages = []
    for dist in importlib.metadata.distributions():
        name = dist.metadata.get('Name') or dist.metadata.get('Summary') or dist.name
        version = dist.version
        packages.append(f"{name}=={version}")
    return sorted(set(packages))


def gather_nvidia_snapshot() -> str:
    if shutil.which('nvidia-smi') is None:
        return ''
    return run_text(
        [
            'nvidia-smi',
            '--query-gpu=name,driver_version,memory.total',
            '--format=csv,noheader',
        ],
        allow_failure=True,
    )


def build_environment_manifest(out_dir: Path) -> EnvironmentManifest:
    fingerprint_payload = {
        'python_executable': sys.executable,
        'python_version': sys.version,
        'platform': platform.platform(),
        'uname': list(platform.uname()),
        'cwd': os.getcwd(),
        'env': {
            key: os.environ.get(key)
            for key in [
                'CUDA_VISIBLE_DEVICES',
                'HF_HUB_OFFLINE',
                'TRANSFORMERS_OFFLINE',
                'WANDB_BASE_URL',
                'WANDB_MODE',
            ]
            if os.environ.get(key) is not None
        },
        'pip_freeze': gather_pip_freeze(),
        'nvidia_smi': gather_nvidia_snapshot(),
    }
    fingerprint = sha256_bytes(stable_json_dumps(fingerprint_payload).encode('utf-8'))
    payload = {
        'generated_at': utc_now(),
        **fingerprint_payload,
        'aggregate_sha256': fingerprint,
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = out_dir / 'environment_manifest.json'
    manifest_path.write_text(stable_json_dumps(payload) + '\n', encoding='utf-8')
    return EnvironmentManifest(hash=fingerprint, manifest_path=manifest_path)


def create_code_snapshot(repo_root: Path, out_dir: Path, allow_dirty: bool) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    snapshot_path = out_dir / 'code_snapshot.tar.gz'
    if not allow_dirty:
        subprocess.check_call(['git', 'archive', '--format=tar.gz', '-o', str(snapshot_path), 'HEAD'], cwd=repo_root)
        return snapshot_path

    tracked = run_text(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
        cwd=repo_root,
        allow_failure=False,
    )
    paths = [Path(item) for item in tracked.split('\0') if item]
    with tarfile.open(snapshot_path, 'w:gz') as tar:
        for rel in sorted(paths):
            if set(rel.parts).intersection(EXCLUDED_CODE_PATHS):
                continue
            path = repo_root / rel
            if not path.exists():
                continue
            tar.add(path, arcname=rel.as_posix(), recursive=False)
    return snapshot_path


def artifact_ref(artifact: wandb.Artifact) -> str:
    qualified_name = getattr(artifact, 'qualified_name', None)
    if qualified_name:
        return qualified_name
    return f"{artifact.entity}/{artifact.project}/{artifact.name}"


def log_file_artifact(run: wandb.sdk.wandb_run.Run, name: str, artifact_type: str, file_path: Path, alias_payload: dict[str, Any] | None = None) -> str:
    artifact = wandb.Artifact(name, type=artifact_type, metadata=alias_payload or {})
    artifact.add_file(str(file_path), name=file_path.name)
    logged = run.log_artifact(artifact)
    logged.wait()
    return artifact_ref(logged)


def build_repro_bundle(
    *,
    repo_root: Path,
    project: str,
    entity: str | None,
    model: str,
    dataset_root: str | Path,
    sweep_config: dict[str, Any],
    train_args: list[str],
    allow_dirty: bool,
) -> ReproBundle:
    git_commit = current_git_commit(repo_root)
    git_dirty = is_git_dirty(repo_root)
    if git_dirty and not allow_dirty:
        raise SystemExit('Strict reproducibility mode requires a clean git working tree. Commit or stash local changes first.')

    tmp_root = Path(os.environ.get('TMPDIR', '/tmp'))
    tmp_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='lehome_repro_', dir=tmp_root) as temp_dir:
        temp_root = Path(temp_dir)
        code_dir = temp_root / 'code'
        dataset_dir = temp_root / 'dataset'
        env_dir = temp_root / 'env'
        sweep_dir = temp_root / 'sweep'

        code_snapshot_path = create_code_snapshot(repo_root, code_dir, allow_dirty=allow_dirty)
        dataset_manifest = build_dataset_manifest(repo_root, dataset_root, dataset_dir)
        environment_manifest = build_environment_manifest(env_dir)

        sweep_manifest = {
            'generated_at': utc_now(),
            'model': model,
            'project': project,
            'entity': entity,
            'git_commit': git_commit,
            'git_dirty': git_dirty,
            'dataset_root': dataset_manifest.root,
            'dataset_hash': dataset_manifest.hash,
            'environment_hash': environment_manifest.hash,
            'train_args': train_args,
            'sweep_config': sweep_config,
        }
        sweep_dir.mkdir(parents=True, exist_ok=True)
        sweep_manifest_path = sweep_dir / 'sweep_manifest.json'
        sweep_manifest_path.write_text(stable_json_dumps(sweep_manifest) + '\n', encoding='utf-8')

        run = wandb.init(
            project=project,
            entity=entity,
            job_type='repro_setup',
            name=f'{model}-repro-setup-{git_commit[:8]}',
            config={
                'repro_mode': 'strict',
                'git_commit': git_commit,
                'git_dirty': git_dirty,
                'dataset_root': dataset_manifest.root,
                'dataset_hash': dataset_manifest.hash,
                'environment_hash': environment_manifest.hash,
            },
        )
        if run is None:
            raise RuntimeError('Failed to initialize W&B repro setup run.')
        try:
            code_ref = log_file_artifact(
                run,
                name=f'{model}-code-{git_commit[:8]}',
                artifact_type='code-snapshot',
                file_path=code_snapshot_path,
                alias_payload={'git_commit': git_commit, 'git_dirty': git_dirty},
            )
            dataset_ref = log_file_artifact(
                run,
                name=f'{model}-dataset-manifest-{dataset_manifest.hash[:12]}',
                artifact_type='dataset-manifest',
                file_path=dataset_manifest.manifest_path,
                alias_payload={'dataset_root': dataset_manifest.root, 'dataset_hash': dataset_manifest.hash},
            )
            environment_ref = log_file_artifact(
                run,
                name=f'{model}-environment-manifest-{environment_manifest.hash[:12]}',
                artifact_type='environment-manifest',
                file_path=environment_manifest.manifest_path,
                alias_payload={'environment_hash': environment_manifest.hash},
            )
            sweep_ref = log_file_artifact(
                run,
                name=f'{model}-sweep-manifest-{git_commit[:8]}-{dataset_manifest.hash[:8]}',
                artifact_type='sweep-manifest',
                file_path=sweep_manifest_path,
                alias_payload={'git_commit': git_commit, 'dataset_hash': dataset_manifest.hash, 'environment_hash': environment_manifest.hash},
            )
            setup_run_url = run.url
            setup_run_id = run.id
        finally:
            run.finish()

    return ReproBundle(
        git_commit=git_commit,
        git_dirty=git_dirty,
        code_snapshot_path=Path(code_snapshot_path.name),
        dataset_manifest=dataset_manifest,
        environment_manifest=environment_manifest,
        setup_run_url=setup_run_url,
        setup_run_id=setup_run_id,
        code_artifact_ref=code_ref,
        dataset_artifact_ref=dataset_ref,
        environment_artifact_ref=environment_ref,
        sweep_manifest_artifact_ref=sweep_ref,
    )


def inject_reproducibility_parameters(sweep_config: dict[str, Any], bundle: ReproBundle) -> None:
    params = sweep_config.setdefault('parameters', {})
    params.update(
        {
            'repro_mode': {'value': 'strict'},
            'repro_git_commit': {'value': bundle.git_commit},
            'repro_git_dirty': {'value': bundle.git_dirty},
            'repro_dataset_hash': {'value': bundle.dataset_manifest.hash},
            'repro_env_hash': {'value': bundle.environment_manifest.hash},
            'repro_setup_run_id': {'value': bundle.setup_run_id},
        }
    )


def validate_git_state(repo_root: Path, expected_commit: str, expected_dirty: bool) -> None:
    current_commit = current_git_commit(repo_root)
    current_dirty = is_git_dirty(repo_root)
    if current_commit != expected_commit:
        raise SystemExit(
            f'Reproducibility check failed: git commit mismatch. expected={expected_commit} current={current_commit}'
        )
    if not expected_dirty and current_dirty:
        raise SystemExit('Reproducibility check failed: working tree is dirty but sweep expects a clean repository.')


def validate_dataset_hash(repo_root: Path, dataset_root: str | Path, expected_hash: str, cache_dir: Path) -> DatasetManifest:
    manifest = build_dataset_manifest(repo_root, dataset_root, cache_dir)
    if manifest.hash != expected_hash:
        raise SystemExit(
            'Reproducibility check failed: dataset hash mismatch. '
            f'expected={expected_hash} current={manifest.hash}'
        )
    return manifest


def validate_environment_hash(expected_hash: str, cache_dir: Path) -> EnvironmentManifest:
    manifest = build_environment_manifest(cache_dir)
    if manifest.hash != expected_hash:
        raise SystemExit(
            'Reproducibility check failed: environment hash mismatch. '
            f'expected={expected_hash} current={manifest.hash}'
        )
    return manifest


def bind_reproducibility_artifacts(run: wandb.sdk.wandb_run.Run, artifact_refs: list[str]) -> None:
    for ref in artifact_refs:
        run.use_artifact(ref)
