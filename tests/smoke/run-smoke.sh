#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIPELINE="${ROOT}/src/pipeline.sh"
FAILS=0

assert_file() {
    if [[ ! -f "$1" ]]; then
        echo "FAIL: missing $1"
        FAILS=$((FAILS + 1))
    else
        echo "PASS: found $1"
    fi
}

assert_file "${PIPELINE}"

# shellcheck disable=SC2016 # intentional literal pattern, not a shell expansion
if grep -q 'SCAN_ROOT="\${SCAN_ROOT:-' "${PIPELINE}" 2>/dev/null; then
    echo "PASS: SCAN_ROOT uses env-default pattern"
else
    echo "FAIL: SCAN_ROOT must use SCAN_ROOT=\"\${SCAN_ROOT:-...}\" pattern"
    FAILS=$((FAILS + 1))
fi

if grep -q 'pip install --quiet' "${PIPELINE}" && grep -q 'docker pull' "${PIPELINE}" && grep -q 'gem install' "${PIPELINE}"; then
    echo "PASS: header examples mention pip/docker/gem"
else
    echo "FAIL: config header must include pip/docker/gem examples"
    FAILS=$((FAILS + 1))
fi

# Extract and test install-decision helper by sourcing a minimal stub.
# We grep for the corrected branch instead of running real installs.
if grep -q 'INSTALLED_CHECK\[@\]} -eq 0' "${PIPELINE}" \
   && grep -A20 'INSTALLED_CHECK\[@\]} -eq 0' "${PIPELINE}" | grep -q 'INSTALL_COMMAND'; then
    echo "PASS: empty INSTALLED_CHECK force-install branch present"
else
    echo "FAIL: missing empty INSTALLED_CHECK => INSTALL_COMMAND path"
    FAILS=$((FAILS + 1))
fi

# Source-level: must not append literal "<" into the command array for redirect mode
if grep -n 'command+=("<"' "${PIPELINE}" >/dev/null; then
    echo "FAIL: REDIRECTED still pushes literal < into argv"
    FAILS=$((FAILS + 1))
else
    echo "PASS: no literal < argv append"
fi

# Behavioural: run a tiny redirected pipeline against cat
SMOKE_DIR="$(mktemp -d)"
# shellcheck disable=SC2329 # invoked indirectly via `trap ... EXIT` below
cleanup() { rm -rf "${SMOKE_DIR}"; }
trap cleanup EXIT
cp "${PIPELINE}" "${SMOKE_DIR}/pipeline.sh"
# Rewrite config in the copy for a no-install cat redirect smoke
python3 - <<'PY' "${SMOKE_DIR}/pipeline.sh" "${ROOT}/tests/smoke/fixtures"
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
fix_root = sys.argv[2]
text = path.read_text()
replacements = {
    "PREREQUISITE_COMMANDS=(npm)": "PREREQUISITE_COMMANDS=()",
    "PACKAGE_NAME='standard'": "PACKAGE_NAME='cat'",
    'BASE_COMMAND="${PACKAGE_NAME}"': 'BASE_COMMAND="cat"',
    'INSTALLED_CHECK=("${BASE_COMMAND}" --version)': "INSTALLED_CHECK=()",
    'INSTALL_COMMAND=(npm install -g "${PACKAGE_NAME}")\nTEST_COMMAND=("${BASE_COMMAND}")': 'INSTALL_COMMAND=()\nTEST_COMMAND=("${BASE_COMMAND}")',
    'TEST_COMMAND=("${BASE_COMMAND}")': 'TEST_COMMAND=("cat")',
    "REDIRECTED=false": "REDIRECTED=true",
    'VERSION_COMMAND=("${BASE_COMMAND}" --version)': 'VERSION_COMMAND=("echo" "0.0.0")',
    'FILE_NAME_SEARCH_PATTERN=\'\\.(js|mjs|cjs|jsx)$\'': r"FILE_NAME_SEARCH_PATTERN='sample\.txt$'",
}
# Apply SCAN_ROOT default to fixtures
text = re.sub(
    r'SCAN_ROOT="\$\{SCAN_ROOT:-\.\}"',
    f'SCAN_ROOT="${{SCAN_ROOT:-{fix_root}}}"',
    text,
    count=1,
)
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f"pattern not found for smoke rewrite: {old}")
    text = text.replace(old, new, 1)
path.write_text(text)
PY

