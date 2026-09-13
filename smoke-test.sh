#!/usr/bin/env bash
#
# Installs one Sluice package the way a user would get it, launches it, and says what happened.
#
# This is the half of verification a developer machine cannot do. A build on the release machine
# proves the package was produced. It cannot prove that the operating system accepts it, that the
# installer puts the launchers where the app expects them, or that a first launch survives the
# signature and quarantine checks a real download goes through.
#
# Every check runs, and the failures are counted rather than thrown. A rig that stops at its first
# red step answers one question per dispatch, and a macOS dispatch takes long enough that the
# difference matters.
#
# Usage: smoke-test.sh <machine> <package-dir> <expected-version> <heic fixture>

set -uo pipefail

MACHINE="${1:?machine}"
# Absolute, because apt reads an argument as a package name unless it starts with a slash or a dot.
# A relative "package/sluice_0.1.0_amd64.deb" is parsed as the pkg/release form instead, and apt
# then reports "Unable to locate package package", naming a package nobody asked for.
PKGDIR="$(cd "${2:?package directory}" && pwd)"
EXPECTED_VERSION="${3:?expected version}"
HEIC="${4:?heic fixture}"

FAILURES=0

# Named rather than numbered, because the summary at the bottom is what a reader scrolls to and a
# list of numbers says nothing there.
fail() {
  echo "FAIL: $*"
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "ok: $*"
}

section() {
  echo
  echo "=== $* ==="
}

# Runs a command, prints both streams, and holds the caller to the exit code AND to an empty error
# stream. The phase's own acceptance for the command line is that nothing leaks to stderr, since a
# GUI-declared build on Windows silences one launcher and a framework report on the other stream
# once put 9,648 bytes in front of a reader.
run_quiet() {
  local label="$1"; shift
  local out err status
  out="$(mktemp)"; err="$(mktemp)"
  "$@" > "$out" 2> "$err"
  status=$?
  echo "--- $label stdout"
  cat "$out"
  echo "--- $label stderr"
  cat "$err"
  if [ "$status" -ne 0 ]; then
    fail "$label exited $status"
  elif [ -s "$err" ]; then
    fail "$label wrote $(wc -c < "$err") bytes to stderr"
  else
    pass "$label exited 0 with an empty error stream"
  fi
  LAST_STDOUT="$out"
}

section "environment"
echo "machine: $MACHINE"
echo "expecting version: $EXPECTED_VERSION"
uname -a || ver
ls -l "$PKGDIR"

# ---------------------------------------------------------------------------------------------
# Install
#
# Each machine gets the artifact a user would actually download, not the loose directory the build
# also produces. The zip is what the download page offers on Windows as the portable option, but
# the MSIX is what the update channel runs through, so that is the one installed here.
# ---------------------------------------------------------------------------------------------
section "install"

