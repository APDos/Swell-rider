#!/usr/bin/env bash
# Runs every test. Usage: tests/run_tests.sh   (from anywhere)
# Needs godot (4.3+) on PATH, or GODOT=/path/to/godot. The GPU parity test
# also needs xvfb-run unless a display is already available.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# A test that hits a script error never reaches quit() and would hang, so every
# run gets a time limit.
TIMEOUT="${TEST_TIMEOUT:-180}"
# macOS has no GNU timeout; use gtimeout (brew coreutils) or a perl fallback.
if ! command -v timeout >/dev/null; then
	if command -v gtimeout >/dev/null; then timeout() { gtimeout "$@"; }
	else timeout() { perl -e '$t=shift; $p=fork; if(!$p){exec @ARGV} $SIG{ALRM}=sub{kill "TERM",$p; exit 124}; alarm $t; waitpid $p,0; exit($?>>8)' "$@"; }
	fi
fi

if [[ -n "${DISPLAY:-}" ]]; then GPU_PREFIX=(); else GPU_PREFIX=(xvfb-run -a); fi

failed=0
run() {
	local name="$1"; shift
	local out status
	out="$(timeout "$TIMEOUT" "$@" 2>&1)"; status=$?
	[[ $status -eq 124 ]] && out+=$'\n'"(timed out after ${TIMEOUT}s)"
	# Godot keeps going after a script error, so check the log as well as the exit code.
	if [[ $status -ne 0 ]] || grep -qE "SCRIPT ERROR|Parse Error|SHADER ERROR|Failed to compile" <<<"$out"; then
		echo "FAIL $name"
		grep -vE "^ALSA lib|audio|V-Sync|set_use_vsync|status < 0|mesh_get_surface_count|Parameter \"m\" is null" <<<"$out" | sed 's/^/    /'
		failed=1
	else
		grep -E "^PASS" <<<"$out" || echo "PASS $name"
	fi
}

run import          "$GODOT" --headless --path . --import
run wave_model      "$GODOT" --headless --path . -s res://tests/test_wave_model.gd
run smoke           "$GODOT" --headless --fixed-fps 60 --path . -s res://tests/test_smoke.gd
run controls        "$GODOT" --headless --fixed-fps 60 --path . -s res://tests/test_controls.gd
run pump            "$GODOT" --headless --fixed-fps 60 --path . -s res://tests/test_pump.gd
# The same 5 s ride must end in exactly the same state at any frame rate.
fr_ref=""
for fps in 30 60 144; do
	out="$(timeout "$TIMEOUT" "$GODOT" --headless --fixed-fps "$fps" --path . -s res://tests/test_framerate.gd 2>&1)"
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

run wave_parity     ${GPU_PREFIX[@]+"${GPU_PREFIX[@]}"} "$GODOT" --rendering-driver opengl3 --path . -s res://tests/test_wave_parity.gd

exit $failed
