### Configure and Run Wandb Sweeps (Hyperparameter Optimization)

Source: https://context7.com/wandb/wandb/llms.txt

Defines a sweep configuration with various parameter types and search strategies, creates a sweep, and then launches an agent to execute the sweep. This enables automated hyperparameter tuning.

```python
import wandb

sweep_config = {
    "method": "bayes",  # "grid", "random", or "bayes"
    "metric": {
        "name": "val/accuracy",
        "goal": "maximize"
    },
    "parameters": {
        "learning_rate": {
            "distribution": "log_uniform_values",
            "min": 1e-5,
            "max": 1e-1
        },
        "batch_size": {
            "values": [16, 32, 64, 128]
        },
        "epochs": {
            "value": 10
        },
        "optimizer": {
            "values": ["adam", "sgd", "rmsprop"]
        }
    },
    "early_terminate": {
        "type": "hyperband",
        "min_iter": 3
    }
}

sweep_id = wandb.sweep(sweep_config, project="sweep-demo")

def train():
    with wandb.init() as run:
        config = run.config

        lr = config.learning_rate
        batch_size = config.batch_size

        for epoch in range(config.epochs):
            accuracy = 0.7 + epoch * 0.02 * (lr * 1000)
            run.log({"val/accuracy": accuracy, "epoch": epoch})

wandb.agent(sweep_id, function=train, count=20)
```

--------------------------------

### Initialize Wandb Run and Log Metrics

Source: https://github.com/wandb/wandb/blob/main/README.md

Initializes a Weights & Biases run, specifying the project name and configuration hyperparameters. It then logs sample metrics like accuracy and loss during the training process. The 'with' statement ensures the run is properly finished, even if errors occur.

```python
import wandb

# Project that the run is recorded to
project = "my-awesome-project"

# Dictionary with hyperparameters
config = {"epochs": 1337, "lr": 3e-4}

# The `with` syntax marks the run as finished upon exiting the `with` block,
# and it marks the run "failed" if there's an exception.
#
# In a notebook, it may be more convenient to write `run = wandb.init()`
# and manually call `run.finish()` instead of using a `with` block.
with wandb.init(project=project, config=config) as run:
    # Training code here

    # Log values to W&B with run.log()
    run.log({"accuracy": 0.9, "loss": 0.1})
```

--------------------------------

### Manage Hyperparameter Configuration with W&B

Source: https://context7.com/wandb/wandb/llms.txt

The `wandb.config` object stores and tracks hyperparameters and settings for your experiment. Values can be set at initialization or updated dynamically during the run.

```python
import wandb

with wandb.init(project="config-demo") as run:
    # Set config at initialization
    run.config.learning_rate = 0.001
    run.config.batch_size = 32

    # Update config with dictionary
    run.config.update({
        "epochs": 100,
        "optimizer": "adam",
        "model": {
            "type": "transformer",
            "layers": 6,
            "hidden_size": 512
        }
    })

    # Access config values
    lr = run.config.learning_rate
    print(f"Training with lr={lr}")

    # Config is also accessible via wandb.config global
    print(wandb.config.batch_size)
```

### Summary

Source: https://context7.com/wandb/wandb/llms.txt

The W&B SDK provides a comprehensive experiment tracking solution for machine learning workflows. The primary use cases include: (1) tracking training metrics and visualizing them in real-time dashboards, (2) versioning datasets and models with artifacts for reproducibility, (3) running hyperparameter sweeps with Bayesian optimization, and (4) collaborating with teams through shared workspaces and reports. The SDK integrates seamlessly with Jupyter notebooks, supports distributed training scenarios, and works in both online and offline modes.

--------------------------------

### Core APIs > wandb.config - Hyperparameter Configuration

Source: https://context7.com/wandb/wandb/llms.txt

The `wandb.config` object stores and tracks hyperparameters and settings for your experiment. You can set configuration values at initialization or update them later using the `update()` method. Config values can be accessed directly as attributes of the `run.config` object or through the global `wandb.config`.
