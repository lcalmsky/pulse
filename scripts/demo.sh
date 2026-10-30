#!/bin/bash
# README 그림용 데모 세션. 사용자 설정(~/.claude)은 건드리지 않고 demo/.run/ 사본만 쓴다.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
demo_root="$root/demo"
run_dir="$demo_root/.run"
state_dir="$run_dir/deadhd-state"
pid_file="$run_dir/pulse.pid"
keepers_file="$run_dir/.demo-keepers"
# Pulse 는 /tmp 아래 절대 경로만 체크리스트 데이터로 읽는다.
data_dir="/tmp/pulse-demo"
bundle="$root/build/Pulse.app"
app_bin="$bundle/Contents/MacOS/pulse"
lang=""
locale_root="$demo_root"

usage() {
    cat <<'TEXT'
사용법:
  scripts/demo.sh start [--dry-run] [--replace] [--many] [--lang ko|en]
                                                  실행용 사본을 만들고 데모 Pulse 를 띄운다
                                                  --lang en 은 영어 데이터와 PULSE_LANG=en 을 쓴다
  scripts/demo.sh render [--many] [--lang ko|en] <디렉터리>
                                                  템플릿을 현재 시각으로 전개한다
                                                  --many 는 세션 15개짜리 묶음을 쓴다
  scripts/demo.sh fire done                       새 「끝남」 세션으로 끝남 카드를 띄운다
  scripts/demo.sh fire attention                  새 「확인 필요」 세션으로 카드를 띄운다
  scripts/demo.sh fire both                       둘 다 넣어 여러 장 카드를 띄운다
  scripts/demo.sh stop                            데모 Pulse 와 실행용 사본을 정리한다

데모 Pulse 는 실제 Pulse 와 같은 설정 저장소를 쓴다. 확인(ack) 기록이 섞일 수 있으니
그림을 다 찍으면 stop 으로 끈다.
TEXT
}

parse_args() {
    many=0 dry_run=0 replace=0 render_dir=""
    while (( $# > 0 )); do
        case "$1" in
            --dry-run) dry_run=1; shift ;;
            --replace) replace=1; shift ;;
            --many) many=1; shift ;;
            --lang)
                [[ $# -ge 2 ]] || { usage >&2; exit 2; }
                lang="$2"
                shift 2
                ;;
            --lang=*) lang="${1#--lang=}"; shift ;;
            -*) echo "알 수 없는 인자입니다 · $1" >&2; usage >&2; exit 2 ;;
            *)
                [[ -z "$render_dir" ]] || { usage >&2; exit 2; }
                render_dir="$1"
                shift
                ;;
        esac
    done
    case "$lang" in
        "") locale_root="$demo_root" ;;
        ko) locale_root="$demo_root" ;;
        en) locale_root="$demo_root/en" ;;
        *) echo "알 수 없는 언어입니다 · $lang" >&2; usage >&2; exit 2 ;;
    esac
}

# 언어별 템플릿은 --lang en 이면 demo/en 아래에서만 찾는다. 한국어판에 있는데 영어판이 없으면
# 조용히 한국어로 되돌아가지 않고 실패한다.
require_localized() {
    local relative="$1"
    if [[ -f "$locale_root/$relative" ]]; then
        echo "$locale_root/$relative"
        return 0
    fi
    if [[ "$lang" == "en" && -f "$demo_root/$relative" ]]; then
        echo "영어판 템플릿이 없습니다 · demo/en/$relative" >&2
        return 1
    fi
    echo "템플릿이 없습니다 · $relative" >&2
    return 1
}

iso_at() {
    date -u -r "$1" +"%Y-%m-%dT%H:%M:%SZ"
}

render_file() {
    local template="$1" output="$2" pid="$3" sid="$4" now="$5"
    local spec label offset
    local args=(-e "s|__PID__|$pid|g" -e "s|__SESSION_ID__|$sid|g" -e "s|__DATA_DIR__|$data_dir|g")
    for spec in NOW:0 S30:30 M1:60 M2:120 M3:180 M4:240 M5:300 M8:480 M9:540 M11:660 M12:720 M22:1320 M35:2100; do
        label="${spec%%:*}"
        offset="${spec#*:}"
        args+=(-e "s|__ISO_${label}__|$(iso_at $((now - offset)))|g")
        args+=(-e "s|__MS_${label}__|$(((now - offset) * 1000))|g")
    done
    for spec in P5:300 P14:840 P30:1800; do
        label="${spec%%:*}"
        offset="${spec#*:}"
        args+=(-e "s|__ISO_${label}__|$(iso_at $((now + offset)))|g")
        args+=(-e "s|__MS_${label}__|$(((now + offset) * 1000))|g")
    done
    sed "${args[@]}" "$template" > "$output"
}

