#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/scripts/run-failed-putnambench.sh"
WRAPPER="$ROOT/scripts/check-putnambench-comparator.sh"

rg -q 'bash tools/check-with-comparator\.sh' "$RUNNER"
rg -q 'Your solution is okay!' "$RUNNER"
rg -q '## Comparator self-check' "$RUNNER"
rg -q 'ComparatorChallenge\.lean comparator\.json' "$RUNNER"
rg -q 'mount -o remount,ro,bind.*comparator-tools' "$RUNNER"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/project/tools" "$tmp/bin" "$tmp/lean-prefix/bin"
cp "$WRAPPER" "$tmp/project/tools/check-with-comparator.sh"
printf '{}\n' > "$tmp/project/comparator.json"
for tool in comparator lean4export landrun; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/$tool"
  chmod +x "$tmp/$tool"
done
cat > "$tmp/bin/lean" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$tmp/lean-prefix'
EOF
cat > "$tmp/lean-prefix/bin/lake" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*"
printf 'landrun=%s\n' "$COMPARATOR_LANDRUN"
printf 'exporter=%s\n' "$COMPARATOR_LEAN4EXPORT"
EOF
chmod +x "$tmp/bin/lean" "$tmp/lean-prefix/bin/lake"

output="$(PATH="$tmp/bin:$PATH" COMPARATOR_BIN="$tmp/comparator" \
  LEAN4EXPORT_BIN="$tmp/lean4export" LANDRUN_BIN="$tmp/landrun" \
  bash "$tmp/project/tools/check-with-comparator.sh")"
[[ "$output" == *"env $tmp/comparator $tmp/project/comparator.json"* ]]
[[ "$output" == *"landrun=$tmp/landrun"* ]]
[[ "$output" == *"exporter=$tmp/lean4export"* ]]

printf 'Comparator worker prompt and wrapper tests passed.\n'
