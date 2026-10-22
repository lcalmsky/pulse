#!/bin/bash
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
real_git="$(command -v git)"
work="$(mktemp -d "${TMPDIR:-/tmp}/release-selftest.XXXXXX")"
trap 'rm -rf "$work"' EXIT

repo="$work/repo"
shims="$work/shims"
mkdir -p "$repo/scripts" "$repo/Sources/pulse" "$repo/Formula" "$shims"
cp "$src/scripts/release.sh" "$repo/scripts/release.sh"
echo '    static let version = "0.2.0"' > "$repo/Sources/pulse/AppDelegate.swift"
cat > "$repo/Formula/pulse.rb" <<'EOF'
class Pulse < Formula
  homepage "https://github.com/lcalmsky/pulse"
  url "https://github.com/lcalmsky/pulse/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
EOF

export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.com
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.com
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false

g() { "$real_git" -C "$repo" "$@"; }
g init -q -b main
g add -A
g commit -q -m "chore: 시험 저장소"
g tag -a v0.2.0 -m "시험 태그"
g remote add origin git@github-lcalmsky:lcalmsky/pulse.git

# release.sh 가 부르는 외부 명령은 네트워크나 빌드가 필요하므로 호출을 기록만 하는 가짜로 바꾼다
: > "$work/push.log"
: > "$work/gh.log"
cat > "$shims/gh" <<EOF
#!/bin/bash
echo "\$*" >> "$work/gh.log"
[[ "\$1 \$2" != "api user" ]] || echo lcalmsky
if [[ "\$1 \$2" == "release create" ]]; then
    while ((\$# > 0)); do
        if [[ "\$1" == --notes-file ]]; then
            cp "\$2" "$work/release-notes"
        fi
        shift
    done
fi
exit 0
EOF
cat > "$shims/git" <<EOF
#!/bin/bash
if [[ "\$*" == *ls-remote* ]]; then
    [[ \$FAKE_LS_REMOTE != FAIL ]] || exit 128
    printf '%s' "\$FAKE_LS_REMOTE"
    exit 0
fi
if [[ "\$1" == push ]]; then
    echo "\$*" >> "$work/push.log"
    exit 0
fi
exec "$real_git" "\$@"
EOF
cat > "$shims/curl" <<'EOF'
#!/bin/bash
printf 'fixed-tarball'
EOF
cat > "$shims/swift" <<'EOF'
#!/bin/bash
if [[ $1 == run ]]; then echo "selftest: 1 checks, 0 failures"; fi
exit 0
EOF
chmod +x "$shims/gh" "$shims/git" "$shims/curl" "$shims/swift"
export PATH="$shims:$PATH"

fixed_sha="$(printf 'fixed-tarball' | shasum -a 256 | awk '{print $1}')"

total=0
failures=0
out=""
status=0

run() {
    set +e
    out="$(cd "$repo" && scripts/release.sh "$@" 2>&1)"
    status=$?
    set -e
}

check() {
    local name="$1" want_status="$2" want_text="$3"
    total=$((total + 1))
    if ((status != want_status)) || [[ $out != *"$want_text"* ]]; then
        failures=$((failures + 1))
        echo "실패: $name (종료 $status, 기대 $want_status, 기대 문구 \"$want_text\")"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
}

check_absent() {
    local name="$1" unwanted="$2"
    total=$((total + 1))
    if [[ $out == *"$unwanted"* ]]; then
        failures=$((failures + 1))
        echo "실패: $name (출력에 \"$unwanted\" 가 있으면 안 된다)"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
}

expect_eq() {
    local name="$1" actual="$2" expected="$3"
    total=$((total + 1))
    if [[ $actual != "$expected" ]]; then
        failures=$((failures + 1))
        echo "실패: $name (실제 \"$actual\", 기대 \"$expected\")"
    fi
}

formula_line() { grep "^  $1 " "$repo/Formula/pulse.rb"; }

export FAKE_LS_REMOTE=$'0000000000000000000000000000000000000000\trefs/tags/v0.2.0\n'

run --formula-only
check "재개: 버전 누락" 1 "버전을 넘기세요"

run --formula-only abc
check "재개: 버전 형식 오류" 1 "X.Y.Z 형식이어야 합니다"

run --formula-only 0.2.0 -m x
check "재개: -m 거부" 1 "받지 않습니다"

run --formula-only 0.2.0 --notes-file x
check "재개: --notes-file 거부" 1 "받지 않습니다"

run --formula-only 9.9.9
check "재개: 로컬 태그 없음" 1 "로컬에 태그 v9.9.9 이 없습니다"

FAKE_LS_REMOTE="" run --formula-only 0.2.0
check "재개: 원격 태그 없음" 1 "원격 origin 에 태그 v0.2.0 이 없습니다"

FAKE_LS_REMOTE=FAIL run --formula-only 0.2.0
check "재개: 원격 조회 실패" 1 "원격 태그를 조회하지 못했습니다"

touch "$repo/dirty"
run --formula-only 0.2.0
check "재개: 더러운 워킹트리" 1 "워킹트리가 깨끗하지 않습니다"
rm "$repo/dirty"

run --formula-only 0.2.0 --dry-run
check "재개 dry-run: 7~9단계 출력" 0 "7. https://github.com/lcalmsky/pulse/archive/refs/tags/v0.2.0.tar.gz"
check "재개 dry-run: 9단계 출력" 0 "9. 릴리즈 URL"
check_absent "재개 dry-run: 2단계 생략" "2. Sources"
check_absent "재개 dry-run: 6단계 생략" "6. gh release create"

run 0.2.0 -m x --dry-run
check "전체: 기존 태그 거부" 1 "태그 v0.2.0 이 이미 있습니다"

run 0.1.9 -m x --dry-run
check "전체: 낮은 버전 거부" 1 "현재 버전 0.2.0 보다 크지 않습니다"

run 0.2.1 -m x --dry-run
check "전체 dry-run: 2단계 출력" 0 "2. Sources/pulse/AppDelegate.swift"
check "전체 dry-run: 6단계 출력" 0 "6. gh release create v0.2.1"
check "전체 dry-run: 9단계 출력" 0 "9. 릴리즈 URL"

run --formula-only 0.2.0
check "재개 실행: 종료" 0 "릴리즈: https://github.com/lcalmsky/pulse/releases/tag/v0.2.0"
expect_eq "재개 실행: url 갱신" "$(formula_line url)" '  url "https://github.com/lcalmsky/pulse/archive/refs/tags/v0.2.0.tar.gz"'
expect_eq "재개 실행: sha256 갱신" "$(formula_line sha256)" "  sha256 \"$fixed_sha\""
expect_eq "재개 실행: formula 커밋" "$(g log -1 --format=%s)" "chore: Formula v0.2.0"
expect_eq "재개 실행: 버전 유지" "$(cat "$repo/Sources/pulse/AppDelegate.swift")" '    static let version = "0.2.0"'
expect_eq "재개 실행: 태그 유지" "$(g tag -l | tr '\n' ' ')" "v0.2.0 "
expect_eq "재개 실행: 푸시" "$(cat "$work/push.log")" "push origin main"
expect_eq "재개 실행: 릴리즈 생성 없음" "$(grep -c 'release create' "$work/gh.log" || true)" "0"

: > "$work/push.log"
run 0.2.1 -m x
check "전체 실행: 종료" 0 "릴리즈: https://github.com/lcalmsky/pulse/releases/tag/v0.2.1"
expect_eq "전체 실행: 버전 변경" "$(cat "$repo/Sources/pulse/AppDelegate.swift")" '    static let version = "0.2.1"'
expect_eq "전체 실행: 태그 생성" "$(g tag -l | tr '\n' ' ')" "v0.2.0 v0.2.1 "
expect_eq "전체 실행: 버전 커밋" "$(g log -2 --format=%s | tail -1)" "chore: x 버전 0.2.1"
expect_eq "전체 실행: formula 커밋" "$(g log -1 --format=%s)" "chore: Formula v0.2.1"
expect_eq "전체 실행: url 갱신" "$(formula_line url)" '  url "https://github.com/lcalmsky/pulse/archive/refs/tags/v0.2.1.tar.gz"'
expect_eq "전체 실행: 푸시 순서" "$(tr '\n' '|' < "$work/push.log")" "push origin main|push origin v0.2.1|push origin main|"
expect_eq "전체 실행: 릴리즈 생성" "$(grep -c '^release create v0.2.1 ' "$work/gh.log")" "1"
check "전체 실행: 업데이트 안내" 0 "업데이트: brew upgrade lcalmsky/pulse/pulse"
expect_eq "전체 실행: 릴리즈 노트 업데이트 안내" "$(grep -c 'brew upgrade lcalmsky/pulse/pulse' "$work/release-notes" 2>/dev/null || true)" "1"

echo "release-selftest: $total checks, $failures failures"
((failures == 0))