# 두 번째 인자가 herdr 이면 화면 그림에 herdr 배지가 보이도록 패널 환경 변수를 넣어 띄운다.
# 플랫폼 서명 바이너리의 환경은 procargs 에서 가려지므로, ad-hoc 서명한 사본으로 띄운다.
spawn_keeper() {
    local keepers="$1" kind="${2:-sleep}"
    if [[ "$kind" == "herdr" ]]; then
        local binary="${keepers%/*}/.herdr-keeper"
        if [[ ! -x "$binary" ]]; then
            cp /bin/sleep "$binary"
            codesign -s - -f "$binary" >/dev/null 2>&1 || true
        fi
        HERDR_ENV=1 HERDR_PANE_ID=w1:p3 HERDR_TAB_ID=w1:t1 HERDR_WORKSPACE_ID=w1 "$binary" 86400 &
    else
        /bin/sleep 86400 &
    fi
    echo "$!" >> "$keepers"
}

# pid 가 재사용됐을 수 있으니 이 스크립트가 띄운 종류(pulse·sleep·herdr keeper)일 때만 죽인다.
kill_if_ours() {
    local pid="$1" comm
    comm="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    case "${comm##*/}" in
        pulse|sleep|.herdr-keeper) kill "$pid" 2>/dev/null || true ;;
    esac
}

kill_run_processes() {
    local pid
    if [[ -f "$pid_file" ]]; then
        pid="$(cat "$pid_file")"
        [[ -n "$pid" ]] && kill_if_ours "$pid"
    fi
    if [[ -f "$keepers_file" ]]; then
        while read -r pid; do
            [[ -n "$pid" ]] && kill_if_ours "$pid"
        done < "$keepers_file"
    fi
}

