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
run controls        "$GODOT" --headless --fixed-fps 60 --path . -s res://tests/test_controls.gd
# The same 5 s ride must end in exactly the same state at any frame rate.
fr_ref=""
for fps in 30 60 144; do
	out="$("$GODOT" --headless --fixed-fps "$fps" --path . -s res://tests/test_framerate.gd 2>&1)"
	st="$(grep -E "^STATE" <<<"$out")"
	if [[ -z "$st" ]] || grep -qE "SCRIPT ERROR|Parse Error" <<<"$out"; then
		echo "FAIL framerate ($fps fps run did not finish)"; sed 's/^/    /' <<<"$out"; failed=1; fr_ref="x"; break
	fi
	if [[ -z "$fr_ref" ]]; then fr_ref="$st"
	elif [[ "$st" != "$fr_ref" ]]; then
		echo "FAIL framerate: 30 fps and $fps fps end differently"; echo "    30:  $fr_ref"; echo "    $fps: $st"; failed=1; fr_ref="x"; break
	fi
done
[[ "$fr_ref" != "x" ]] && echo "PASS test_framerate (identical at 30, 60, 144 fps)"

run wave_parity     "${GPU_PREFIX[@]}" "$GODOT" --rendering-driver opengl3 --path . -s res://tests/test_wave_parity.gd

exit $failed
