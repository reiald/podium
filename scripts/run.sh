#!/bin/bash
# Rebuilds and relaunches Podium.
cd "$(dirname "$0")/.."
pkill -x Podium
scripts/build-app.sh && open build/Podium.app
