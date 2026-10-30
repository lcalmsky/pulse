#!/bin/bash
# scripts/pulse-page.sh 의 열기·기록 경로를 가짜 orca 와 가짜 open, 임시 PULSE_PAGES_DIR 로 검사한다.
# 네트워크와 실제 ~/.pulse/pages 를 쓰지 않는다.
set -u
src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PP="$src/scripts/pulse-page.sh"
pass=0
fail=0

work="$(mktemp -d "${TMPDIR:-/tmp}/pulse-page-selftest.XXXXXX")"
work="$(cd "$work" && pwd -P)"
trap 'rm -rf "$work"' EXIT

shim="$work/shim"
mkdir -p "$shim"
cat > "$shim/open" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$work/open.log"
exit 0
EOF
chmod +x "$shim/open"
export PATH="$shim:$PATH"
: > "$work/open.log"

cat > "$work/orca-ok" <<'EOF'
#!/bin/bash
echo '{"ok":true,"result":{"browserPageId":"p-123"}}'
EOF
cat > "$work/orca-fail" <<'EOF'
#!/bin/bash
echo 'orca boom' >&2
exit 1
EOF
chmod +x "$work/orca-ok" "$work/orca-fail"

E=(env -u ORCA_WORKTREE_ID -u ORCA_TERMINAL_HANDLE -u CLAUDE_CODE_SESSION_ID \
  -u PULSE_PAGES_DIR -u PULSE_PAGE_DRY_RUN -u PULSE_PAGE_DRY_PAGE_ID -u PULSE_ORCA_CLI)

check() {  # $1=설명 $2=기대 부분문자열 $3=출력
  if grep -qF -- "$2" <<<"$3"; then
    echo "PASS: $1"
    pass=$((pass + 1))
  else
    echo "FAIL: $1 — 기대 '$2'"
    sed 's/^/    | /' <<<"$3"
    fail=$((fail + 1))
  fi
}

check_not() {  # $1=설명 $2=나오면 안 되는 부분문자열 $3=출력
  if grep -qF -- "$2" <<<"$3"; then
    echo "FAIL: $1 — '$2' 가 나오면 안 된다"
    sed 's/^/    | /' <<<"$3"
    fail=$((fail + 1))
  else
    echo "PASS: $1"
    pass=$((pass + 1))
  fi
}

check_eq() {  # $1=설명 $2=기대 $3=실제
  if [ "$2" = "$3" ]; then
    echo "PASS: $1"
    pass=$((pass + 1))
  else
    echo "FAIL: $1 — 기대 '$2', 실제 '$3'"
    fail=$((fail + 1))
  fi
}

check_fail() {  # $1=설명 $2=종료코드
  if [ "$2" -ne 0 ]; then
    echo "PASS: $1 (exit $2)"
    pass=$((pass + 1))
  else
    echo "FAIL: $1 — exit 0 이면 안 된다"
    fail=$((fail + 1))
  fi
}

json_field() {  # $1=파일 $2=키 -> 값, 없거나 파싱 실패면 <없음>
  python3 -c 'import json,sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("<없음>"); sys.exit(0)
print(d.get(sys.argv[2], "<없음>"))' "$1" "$2" 2>/dev/null
}

json_has_key() {  # $1=파일 $2=키 -> yes/no, 파싱 실패면 error
  python3 -c 'import json,sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("error"); sys.exit(0)
print("yes" if sys.argv[2] in d else "no")' "$1" "$2" 2>/dev/null
}

url_decodes_to() {  # $1=url $2=경로 -> 같으면 yes
  python3 -c 'import sys,urllib.parse
print("yes" if urllib.parse.unquote(sys.argv[1]) == "file://" + sys.argv[2] else "no")' "$1" "$2" 2>/dev/null
}

count_json() {  # $1=디렉터리 -> *.json 개수
  find "$1" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' '
}

