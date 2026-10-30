#!/bin/bash
# Pulse 페이지 알림을 여는 도구.
#
#   pulse-page.sh [open] [--label <제목>] <html 파일 경로 | http(s) URL>
#     Orca 터미널 안이면 새 탭으로 열고 ~/.pulse/pages 에 알림 파일을 남긴다.
#     그 밖이거나 탭을 열지 못하면 기본 앱으로 열고 파일을 쓰지 않는다.
#   pulse-page.sh record --page-id <id> --url <url> [--label <제목>] [--worktree <id>]
#                        [--terminal-handle <h>] [--session-id <id>] [--session-name <이름>]
#     페이지를 열지 않고 알림 파일만 쓴다.
#
# 환경 변수: PULSE_PAGES_DIR(파일 디렉터리), PULSE_PAGE_DRY_RUN(1 이면 실행하지 않고 명령만 출력),
#            PULSE_PAGE_DRY_PAGE_ID(dry-run 의 page_id), PULSE_ORCA_CLI(Orca 실행 파일 경로),
#            ORCA_WORKTREE_ID·ORCA_TERMINAL_HANDLE·CLAUDE_CODE_SESSION_ID(생략한 값의 기본값)
set -u

dry="${PULSE_PAGE_DRY_RUN:-}"
sub="open"
if [ "${1:-}" = "open" ] || [ "${1:-}" = "record" ]; then
  sub="$1"
  shift
fi

