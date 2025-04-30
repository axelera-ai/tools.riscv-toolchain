#!/bin/bash

set -ex

(type -p wget >/dev/null || (apt update && apt-get install wget -y)) \
  && mkdir -p -m 755 /etc/apt/keyrings \
  && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt-key adv --fetch-keys https://apt.kitware.com/keys/kitware-archive-latest.asc
DISTRO_CODENAME=$(lsb_release -cs)
apt-add-repository "deb https://apt.kitware.com/ubuntu/ $DISTRO_CODENAME main"
apt-get update && \
apt-get install -y \
    autoconf \
    automake \
    autotools-dev \
    curl \
    python3 \
    python-is-python3 \
    python3-pip \
    libmpc-dev \
    gawk \
    build-essential \
    bison \
    flex \
    texinfo \
    gperf \
    libtool \
    patchutils \
    bc \
    zlib1g-dev \
    libexpat-dev \
    ninja-build \
    git \
    libglib2.0-dev \
    libslirp-dev \
    fakeroot \
    gh \
    cmake \
    libncurses-dev
