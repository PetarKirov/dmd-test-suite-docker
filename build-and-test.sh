#!/bin/bash

set -euxo pipefail

# Clone dmd, druntime and phobos:
for repo in dmd druntime phobos; do
    git clone https://github.com/dlang/$repo.git --depth=1
    pushd $repo
    echo "Cloned '${repo}' at commit: '`git rev-parse HEAD`'"
    popd
done

# Use DMD_STABLE to build dmd master:
source ~/dlang/dmd-${DMD_STABLE_VERSION}/activate
cd ./dmd && make -f posix.mak -j8 DMD=dmd
deactivate

# Build druntime and phobos:
cd ../druntime && make -f posix.mak -j8
cd ../phobos && make -f posix.mak -j8

# Run dmd's test suite:
cd ../dmd && make -f posix.mak test