render_into() {
    local out="$1" sessions="$2"
    if [[ -e "$out" ]] && [[ -n "$(ls -A "$out" 2>/dev/null)" ]]; then
        echo "render: 비어 있지 않은 디렉터리입니다 · $out" >&2
        return 1
    fi
    mkdir -p "$out/sessions" "$out/projects" "$out/deadhd-state" "$out/pages" "$data_dir"
    local keepers="$out/.demo-keepers"
    : > "$keepers"

    local now key sid slug pid index=0 template
    local pids=()
    if [[ -n "${DEMO_PIDS:-}" ]]; then
        IFS=',' read -r -a pids <<< "$DEMO_PIDS"
    fi
    now=$(date +%s)

    while IFS=$'\t' read -r key sid slug; do
        [[ -z "${key:-}" ]] && continue
        [[ "${key:0:1}" == "#" ]] && continue
        if (( ${#pids[@]} > 0 )); then
            pid="${pids[$((index % ${#pids[@]}))]}"
        else
            if [[ "$key" == "docs-site" ]]; then
                spawn_keeper "$keepers" herdr
            else
                spawn_keeper "$keepers"
            fi
            pid="$!"
        fi
        render_file "$demo_root/claude-config/sessions/$key.json.template" \
            "$out/sessions/$pid.json" "$pid" "$sid" "$now"
        mkdir -p "$out/projects/$slug"
        template="$(require_localized "claude-config/projects/$slug/transcript.jsonl.template")" || return 1
        render_file "$template" \
            "$out/projects/$slug/$sid.jsonl" "$pid" "$sid" "$now"
        # deadhd 파일은 원본에도 없는 세션이 있어, 두 언어판 모두 없을 때만 건너뛴다.
        if [[ -f "$demo_root/deadhd-state/$key.json.template" || -f "$locale_root/deadhd-state/$key.json.template" ]]; then
            template="$(require_localized "deadhd-state/$key.json.template")" || return 1
            render_file "$template" \
                "$out/deadhd-state/$sid.json" "$pid" "$sid" "$now"
        fi
        if [[ -f "$demo_root/deadhd-data/$key.json.template" || -f "$locale_root/deadhd-data/$key.json.template" ]]; then
            template="$(require_localized "deadhd-data/$key.json.template")" || return 1
            render_file "$template" \
                "$data_dir/$key.json" "$pid" "$sid" "$now"
        fi
        if [[ -f "$demo_root/pages/$key.json.template" || -f "$locale_root/pages/$key.json.template" ]]; then
            template="$(require_localized "pages/$key.json.template")" || return 1
            render_file "$template" \
                "$out/pages/$key.json" "$pid" "$sid" "$now"
        fi
        index=$((index + 1))
    done < "$sessions"
}

start() {
    parse_args "$@"
    [[ -z "$render_dir" ]] || { usage >&2; exit 2; }

    if (( dry_run )); then
        local lang_env=""
        [[ -n "$lang" ]] && lang_env="PULSE_LANG=$lang "
        echo "${lang_env}CLAUDE_CONFIG_DIR=\"$run_dir\" DEADHD_STATE_DIR=\"$state_dir\" PULSE_PAGES_DIR=\"$run_dir/pages\" \"$app_bin\" &"
        return 0
    fi

    # open 은 환경 변수를 넘기지 못해 번들 안 실행 파일을 직접 띄운다.
    if pgrep -x pulse >/dev/null 2>&1; then
        if (( replace )); then
            pkill -x pulse || true
            sleep 1
        else
            echo "이미 실행 중인 pulse 프로세스가 있습니다. 사용자 것일 수 있어 끄지 않습니다." >&2
            echo "--replace 를 주면 그 프로세스를 끄고 데모 Pulse 를 띄웁니다." >&2
            exit 1
        fi
    fi

    if [[ ! -x "$app_bin" ]]; then
        "$root/scripts/bundle.sh"
    fi

    kill_run_processes
    rm -rf "$run_dir"
    local sessions="$demo_root/sessions.tsv"
    (( many )) && sessions="$demo_root/sessions-many.tsv"
    render_into "$run_dir" "$sessions"
    # fire 가 start 가 고른 언어를 따르도록 남긴다.
    echo "${lang:-ko}" > "$run_dir/lang"
    env ${lang:+PULSE_LANG="$lang"} CLAUDE_CONFIG_DIR="$run_dir" DEADHD_STATE_DIR="$state_dir" PULSE_PAGES_DIR="$run_dir/pages" "$app_bin" &
    echo "$!" > "$pid_file"
    echo "데모 Pulse 시작 · CLAUDE_CONFIG_DIR=$run_dir · 언어=${lang:-ko}"
}

fire_attention() {
    local now="$1" sid slug="-Users-demo-projects-search-service" pid
    sid=$(uuidgen | tr '[:upper:]' '[:lower:]')
    spawn_keeper "$keepers_file"
    pid="$!"
    render_file "$demo_root/fire/attention.json.template" \
        "$run_dir/sessions/$pid.json" "$pid" "$sid" "$now"
    mkdir -p "$run_dir/projects/$slug"
    local template
    template="$(require_localized "fire/attention.jsonl.template")" || exit 1
    render_file "$template" \
        "$run_dir/projects/$slug/$sid.jsonl" "$pid" "$sid" "$now"
    echo "확인 필요 세션 추가 · search-service"
}

fire_done() {
    local now="$1" sid slug="-Users-demo-projects-release-tool" pid
    sid=$(uuidgen | tr '[:upper:]' '[:lower:]')
    spawn_keeper "$keepers_file"
    pid="$!"
    mkdir -p "$run_dir/projects/$slug"
    local template
    template="$(require_localized "fire/done.jsonl.template")" || exit 1
    render_file "$template" \
        "$run_dir/projects/$slug/$sid.jsonl" "$pid" "$sid" "$now"
    render_file "$demo_root/fire/done-working.json.template" \
        "$run_dir/sessions/$pid.json" "$pid" "$sid" "$now"
    # 끝남 카드는 직전 갱신에서 「진행 중」이던 세션에만 뜬다(폴링 3초). 먼저 진행 중으로 보이게 둔 뒤 끝남으로 바꾼다.
    sleep 5
    render_file "$demo_root/fire/done-idle.json.template" \
        "$run_dir/sessions/$pid.json" "$pid" "$sid" "$(date +%s)"
    echo "끝남 세션 추가 · release-tool"
}

fire() {
    local kind="${1:-}"
    if [[ ! -f "$pid_file" ]]; then
        echo "fire: 먼저 scripts/demo.sh start 를 실행하세요" >&2
        exit 1
    fi
    lang="$(cat "$run_dir/lang" 2>/dev/null || true)"
    case "$lang" in
        en) locale_root="$demo_root/en" ;;
        *) lang="ko"; locale_root="$demo_root" ;;
    esac
    local now
    now=$(date +%s)
    case "$kind" in
        done) fire_done "$now" ;;
        attention) fire_attention "$now" ;;
        both)
            fire_attention "$now"
            fire_done "$now"
            ;;
        *) usage; exit 2 ;;
    esac
}

stop() {
    kill_run_processes
    rm -rf "$run_dir" "$data_dir"
    echo "데모 Pulse 종료 · 실행용 사본 삭제"
}

command="${1:-}"
case "$command" in
    start) shift; start "$@" ;;
    render)
        shift
        parse_args "$@"
        [[ -n "$render_dir" ]] || { usage >&2; exit 2; }
        sessions="$demo_root/sessions.tsv"
        (( many )) && sessions="$demo_root/sessions-many.tsv"
        render_into "$render_dir" "$sessions"
        ;;
    fire) shift; fire "${1:-}" ;;
    stop) stop ;;
    *) usage; exit 2 ;;
esac