write_record() {  # $1=page_id $2=url $3=label $4=worktree $5=terminal_handle $6=session_id $7=session_name
  local page_id="$1" url="$2" label="$3" worktree="$4" handle="$5" session_id="$6" session_name="$7"
  case "$page_id" in
    */*)
      printf 'pulse-page.sh: page_id 에 / 가 있어 페이지 파일을 쓰지 않는다: %s\n' "$page_id" >&2
      return 2
      ;;
  esac
  local pages_dir="${PULSE_PAGES_DIR:-$HOME/.pulse/pages}"
  local page_file="$pages_dir/$page_id.json"
  if [ -n "$dry" ] && [ -z "${PULSE_PAGES_DIR:-}" ]; then
    printf 'page-file %s\n' "$page_file"
    return 0
  fi
  if ! mkdir -p "$pages_dir" 2>/dev/null; then
    printf 'pulse-page.sh: 페이지 디렉터리를 만들지 못했다: %s\n' "$pages_dir" >&2
    return 1
  fi
  local page_tmp="$pages_dir/.$page_id.json.tmp"
  if ! python3 - "$page_tmp" "$page_id" "$worktree" "$url" "$label" "$handle" "$session_id" "$session_name" <<'PY'
import json, sys, time

tmp, page_id, worktree, url, label, handle, session_id, session_name = sys.argv[1:9]
page = {
    "version": 1,
    "page_id": page_id,
    "worktree": worktree,
    "url": url,
    "label": label,
    "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
if handle:
    page["terminal_handle"] = handle
if session_id:
    page["session_id"] = session_id
if session_name:
    page["session_name"] = session_name
with open(tmp, "w", encoding="utf-8") as f:
    f.write(json.dumps(page, ensure_ascii=False, indent=2) + "\n")
PY
  then
    rm -f "$page_tmp" 2>/dev/null
    printf 'pulse-page.sh: 페이지 파일을 쓰지 못했다: %s\n' "$page_file" >&2
    return 1
  fi
  if ! mv -f "$page_tmp" "$page_file" 2>/dev/null; then
    rm -f "$page_tmp" 2>/dev/null
    printf 'pulse-page.sh: 페이지 파일을 쓰지 못했다: %s\n' "$page_file" >&2
    return 1
  fi
  python3 - "$pages_dir" "$page_file" <<'PY'
import json, os, sys

try:
    pages_dir, keep = sys.argv[1], os.path.abspath(sys.argv[2])
    with open(keep, encoding="utf-8") as f:
        target = json.load(f)
    worktree, url = target.get("worktree"), target.get("url")
    if worktree and url:
        for name in os.listdir(pages_dir):
            if name.startswith(".") or not name.endswith(".json"):
                continue
            path = os.path.abspath(os.path.join(pages_dir, name))
            if path == keep:
                continue
            try:
                with open(path, encoding="utf-8") as f:
                    other = json.load(f)
            except Exception:
                continue
            if other.get("worktree") == worktree and other.get("url") == url:
                try:
                    os.remove(path)
                except OSError as exc:
                    sys.stderr.write("pulse-page.sh: 같은 페이지의 옛 파일을 지우지 못했다: %s: %s\n" % (path, exc))
except Exception as exc:
    sys.stderr.write("pulse-page.sh: 같은 페이지의 옛 파일 정리를 건너뛴다: %s\n" % exc)
PY
  return 0
}

if [ "$sub" = "record" ]; then
  page_id=""
  url=""
  label=""
  worktree=""
  handle=""
  session_id=""
  session_name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --page-id) page_id="${2:-}"; shift 2 2>/dev/null || shift ;;
      --page-id=*) page_id="${1#--page-id=}"; shift ;;
      --url) url="${2:-}"; shift 2 2>/dev/null || shift ;;
      --url=*) url="${1#--url=}"; shift ;;
      --label) label="${2:-}"; shift 2 2>/dev/null || shift ;;
      --label=*) label="${1#--label=}"; shift ;;
      --worktree) worktree="${2:-}"; shift 2 2>/dev/null || shift ;;
      --worktree=*) worktree="${1#--worktree=}"; shift ;;
      --terminal-handle) handle="${2:-}"; shift 2 2>/dev/null || shift ;;
      --terminal-handle=*) handle="${1#--terminal-handle=}"; shift ;;
      --session-id) session_id="${2:-}"; shift 2 2>/dev/null || shift ;;
      --session-id=*) session_id="${1#--session-id=}"; shift ;;
      --session-name) session_name="${2:-}"; shift 2 2>/dev/null || shift ;;
      --session-name=*) session_name="${1#--session-name=}"; shift ;;
      *) shift ;;
    esac
  done
  if [ -z "$page_id" ] || [ -z "$url" ]; then
    echo '사용법: pulse-page.sh record --page-id <id> --url <url> [--label <제목>] [--worktree <id>] [--terminal-handle <h>] [--session-id <id>] [--session-name <이름>]' >&2
    exit 2
  fi
  if [ -z "$worktree" ]; then worktree="${ORCA_WORKTREE_ID:-}"; fi
  if [ -z "$handle" ]; then handle="${ORCA_TERMINAL_HANDLE:-}"; fi
  if [ -z "$session_id" ]; then session_id="${CLAUDE_CODE_SESSION_ID:-}"; fi
  if [ -z "$worktree" ]; then
    printf 'pulse-page.sh: 워크트리를 알 수 없어 페이지 파일을 쓰지 않는다: %s\n' "$page_id" >&2
    exit 2
  fi
  if [ -z "$label" ]; then label="$url"; fi
  write_record "$page_id" "$url" "$label" "$worktree" "$handle" "$session_id" "$session_name"
  exit $?
fi

label=""
target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      if [ $# -ge 2 ]; then label="$2"; shift 2; else shift; fi
      ;;
    --label=*) label="${1#--label=}"; shift ;;
    *)
      if [ -z "$target" ]; then target="$1"; fi
      shift
      ;;
  esac
done

if [ -z "$target" ]; then
  echo '사용법: pulse-page.sh [open] [--label "<제목>"] <html 파일 경로 또는 http(s) URL>' >&2
  exit 1
fi

is_url=""
case "$target" in
  http://*|https://*) is_url=1 ;;
esac

abs="$target"
url=""
if [ -z "$is_url" ]; then
  if [ ! -e "$target" ]; then
    printf 'pulse-page.sh: 파일이 없다: %s\n' "$target" >&2
    exit 1
  fi
  abs="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$target")"
  url="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).as_uri())' "$abs")"
  if [ -z "$label" ]; then
    label="$(python3 - "$abs" <<'PY'
import re, sys

try:
    src = open(sys.argv[1], encoding='utf-8', errors='surrogateescape').read()
except OSError:
    sys.exit(0)
m = re.search(r'<title\b[^>]*>(.*?)</title>', src, re.S | re.I)
if m:
    sys.stdout.write(re.sub(r'\s+', ' ', m.group(1)).strip())
PY
)"
  fi
  if [ -z "$label" ]; then label="$(basename "$abs")"; fi
else
  url="$target"
  if [ -z "$label" ]; then label="$target"; fi
fi

orca_cli="${PULSE_ORCA_CLI:-/Applications/Orca.app/Contents/Resources/bin/orca}"
method="open"
page_id=""
if [ -n "${ORCA_WORKTREE_ID:-}" ] && [ -x "$orca_cli" ]; then
  if [ -n "$dry" ]; then
    printf 'orca tab create --url %s --worktree id:%s --json\n' "$url" "$ORCA_WORKTREE_ID"
    method="orca-tab"
    page_id="${PULSE_PAGE_DRY_PAGE_ID:-}"
  elif out="$("$orca_cli" tab create --url "$url" --worktree "id:$ORCA_WORKTREE_ID" --json 2>&1)"; then
    method="orca-tab"
    page_id="$(printf '%s\n' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

def find(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "browserPageId" and isinstance(v, str) and v:
                return v
            r = find(v)
            if r:
                return r
    elif isinstance(o, list):
        for v in o:
            r = find(v)
            if r:
                return r
    return None

pid = find(d)
if pid is None and isinstance(d, dict) and isinstance(d.get("id"), str) and d["id"]:
    pid = d["id"]
if pid:
    print(pid)
')"
  else
    printf '%s\n' "$out" >&2
  fi
fi

if [ "$method" = "orca-tab" ]; then
  if [ -n "$page_id" ]; then
    write_record "$page_id" "$url" "$label" "${ORCA_WORKTREE_ID:-}" "${ORCA_TERMINAL_HANDLE:-}" "${CLAUDE_CODE_SESSION_ID:-}" ""
  fi
  if [ -n "$page_id" ]; then
    printf 'opened: orca-tab %s\n' "$page_id"
  else
    printf 'opened: orca-tab\n'
  fi
  exit 0
fi

if [ -n "$dry" ]; then
  printf 'open %s\n' "$abs"
else
  if ! open "$abs"; then
    printf 'pulse-page.sh: 페이지를 열지 못했다: %s\n' "$abs" >&2
    exit 1
  fi
fi
printf 'opened: open %s\n' "$abs"
exit 0
