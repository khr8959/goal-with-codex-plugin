#!/bin/bash
# Backward-compatible wrapper.
# goal-dual v2 is no longer a full self-driving loop. It delegates one Codex
# implementation step, then returns a compact evidence packet for Claude /goal.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/delegate-step.sh" "$@"
