#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

usage() {
    cat <<'EOF'
사용법:
  scripts/release.sh X.Y.Z -m "<바뀐 기능 요약>" [--notes-file FILE] [--dry-run]
  scripts/release.sh --formula-only X.Y.Z [--dry-run]
  scripts/release.sh --help

X.Y.Z 를 AppInfo.version 에 반영하고, 빌드·검사·태그·GitHub Release·Homebrew formula 갱신까지 한 번에 한다.

  -m "<요약>"        커밋 제목과 릴리즈 본문에 쓸 바뀐 기능 요약
  --notes-file FILE  릴리즈 본문으로 쓸 파일. 없으면 요약과 업데이트 방법으로 만든다
  --formula-only     7~9 단계(tarball sha256, formula 갱신·푸시)만 다시 한다. 태그 vX.Y.Z 가 로컬과 원격에 있어야 한다
  --dry-run          검사만 하고, 이어지는 단계에서 할 일을 출력한다
  --help             이 도움말을 보여 준다
EOF
}

fail() {
    echo "오류: $*" >&2
    exit 1
}

version=""
summary=""
notes_file=""
dry_run=0
formula_only=0

while (($#)); do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        -m)
            (($# >= 2)) || { echo "오류: -m 뒤에 요약이 필요합니다" >&2; exit 1; }
            summary="$2"
            shift 2
            ;;
        --notes-file)
            (($# >= 2)) || { echo "오류: --notes-file 뒤에 파일 경로가 필요합니다" >&2; exit 1; }
            notes_file="$2"
            shift 2
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        --formula-only)
            formula_only=1
            shift
            ;;
        -*)
            echo "오류: 알 수 없는 인자입니다: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            [[ -z $version ]] || { echo "오류: 버전은 하나만 넘길 수 있습니다: $1" >&2; exit 1; }
            version="$1"
            shift
            ;;
    esac
done

[[ -n $version ]] || { echo "오류: 버전을 넘기세요" >&2; usage >&2; exit 1; }
if ((formula_only)); then
    [[ -z $summary && -z $notes_file ]] || { echo "오류: --formula-only 는 -m 과 --notes-file 을 받지 않습니다" >&2; exit 1; }
else
    [[ -n $summary ]] || { echo "오류: -m 으로 바뀐 기능 요약을 넘기세요" >&2; usage >&2; exit 1; }
fi

step="준비"
notes_tmp=""

on_exit() {
    local status=$?
    if ((status != 0)); then
        echo "실패: ${step} 단계에서 멈췄습니다 (종료 ${status})" >&2
    fi
    if [[ -n $notes_tmp ]]; then
        rm -f "$notes_tmp"
    fi
}
trap on_exit EXIT

begin_step() {
    step="$1"
    echo "==> $1"
}

version_gt() {
    local IFS=.
    local -a left right
    read -r -a left <<< "$1"
    read -r -a right <<< "$2"
    local i l r
    for i in 0 1 2; do
        l="${left[i]:-0}"
        r="${right[i]:-0}"
        if ((10#$l > 10#$r)); then return 0; fi
        if ((10#$l < 10#$r)); then return 1; fi
    done
    return 1
}

update_formula() {
    # 7. tarball sha256
    begin_step "7/9 tarball sha256"
    step="sha256"
    tarball="https://github.com/lcalmsky/pulse/archive/refs/tags/v${version}.tar.gz"
    sha=""
    for attempt in 1 2 3 4 5; do
        if sha="$(curl -fsSL "$tarball" | shasum -a 256 | awk '{print $1}')" && [[ ${#sha} -eq 64 ]]; then
            break
        fi
        sha=""
        echo "tarball 을 아직 받지 못했습니다 (${attempt}/5)"
        if ((attempt < 5)); then
            sleep 3
        fi
    done
    [[ ${#sha} -eq 64 ]] || fail "태그 tarball 의 sha256 을 구하지 못했습니다: $tarball"

    # 8. Formula 갱신
    begin_step "8/9 Formula 갱신"
    step="formula"
    formula="Formula/pulse.rb"
    [[ -f $formula ]] || fail "formula 파일이 없습니다: $formula"

    url_line="  url \"$tarball\""
    sha_line="  sha256 \"$sha\""
    has_url=0
    has_sha=0
    if grep -qE '^  url "' "$formula"; then has_url=1; fi
    if grep -qE '^  sha256 "' "$formula"; then has_sha=1; fi

    if ((has_url && has_sha)); then
        sed -i '' -E "s|^  url \".*\"$|$url_line|" "$formula"
        sed -i '' -E "s|^  sha256 \".*\"$|$sha_line|" "$formula"
    elif ((has_url)); then
        sed -i '' -E "s|^  url \".*\"$|$url_line|" "$formula"
        awk -v line="$sha_line" '{ print } /^  url "/ && !done { print line; done=1 }' "$formula" > "$formula.tmp"
        mv "$formula.tmp" "$formula"
    elif ((has_sha)); then
        fail "formula 에 url 줄이 없고 sha256 줄만 있습니다"
    else
        if ! awk -v url="$url_line" -v sha="$sha_line" '
            { print }
            /^  homepage / { print url; print sha; done=1 }
            END { if (!done) exit 3 }
        ' "$formula" > "$formula.tmp"; then
            rm -f "$formula.tmp"
            fail "formula 의 homepage 줄을 찾지 못해 url 과 sha256 을 넣지 못했습니다"
        fi
        mv "$formula.tmp" "$formula"
    fi

    git commit -am "chore: Formula v$version"
    git push origin main

    # 9. 안내
    begin_step "9/9 마무리"
    step="완료"
    echo "릴리즈: https://github.com/lcalmsky/pulse/releases/tag/v$version"
    echo "업데이트: brew upgrade pulse"
}

# 1. 검사
begin_step "1/9 검사"
step="검사"

[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "버전은 X.Y.Z 형식이어야 합니다: $version"

if [[ -n $notes_file && ! -f $notes_file ]]; then
    fail "릴리즈 노트 파일이 없습니다: $notes_file"
fi

branch="$(git branch --show-current)"
[[ $branch == main ]] || fail "현재 브랜치가 main 이 아닙니다: ${branch:-없음}"

worktree="$(git status --porcelain)"
[[ -z $worktree ]] || fail "워킹트리가 깨끗하지 않습니다. 커밋하거나 되돌린 뒤 다시 실행하세요.
$worktree"

if ((formula_only)); then
    [[ -n "$(git tag -l "v$version")" ]] || fail "로컬에 태그 v$version 이 없습니다"
    remote_tag="$(git ls-remote --tags origin "refs/tags/v$version")" || fail "원격 태그를 조회하지 못했습니다"
    [[ -n $remote_tag ]] || fail "원격 origin 에 태그 v$version 이 없습니다"
else
    [[ -z "$(git tag -l "v$version")" ]] || fail "태그 v$version 이 이미 있습니다"

    old_version="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/pulse/AppDelegate.swift)"
    old_version="${old_version%%$'\n'*}"
    [[ -n $old_version ]] || fail "Sources/pulse/AppDelegate.swift 에서 AppInfo.version 을 찾지 못했습니다"
    version_gt "$version" "$old_version" || fail "새 버전 $version 이 현재 버전 $old_version 보다 크지 않습니다"
fi

if ! login="$(gh api user -q .login 2>/dev/null)"; then
    login=""
fi
[[ $login == lcalmsky ]] || fail "gh 활성 계정이 lcalmsky 가 아닙니다: ${login:-없음}. gh auth switch -u lcalmsky 로 바꾸세요"

origin="$(git remote get-url origin 2>/dev/null || true)"
[[ $origin == "git@github-lcalmsky:lcalmsky/pulse.git" ]] || fail "origin 주소가 다릅니다: ${origin:-없음}"

if ((formula_only)); then
    echo "검사 통과: 태그 v$version 이 로컬과 원격에 있음, 계정 $login"
else
    echo "검사 통과: $old_version -> $version, 계정 $login"
fi

if ((dry_run)); then
    echo
    echo "--dry-run: 아래 단계는 실행하지 않고 출력만 합니다."
    if ((! formula_only)); then
        echo "2. Sources/pulse/AppDelegate.swift 의 static let version = \"$old_version\" 을 \"$version\" 으로 바꾼다"
        echo "3. swift build -c release 와 swift run pulse-selftest 를 돌린다. 검사가 실패하면 버전 변경을 되돌린다"
        echo "4. git commit -am \"chore: $summary 버전 $version\""
        echo "5. git tag -a v$version -m \"$summary\" / git push origin main / git push origin v$version"
        if [[ -n $notes_file ]]; then
            echo "6. gh release create v$version --title v$version --notes-file $notes_file"
        else
            echo "6. gh release create v$version --title v$version --notes-file <요약과 업데이트 방법으로 만든 임시 파일>"
        fi
    fi
    echo "7. https://github.com/lcalmsky/pulse/archive/refs/tags/v$version.tar.gz 의 sha256 을 구한다 (최대 5회, 3초 간격)"
    echo "8. Formula/pulse.rb 의 url 과 sha256 을 갱신하고 git commit -am \"chore: Formula v$version\" 후 푸시한다"
    echo "9. 릴리즈 URL 과 brew upgrade pulse 를 안내한다"
    exit 0
fi

if ((formula_only)); then
    update_formula
    exit 0
fi

# 2. 버전 변경
begin_step "2/9 AppInfo.version $old_version -> $version"
step="버전 변경"

old_pattern="${old_version//./\\.}"
sed -i '' -E "s|(static let version = \")${old_pattern}\"|\1${version}\"|" Sources/pulse/AppDelegate.swift

numstat="$(git diff --numstat -- Sources/pulse/AppDelegate.swift)"
added=""
deleted=""
path=""
read -r added deleted path <<< "$numstat" || true
if [[ $added != 1 || $deleted != 1 || $path != Sources/pulse/AppDelegate.swift ]]; then
    git checkout -- Sources/pulse/AppDelegate.swift
    fail "AppDelegate.swift 에서 정확히 한 줄만 바뀌지 않았습니다: ${numstat:-변경 없음}"
fi

# 3. 빌드와 검사
begin_step "3/9 빌드와 검사"
step="빌드"
if ! swift build -c release; then
    git checkout -- Sources/pulse/AppDelegate.swift
    fail "릴리즈 빌드가 실패해 버전 변경을 되돌렸습니다"
fi

step="검사"
set +e
selftest_output="$(swift run pulse-selftest 2>&1)"
selftest_status=$?
set -e
printf '%s\n' "$selftest_output" | tail -20
last_line="$(printf '%s\n' "$selftest_output" | tail -1)"
failures=1
if [[ $last_line =~ ^selftest:\ ([0-9]+)\ checks,\ ([0-9]+)\ failures$ ]]; then
    failures="${BASH_REMATCH[2]}"
fi
if ((failures != 0)); then
    git checkout -- Sources/pulse/AppDelegate.swift
    fail "검사가 실패해 버전 변경을 되돌렸습니다: ${last_line:-출력 없음} (종료 $selftest_status)"
fi
echo "검사 통과: $last_line"

# 4. 커밋
begin_step "4/9 커밋"
step="커밋"
git commit -am "chore: $summary 버전 $version"

# 5. 태그와 푸시
begin_step "5/9 태그와 푸시"
step="태그"
git tag -a "v$version" -m "$summary"
step="푸시"
git push origin main
git push origin "v$version"

# 6. GitHub Release
begin_step "6/9 GitHub Release"
step="릴리즈"
if [[ -z $notes_file ]]; then
    notes_tmp="$(mktemp "${TMPDIR:-/tmp}/pulse-release-notes.XXXXXX")"
    cat > "$notes_tmp" <<EOF
$summary

## 업데이트

- Homebrew: \`brew upgrade pulse\`
- 소스 빌드: \`scripts/bundle.sh\`
EOF
    notes_file="$notes_tmp"
fi
gh release create "v$version" --title "v$version" --notes-file "$notes_file"

update_formula