case "$MACHINE" in
  mac.*)
    ARCH="${MACHINE#mac.}"
    ZIP="$(find "$PKGDIR" -name "sluice-*-mac-${ARCH}.zip" -print -quit)"
    [ -n "$ZIP" ] || { fail "no mac ${ARCH} zip in $PKGDIR"; exit 1; }

    # Quarantine is set before unpacking and read after, because that is the order a browser does
    # it in. The attribute rides on the archive and ditto carries it onto everything it writes.
    # Plain unzip drops it, which would test an app macOS treats as locally built.
    xattr -w com.apple.quarantine "0083;00000000;Safari;00000000-0000-0000-0000-000000000000" "$ZIP"
    sudo ditto -x -k "$ZIP" /Applications
    APP=/Applications/Sluice.app
    [ -d "$APP" ] || { fail "no $APP after unpacking $ZIP"; exit 1; }

    if xattr -p com.apple.quarantine "$APP" > /dev/null 2>&1; then
      pass "the installed bundle carries the quarantine attribute"
    else
      fail "the quarantine attribute did not survive onto $APP, so Gatekeeper below is not being asked the real question"
    fi

    CLI="$APP/Contents/MacOS/sluice"
    GUI_LAUNCH=(open -a "$APP")
    GUI_MATCH="Sluice.app"
    ;;

  windows.amd64)
    MSIX="$(find "$PKGDIR" -name "sluice-*.x64.msix" -print -quit)"
    [ -n "$MSIX" ] || { fail "no msix in $PKGDIR"; exit 1; }
    powershell -NoProfile -Command "Add-AppxPackage -Path '$(cygpath -w "$MSIX")'" || fail "Add-AppxPackage refused the package"

    # An installed MSIX reaches the command line through an execution alias on PATH rather than
    # through a path anybody can compute. Resolving it here means a missing alias reads as a
    # missing alias instead of as a launcher that would not start.
    CLI="$(command -v sluice || true)"
    [ -n "$CLI" ] || { fail "no sluice on PATH after Add-AppxPackage, so the execution alias was not registered"; exit 1; }
    pass "the command line alias resolved to $CLI"
    GUI_LAUNCH=(powershell -NoProfile -Command "Start-Process SluiceDesktop")
    GUI_MATCH="SluiceDesktop"

    # The portable zip holds the same bytes the MSIX does, unpacked somewhere with ordinary
    # permissions. Windows locks the installed package's own directory to the app's identity, so a
    # shell cannot run anything out of it however correct the file is.
    PORTABLE="$(find "$PKGDIR" -name "sluice-*-windows-amd64.zip" -print -quit)"
    if [ -n "$PORTABLE" ]; then
      mkdir -p "$PKGDIR/portable"
      unzip -q -o "$PORTABLE" -d "$PKGDIR/portable"
    fi
    ;;

  linux.amd64)
    DEB="$(find "$PKGDIR" -name "sluice_*_amd64.deb" -print -quit)"
    [ -n "$DEB" ] || { fail "no deb in $PKGDIR"; exit 1; }
    sudo apt-get update
    sudo apt-get install -y "$DEB" || fail "apt refused the package"
    CLI="$(command -v sluice || true)"
    [ -n "$CLI" ] || { fail "no sluice on PATH after installing $DEB"; exit 1; }
    pass "the command line launcher resolved to $CLI"

    # Taken out of the desktop entry rather than assumed, because that entry is the only way in a
    # Linux user has. Nothing puts the window's launcher on PATH, so a name guessed here would test
    # a route nobody can take.
    ENTRY=/usr/share/applications/photos.sluice.desktop
    if [ -f "$ENTRY" ]; then
      EXEC_LINE="$(grep -m1 '^Exec=' "$ENTRY" | cut -d= -f2-)"
      pass "the desktop entry launches $EXEC_LINE"
    else
      fail "no desktop entry at $ENTRY, so the app has no menu item"
      EXEC_LINE=/usr/lib/sluice/bin/SluiceDesktop
    fi
    # No display on the runner, so the window opens against a virtual one. Without this the launch
    # below fails on the display rather than on anything about the package.
    GUI_LAUNCH=(xvfb-run -a "$EXEC_LINE")
    GUI_MATCH="/usr/lib/sluice/bin/"
    ;;

  *)
    echo "unknown machine $MACHINE" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------------------------
# What the operating system makes of the signature
#
# macOS is the only one with a command that answers this directly. Windows decided it at
# Add-AppxPackage, which refuses an untrusted package outright, and Debian packages carry no
# signature of their own.
# ---------------------------------------------------------------------------------------------
case "$MACHINE" in
  mac.*)
    section "gatekeeper"
    if spctl --assess --type execute --verbose=4 "$APP"; then
      pass "Gatekeeper accepts the bundle"
    else
      fail "Gatekeeper rejected the bundle, which is what a user would see as a refusal to open it"
    fi
    codesign --verify --deep --strict --verbose=2 "$APP" \
      && pass "the signature verifies through every nested binary" \
      || fail "codesign found a broken or unsigned nested binary"
    # The staple is what lets a machine with no network open the app. Notarization succeeding at
    # build time says nothing about whether the ticket reached the artifact that shipped.
    xcrun stapler validate "$APP" \
      && pass "the notarization ticket is stapled" \
      || fail "no stapled ticket, so an offline first launch would go to Apple and fail"
    ;;
esac

# ---------------------------------------------------------------------------------------------
# First launch
# ---------------------------------------------------------------------------------------------
section "command line launcher"

run_quiet "sluice --help" "$CLI" --help
# Exit 0 and a clean error stream are both satisfied by a launcher that prints nothing at all, and
# printing nothing is the failure this surface is most exposed to. A Windows executable declares in
# its header whether it is a console program, and a GUI declaration silences everything it writes.
if grep -q "sift" "$LAST_STDOUT" && grep -q "app" "$LAST_STDOUT"; then
  pass "the help names the verbs, so the console launcher is not silenced"
else
  fail "the help did not name the verbs, so nothing reached the terminal"
fi