if ! REPORT_ONLY=true SHOW_UNMATCHED=false bash "${SMOKE_DIR}/pipeline.sh" >/tmp/pipeline-smoke.out 2>&1; then
    echo "FAIL: redirected cat smoke exited non-zero"
    cat /tmp/pipeline-smoke.out
    FAILS=$((FAILS + 1))
else
    if grep -q 'sample.txt' /tmp/pipeline-smoke.out && grep -qE 'Passed:[[:space:]]*[1-9]|✅' /tmp/pipeline-smoke.out; then
        echo "PASS: redirected cat smoke"
    else
        echo "FAIL: redirected cat smoke did not report a pass"
        cat /tmp/pipeline-smoke.out
        FAILS=$((FAILS + 1))
    fi
fi

MISSING_ROOT_DIR="${SMOKE_DIR}/no-such-scan-root-$$"
rm -rf "${MISSING_ROOT_DIR}"
cp "${PIPELINE}" "${SMOKE_DIR}/pipeline-bad-root.sh"
if SCAN_ROOT="${MISSING_ROOT_DIR}" bash "${SMOKE_DIR}/pipeline-bad-root.sh" >/tmp/pipeline-bad-root.out 2>&1; then
    echo "FAIL: missing SCAN_ROOT should exit non-zero"
    FAILS=$((FAILS + 1))
else
    status=$?
    if [[ "${status}" -eq 0 ]]; then
        echo "FAIL: missing SCAN_ROOT exited 0"
        FAILS=$((FAILS + 1))
    else
        echo "PASS: missing SCAN_ROOT exited ${status}"
    fi
fi

# shellcheck disable=SC2016 # intentional literal pattern, not a shell expansion
if grep -n 'echo "\${param} - \${!param} - \${default_value}"' "${PIPELINE}" >/dev/null; then
    echo "FAIL: debug echo still present in named-value handling"
    FAILS=$((FAILS + 1))
else
    echo "PASS: no named-value debug echo"
fi

# Stub must not reference unbound extra_params before assignment under set -u
if grep -A30 '^handle_non_standard_parameters' "${PIPELINE}" | grep -q 'extra_params=""\|extra_params='; then
    echo "PASS: handle_non_standard_parameters initialises extra_params"
else
    # Accept explicit local init patterns
    if grep -A30 '^handle_non_standard_parameters' "${PIPELINE}" | grep -q 'local extra_params='; then
        echo "PASS: handle_non_standard_parameters initialises extra_params"
    else
        echo "FAIL: stub should initialise extra_params"
        FAILS=$((FAILS + 1))
    fi
fi

# Bash version gate: must run before any `declare -A` and must exit non-zero on
# old Bash. If /bin/bash on this host is already >= 4.4 we can't exercise the
# rejection path with a real interpreter, so fall back to a source-level check
# that the gate precedes the first `declare -A` in the file.
OLD_BASH_VERSION="$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"' 2>/dev/null || echo "0.0")"
OLD_BASH_MAJOR="${OLD_BASH_VERSION%%.*}"
OLD_BASH_MINOR="${OLD_BASH_VERSION##*.}"
if [[ -x /bin/bash ]] && { (( OLD_BASH_MAJOR < 4 )) || { (( OLD_BASH_MAJOR == 4 )) && (( OLD_BASH_MINOR < 4 )); }; }; then
    if /bin/bash "${PIPELINE}" >/tmp/pipeline-old-bash.out 2>&1; then
        echo "FAIL: /bin/bash (${OLD_BASH_VERSION}) should be rejected by the version gate but exited 0"
        cat /tmp/pipeline-old-bash.out
        FAILS=$((FAILS + 1))
    else
        echo "PASS: /bin/bash (${OLD_BASH_VERSION}) rejected by version gate (non-zero exit)"
    fi
else
    echo "SKIP: /bin/bash (${OLD_BASH_VERSION}) is already >= 4.4; checking gate placement instead"
    GATE_LINE=$(grep -n 'BASH_VERSINFO\[0\] < 4' "${PIPELINE}" | head -n1 | cut -d: -f1)
    DECLARE_A_LINE=$(grep -n '^declare -A' "${PIPELINE}" | head -n1 | cut -d: -f1)
    if [[ -n "${GATE_LINE}" && -n "${DECLARE_A_LINE}" && "${GATE_LINE}" -lt "${DECLARE_A_LINE}" ]]; then
        echo "PASS: version gate (line ${GATE_LINE}) precedes first declare -A (line ${DECLARE_A_LINE})"
    else
        echo "FAIL: version gate must precede the first declare -A"
        FAILS=$((FAILS + 1))
    fi
fi

exit "${FAILS}"
