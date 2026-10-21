#!/bin/bash
# README 그림용 데모 세션. 사용자 설정(~/.claude)은 건드리지 않고 demo/.run/ 사본만 쓴다.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
demo_root="$root/demo"
run_dir="$demo_root/.run"
state_dir="$run_dir/deadhd-state"
pid_file="$run_dir/pulse.pid"
keepers_file="$run_dir/.demo-keepers"
bundle="$root/build/Pulse.app"
app_bin="$bundle/Contents/MacOS/pulse"

usage() {
    cat <<'TEXT'
사용법:
  scripts/demo.sh start [--dry-run] [--replace]   실행용 사본을 만들고 데모 Pulse 를 띄운다
  scripts/demo.sh render <디렉터리>               템플릿을 현재 시각으로 전개한다
  scripts/demo.sh fire done                       새 「끝남」 세션으로 끝남 카드를 띄운다
  scripts/demo.sh fire attention                  새 「확인 필요」 세션으로 카드를 띄운다
  scripts/demo.sh fire both                       둘 다 넣어 여러 장 카드를 띄운다
  scripts/demo.sh stop                            데모 Pulse 와 실행용 사본을 정리한다

데모 Pulse 는 실제 Pulse 와 같은 설정 저장소를 쓴다. 확인(ack) 기록이 섞일 수 있으니
그림을 다 찍으면 stop 으로 끈다.
TEXT
}

iso_at() {
    date -u -r "$1" +"%Y-%m-%dT%H:%M:%SZ"
}

render_file() {
    local template="$1" output="$2" pid="$3" sid="$4" now="$5"
    local spec label offset
    local args=(-e "s|__PID__|$pid|g" -e "s|__SESSION_ID__|$sid|g")
    for spec in NOW:0 S30:30 M1:60 M2:120 M3:180 M4:240 M5:300 M8:480 M9:540 M12:720 M22:1320 M35:2100; do
        label="${spec%%:*}"
        offset="${spec#*:}"
        args+=(-e "s|__ISO_${label}__|$(iso_at $((now - offset)))|g")
        args+=(-e "s|__MS_${label}__|$(((now - offset) * 1000))|g")
    done
    sed "${args[@]}" "$template" > "$output"
}

spawn_keeper() {
    /bin/sleep 86400 &
    echo "$!" >> "$1"
}

# pid 가 재사용됐을 수 있으니 이 스크립트가 띄운 종류(pulse·sleep)일 때만 죽인다.
kill_if_ours() {
    local pid="$1" comm
    comm="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    case "${comm##*/}" in
        pulse|sleep) kill "$pid" 2>/dev/null || true ;;
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
    local out="$1"
    if [[ -e "$out" ]] && [[ -n "$(ls -A "$out" 2>/dev/null)" ]]; then
        echo "render: 비어 있지 않은 디렉터리입니다 · $out" >&2
        return 1
    fi
    mkdir -p "$out/sessions" "$out/projects" "$out/deadhd-state"
    local keepers="$out/.demo-keepers"
    : > "$keepers"

    local now key sid slug pid index=0
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
            spawn_keeper "$keepers"
            pid="$!"
        fi
        render_file "$demo_root/claude-config/sessions/$key.json.template" \
            "$out/sessions/$pid.json" "$pid" "$sid" "$now"
        mkdir -p "$out/projects/$slug"
        render_file "$demo_root/claude-config/projects/$slug/transcript.jsonl.template" \
            "$out/projects/$slug/$sid.jsonl" "$pid" "$sid" "$now"
        if [[ -f "$demo_root/deadhd-state/$key.json.template" ]]; then
            render_file "$demo_root/deadhd-state/$key.json.template" \
                "$out/deadhd-state/$sid.json" "$pid" "$sid" "$now"
        fi
        index=$((index + 1))
    done < "$demo_root/sessions.tsv"
}

start() {
    local dry_run=0 replace=0 arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run) dry_run=1 ;;
            --replace) replace=1 ;;
            *) usage; exit 2 ;;
        esac
    done

    if (( dry_run )); then
        echo "CLAUDE_CONFIG_DIR=\"$run_dir\" DEADHD_STATE_DIR=\"$state_dir\" \"$app_bin\" &"
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
    render_into "$run_dir"
    CLAUDE_CONFIG_DIR="$run_dir" DEADHD_STATE_DIR="$state_dir" "$app_bin" &
    echo "$!" > "$pid_file"
    echo "데모 Pulse 시작 · CLAUDE_CONFIG_DIR=$run_dir"
}

fire_attention() {
    local now="$1" sid slug="-Users-demo-projects-search-service" pid
    sid=$(uuidgen | tr '[:upper:]' '[:lower:]')
    spawn_keeper "$keepers_file"
    pid="$!"
    render_file "$demo_root/fire/attention.json.template" \
        "$run_dir/sessions/$pid.json" "$pid" "$sid" "$now"
    mkdir -p "$run_dir/projects/$slug"
    render_file "$demo_root/fire/attention.jsonl.template" \
        "$run_dir/projects/$slug/$sid.jsonl" "$pid" "$sid" "$now"
    echo "확인 필요 세션 추가 · search-service"
}

fire_done() {
    local now="$1" sid slug="-Users-demo-projects-release-tool" pid
    sid=$(uuidgen | tr '[:upper:]' '[:lower:]')
    spawn_keeper "$keepers_file"
    pid="$!"
    mkdir -p "$run_dir/projects/$slug"
    render_file "$demo_root/fire/done.jsonl.template" \
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
    rm -rf "$run_dir"
    echo "데모 Pulse 종료 · 실행용 사본 삭제"
}

command="${1:-}"
case "$command" in
    start) shift; start "$@" ;;
    render)
        [[ -n "${2:-}" ]] || { usage; exit 2; }
        render_into "$2"
        ;;
    fire) shift; fire "${1:-}" ;;
    stop) stop ;;
    *) usage; exit 2 ;;
esac