run_quiet "sluice --version" "$CLI" --version
if [ -n "${LAST_STDOUT:-}" ]; then
  REPORTED="$(tr -d '\r' < "$LAST_STDOUT" | head -1)"
  if [ "$REPORTED" = "Sluice $EXPECTED_VERSION" ]; then
    pass "the build reports itself as $EXPECTED_VERSION"
  else
    fail "the build reports itself as \"$REPORTED\", not \"Sluice $EXPECTED_VERSION\""
  fi
fi

section "bundled decoder"
# Reached through the installed tree rather than the build directory, because the question is
# whether the binaries survived packaging, signing and installation with the name the app invokes.
#
# Each of the three is `app.dir` with heif/bin under it, and each installer puts `app.dir` somewhere
# else: the jars sit loose in Resources on macOS, under app/ beside the launchers on Windows, and
# under lib/app/ on Linux. Written out per machine rather than searched for, so a decoder that
# shipped to the wrong place reads as a failure instead of being found anyway.
case "$MACHINE" in
  mac.*)       DECODER="$APP/Contents/Resources/heif/bin/heif-convert" ;;
  windows.*)   DECODER="$(dirname "$(readlink -f "$CLI")")/../app/heif/bin/heif-convert.exe" ;;
  linux.*)     DECODER="$(dirname "$(readlink -f "$CLI")")/../lib/app/heif/bin/heif-convert" ;;
esac
if [ -e "$DECODER" ]; then
  pass "the decoder shipped to $DECODER, which is where the app looks"
else
  fail "no bundled decoder at $DECODER"
fi

# Windows runs it out of the portable copy, since the installed one sits behind the package's own
# permissions and no shell may execute it. Same bytes, so the answer is about the binary rather
# than about where it was read from.
case "$MACHINE" in
  windows.*) RUNNABLE="$PKGDIR/portable/app/heif/bin/heif-convert.exe" ;;
  *)         RUNNABLE="$DECODER" ;;
esac
if [ -e "$RUNNABLE" ]; then
  if "$RUNNABLE" --version; then
    pass "the bundled decoder runs and links against its own libraries"
    # Starting and decoding are different claims. Starting says the libraries load. Decoding says
    # the codecs inside them survived being signed, notarized and installed, which is the step no
    # build machine performs.
    # The tool numbers its output when the file holds more than one image, so what it writes is
    # decoded.png or decoded-1.png. Globbing for both means a multi-image fixture cannot read as a
    # failure to decode.
    rm -f "$PKGDIR"/decoded*.png
    "$RUNNABLE" "$HEIC" "$PKGDIR/decoded.png" || true
    WRITTEN="$(find "$PKGDIR" -name 'decoded*.png' -size +0c | head -1)"
    if [ -n "$WRITTEN" ]; then
      pass "the bundled decoder read a real HEIC and wrote $(wc -c < "$WRITTEN") bytes of PNG"
    else
      fail "the bundled decoder started but could not read a HEIC"
    fi
  else
    fail "the bundled decoder will not run, so no HEIC or AVIF can be read"
  fi
else
  fail "nothing runnable at $RUNNABLE"
fi

section "window launcher"
# Alive after this long counts as launched. A JavaFX startup failure exits in under a second, and
# the toolkit needs a few to put a window up on a cold machine.
#
# Windows gets its own pair of commands rather than pgrep and pkill, which git bash does not carry.
# The bash ones are on the runner's PATH there and answer about nothing, so a check written once
# for all three would pass on Windows by finding no process and reading that as no failure.
"${GUI_LAUNCH[@]}" &
GUI_PID=$!
sleep 20
case "$MACHINE" in
  windows.*)
    ALIVE=(powershell -NoProfile -Command "if (Get-Process $GUI_MATCH -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }")
    STOP=(powershell -NoProfile -Command "Stop-Process -Name $GUI_MATCH -Force -ErrorAction SilentlyContinue")
    ;;
  *)
    ALIVE=(pgrep -f "$GUI_MATCH")
    STOP=(pkill -f "$GUI_MATCH")
    ;;
esac
if "${ALIVE[@]}" > /dev/null 2>&1; then
  pass "the window launcher was still running after 20 seconds"
else
  fail "the window launcher was gone within 20 seconds, so it did not get a window up"
fi
"${STOP[@]}" > /dev/null 2>&1 || true
kill "$GUI_PID" 2>/dev/null || true
wait "$GUI_PID" 2>/dev/null || true

section "summary"
if [ "$FAILURES" -eq 0 ]; then
  echo "$MACHINE: everything passed"
else
  echo "$MACHINE: $FAILURES check(s) failed"
fi
exit "$FAILURES"
