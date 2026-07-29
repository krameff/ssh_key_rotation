#!/bin/bash
set -euo pipefail

# Pre-create root's ansible remote_tmp dir before handing off to the real container command
# (systemd via /usr/sbin/init). This runs synchronously before the container is reported as
# started, so it can never race the first ansible connection's own mkdir of this same path.
install -d -m 0700 /root/.ansible/tmp

exec "$@"
