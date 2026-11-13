#!/usr/bin/env bash
# Runs every test. Usage: tests/run_tests.sh   (from anywhere)
# Needs godot (4.3+) on PATH, or GODOT=/path/to/godot. The GPU parity test
# also needs xvfb-run unless a display is already available.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

if [[ -n "${DISPLAY:-}" ]]; then GPU_PREFIX=(); else GPU_PREFIX=(xvfb-run -a); fi

failed=0
run() {
	local name="$1"; shift
	local out status
	out="$("$@" 2>&1)"; status=$?
	# Godot keeps going after a script error, so check the log as well as the exit code.
	if [[ $status -ne 0 ]] || grep -qE "SCRIPT ERROR|Parse Error|SHADER ERROR|Failed to compile" <<<"$out"; then
		echo "FAIL $name"
		grep -vE "^ALSA lib|audio|V-Sync|set_use_vsync|status < 0" <<<"$out" | sed 's/^/    /'
		failed=1
	else
		grep -E "^PASS" <<<"$out" || echo "PASS $name"
	fi
}

run import          "$GODOT" --headless --path . --import
run wave_model      "$GODOT" --headless --path . -s res://tests/test_wave_model.gd
run smoke           "$GODOT" --headless --fixed-fps 60 --path . -s res://tests/test_smoke.gd
run wave_parity     "${GPU_PREFIX[@]}" "$GODOT" --rendering-driver opengl3 --path . -s res://tests/test_wave_parity.gd

exit $failed