# --- Orca 안: 탭을 열고 페이지 파일을 쓴다
pages1="$work/pages1"
mkdir -p "$work/한글 폴더"
t1k="$work/한글 폴더/페이지.html"
printf '<html><head><title>백오프 설계안</title></head><body>x</body></html>\n' >"$t1k"
out="$("${E[@]}" ORCA_WORKTREE_ID='repo1::/w/tree' ORCA_TERMINAL_HANDLE=term_1 \
  CLAUDE_CODE_SESSION_ID=sess-1 PULSE_PAGES_DIR="$pages1" PULSE_ORCA_CLI="$work/orca-ok" \
  "$PP" "$t1k" 2>&1)"
check 'Orca 안 -> orca tab' 'opened: orca-tab p-123' "$out"
f1="$pages1/p-123.json"
if [ -f "$f1" ]; then
  echo "PASS: Orca 안 -> 페이지 파일 생성"
  pass=$((pass + 1))
else
  echo "FAIL: Orca 안 -> 페이지 파일이 없다 — $f1"
  fail=$((fail + 1))
fi
check_eq '필드 version' '1' "$(json_field "$f1" version)"
check_eq '필드 page_id' 'p-123' "$(json_field "$f1" page_id)"
check_eq '필드 worktree' 'repo1::/w/tree' "$(json_field "$f1" worktree)"
check_eq '필드 label 은 title' '백오프 설계안' "$(json_field "$f1" label)"
check_eq '필드 terminal_handle' 'term_1' "$(json_field "$f1" terminal_handle)"
check_eq 'CLAUDE_CODE_SESSION_ID -> session_id' 'sess-1' "$(json_field "$f1" session_id)"
check_eq 'open 경로에는 session_name 키가 없다' 'no' "$(json_has_key "$f1" session_name)"
if grep -qE '"created_at": "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' "$f1"; then
  echo "PASS: created_at 형식"
  pass=$((pass + 1))
else
  echo "FAIL: created_at 형식"
  sed 's/^/    | /' "$f1"
  fail=$((fail + 1))
fi
check_eq '공백·한글 경로 퍼센트 인코딩' 'yes' "$(url_decodes_to "$(json_field "$f1" url)" "$t1k")"
check_not '퍼센트 인코딩된 url 에 공백이 없다' ' ' "$(json_field "$f1" url)"
check_eq 'tmp 파일이 남지 않는다' '0' "$(find "$pages1" -maxdepth 1 -name '.*.json.tmp' | wc -l | tr -d ' ')"

# --- CLAUDE_CODE_SESSION_ID 가 없으면 session_id 키가 없다
pages2="$work/pages2"
t2="$work/t2.html"
printf '<title>t</title>\n' >"$t2"
"${E[@]}" ORCA_WORKTREE_ID=w2 PULSE_PAGES_DIR="$pages2" PULSE_ORCA_CLI="$work/orca-ok" "$PP" "$t2" >/dev/null 2>&1
check_eq '세션 id 없음 -> session_id 키 없음' 'no' "$(json_has_key "$pages2/p-123.json" session_id)"

# --- label 기본값: title 이 없으면 파일 이름
pages3="$work/pages3"
t3="$work/제목없음.html"
printf '<div>조각</div>\n' >"$t3"
"${E[@]}" ORCA_WORKTREE_ID=w3 PULSE_PAGES_DIR="$pages3" PULSE_ORCA_CLI="$work/orca-ok" "$PP" "$t3" >/dev/null 2>&1
check_eq 'label 기본값은 파일 이름' '제목없음.html' "$(json_field "$pages3/p-123.json" label)"

# --- label 기본값: URL 이면 URL
pages4="$work/pages4"
"${E[@]}" ORCA_WORKTREE_ID=w4 PULSE_PAGES_DIR="$pages4" PULSE_ORCA_CLI="$work/orca-ok" \
  "$PP" https://example.com/report >/dev/null 2>&1
check_eq 'label 기본값은 URL' 'https://example.com/report' "$(json_field "$pages4/p-123.json" label)"
check_eq 'URL 은 그대로 쓴다' 'https://example.com/report' "$(json_field "$pages4/p-123.json" url)"

# --- --label 은 title 보다 우선한다
pages5="$work/pages5"
"${E[@]}" ORCA_WORKTREE_ID=w5 PULSE_PAGES_DIR="$pages5" PULSE_ORCA_CLI="$work/orca-ok" \
  "$PP" --label '배포 확인' "$t2" >/dev/null 2>&1
