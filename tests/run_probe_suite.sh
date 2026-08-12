#!/usr/bin/env bash
# Suite driver: run inside the container as `bash /src/tests/run_probe_suite.sh`,
# or from a CI checkout as `bash tests/run_probe_suite.sh` (path-relative).
# Keep this file free of bare "anx" text that run_tests.sh's pkill -f targets;
# pkill -x matches comm names only, so it is safe here.
pkill -x anx
pkill -x anx-old-binary
sleep 0.3
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_tests.sh"