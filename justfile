set shell := ["bash", "-uc"]

default:
    @just --list

vpn *args:
    bash lehome/allinone.sh vpn {{args}}

prepare *args:
    bash lehome/allinone.sh prepare {{args}}

data *args:
    bash lehome/allinone.sh data {{args}}

setup *args:
    bash lehome/allinone.sh setup {{args}}

train *args:
    bash lehome/train.sh {{args}}

eval *args:
    bash lehome/eval.sh {{args}}

xvla *args:
    bash lehome/xvla.sh {{args}}

wandb *args:
    bash lehome/wandb.sh {{args}}

sweep *args:
    bash lehome/sweep.sh {{args}}

save version:
    bash lehome/allinone.sh save {{version}}