check_eq '--label 우선' '배포 확인' "$(json_field "$pages5/p-123.json" label)"

# --- Orca 밖: 기본 앱으로 열고 파일은 쓰지 않는다
pages6="$work/pages6"
: > "$work/open.log"
out="$("${E[@]}" PULSE_PAGES_DIR="$pages6" "$PP" "$t2" 2>&1)"
check 'Orca 밖 -> open' "opened: open $t2" "$out"
check 'Orca 밖 -> open 실행' "$t2" "$(cat "$work/open.log")"
check_eq 'Orca 밖 -> 파일 없음' '0' "$(count_json "$pages6")"

# --- tab create 실패: 기본 앱으로 열고 파일은 쓰지 않는다
pages7="$work/pages7"
: > "$work/open.log"
out="$("${E[@]}" ORCA_WORKTREE_ID=w7 PULSE_PAGES_DIR="$pages7" PULSE_ORCA_CLI="$work/orca-fail" \
  "$PP" "$t2" 2>&1)"
check 'tab create 실패 -> open' "opened: open $t2" "$out"
check 'tab create 실패 -> orca stderr' 'orca boom' "$out"
check_eq 'tab create 실패 -> 파일 없음' '0' "$(count_json "$pages7")"

# --- record 단독: Orca 를 부르지 않고 파일만 쓴다
pages8="$work/pages8"
out="$("${E[@]}" PULSE_PAGES_DIR="$pages8" PULSE_ORCA_CLI="$work/orca-ok" \
  "$PP" record --page-id r-1 --url file:///tmp/x.html --label X \
  --worktree w8 --terminal-handle h8 --session-id s8 --session-name n8 2>&1)"
check_not 'record -> orca 를 부르지 않는다' 'opened:' "$out"
check_eq 'record 필드 page_id' 'r-1' "$(json_field "$pages8/r-1.json" page_id)"
check_eq 'record 필드 label' 'X' "$(json_field "$pages8/r-1.json" label)"
check_eq 'record 필드 terminal_handle' 'h8' "$(json_field "$pages8/r-1.json" terminal_handle)"
check_eq 'record 필드 session_id' 's8' "$(json_field "$pages8/r-1.json" session_id)"
check_eq 'record 필드 session_name' 'n8' "$(json_field "$pages8/r-1.json" session_name)"

# --- record: 생략한 값은 환경 변수에서 온다
pages9="$work/pages9"
"${E[@]}" ORCA_WORKTREE_ID=w9 ORCA_TERMINAL_HANDLE=h9 CLAUDE_CODE_SESSION_ID=s9 PULSE_PAGES_DIR="$pages9" \
  "$PP" record --page-id r-9 --url file:///tmp/y.html >/dev/null 2>&1
check_eq 'record env worktree' 'w9' "$(json_field "$pages9/r-9.json" worktree)"
check_eq 'record env terminal_handle' 'h9' "$(json_field "$pages9/r-9.json" terminal_handle)"
check_eq 'record env session_id' 's9' "$(json_field "$pages9/r-9.json" session_id)"

# --- record: worktree 를 모르면 쓰지 않고 exit 2
pages10="$work/pages10"
"${E[@]}" PULSE_PAGES_DIR="$pages10" "$PP" record --page-id r-10 --url file:///tmp/z.html >/dev/null 2>&1
rc=$?
check_fail 'worktree 없음 -> exit 2' "$rc"
check_eq 'worktree 없음 -> exit 2' '2' "$rc"
check_eq 'worktree 없음 -> 파일 없음' '0' "$(count_json "$pages10")"

# --- 같은 worktree+url: 이전 파일을 지운다
pages11="$work/pages11"
"${E[@]}" PULSE_PAGES_DIR="$pages11" "$PP" record --page-id r-11a --url file:///same.html --worktree w11 >/dev/null 2>&1
"${E[@]}" PULSE_PAGES_DIR="$pages11" "$PP" record --page-id r-11b --url file:///same.html --worktree w11 >/dev/null 2>&1
check_eq '같은 worktree+url -> 파일 하나' '1' "$(count_json "$pages11")"
check_eq '같은 worktree+url -> 남은 것은 새 파일' 'r-11b' "$(json_field "$pages11/r-11b.json" page_id)"

# --- url 이 다르면 둘 다 남는다
pages12="$work/pages12"
"${E[@]}" PULSE_PAGES_DIR="$pages12" "$PP" record --page-id r-12a --url file:///a.html --worktree w12 >/dev/null 2>&1
"${E[@]}" PULSE_PAGES_DIR="$pages12" "$PP" record --page-id r-12b --url file:///b.html --worktree w12 >/dev/null 2>&1
check_eq 'url 이 다르면 둘 다 남는다' '2' "$(count_json "$pages12")"

# --- 깨진 JSON 은 건드리지 않는다
pages13="$work/pages13"
mkdir -p "$pages13"
printf '{' >"$pages13/broken.json"
"${E[@]}" PULSE_PAGES_DIR="$pages13" "$PP" record --page-id r-13 --url file:///same.html --worktree w13 >/dev/null 2>&1
check_eq '깨진 JSON 은 그대로' '{' "$(cat "$pages13/broken.json" 2>/dev/null)"
check_eq '깨진 JSON + 새 파일' '2' "$(count_json "$pages13")"

# --- page_id 에 / 가 있으면 거부한다
pages14="$work/pages14"
out="$("${E[@]}" PULSE_PAGES_DIR="$pages14" "$PP" record --page-id 'a/b' --url file:///x.html --worktree w14 2>&1)"
rc=$?
check_fail 'page_id 에 / -> exit 2' "$rc"
check_eq 'page_id 에 / -> exit 2' '2' "$rc"
check_eq 'page_id 에 / -> 파일 없음' '0' "$(count_json "$pages14")"

# --- dry-run: Orca 밖이면 open 명령만 출력하고 실행하지 않는다
pages15="$work/pages15"
: > "$work/open.log"
out="$("${E[@]}" PULSE_PAGE_DRY_RUN=1 PULSE_PAGES_DIR="$pages15" "$PP" "$t2" 2>&1)"
check 'dry-run -> open 명령 출력' "open $t2" "$out"
check_eq 'dry-run -> open 을 실행하지 않는다' '' "$(cat "$work/open.log")"
check_eq 'dry-run -> 파일 없음' '0' "$(count_json "$pages15")"

# --- dry-run: Orca 안이면 tab create 명령을 출력하고 page_id 와 함께 파일을 쓴다
pages16="$work/pages16"
out="$("${E[@]}" PULSE_PAGE_DRY_RUN=1 PULSE_PAGE_DRY_PAGE_ID=dp-16 ORCA_WORKTREE_ID=w16 \
  PULSE_PAGES_DIR="$pages16" PULSE_ORCA_CLI="$work/orca-ok" "$PP" "$t2" 2>&1)"
check 'dry-run -> tab create 명령' 'orca tab create --url file://' "$out"
check 'dry-run -> worktree 포함' '--worktree id:w16' "$out"
check 'dry-run -> orca-tab 출력' 'opened: orca-tab dp-16' "$out"
check_eq 'dry-run -> page_id 파일' 'dp-16' "$(json_field "$pages16/dp-16.json" page_id)"

# --- dry-run: PULSE_PAGES_DIR 이 없으면 page-file 줄만 출력하고 쓰지 않는다
home17="$work/home17"
mkdir -p "$home17"
out="$("${E[@]}" HOME="$home17" PULSE_PAGE_DRY_RUN=1 PULSE_PAGE_DRY_PAGE_ID=dp-17 ORCA_WORKTREE_ID=w17 \
  PULSE_ORCA_CLI="$work/orca-ok" "$PP" "$t2" 2>&1)"
check 'dry-run -> page-file 줄' "page-file $home17/.pulse/pages/dp-17.json" "$out"
if [ -e "$home17/.pulse/pages" ]; then
  echo "FAIL: dry-run 인데 HOME 아래에 페이지 디렉터리가 생겼다"
  fail=$((fail + 1))
else
  echo "PASS: dry-run -> HOME 아래에 쓰지 않는다"
  pass=$((pass + 1))
fi

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ] || exit 1
