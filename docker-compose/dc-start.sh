#!/usr/bin/env bash

echo
echo "##############################################################"
echo "### -------------------- start.sh ------------------------ ###"
echo "### -------------------- start.sh ------------------------ ###"
echo "### -------------------- start.sh ------------------------ ###"
echo "##############################################################"

usage() {
  local FILENAME=$(basename "$0")
  
  if [ ! -z "$1" ]; then
    local indent=10
    local formatl=" - %-"$indent"s: %s\n"
    local formatr=" - %"$indent"s: %s\n"
    echo
    echo "================================================================================"
    printf "$formatl" "filename" "$FILENAME"
    printf "$formatl" "line" "$2"
    printf "$formatl" "callstack"
    local idx=1
    for func in ${FUNCNAME[@]:1}
    do
      printf "$formatr" "["$idx"]" $func
      ((idx++))
    done
    printf "$formatl" "cause" "$1"
    echo "================================================================================"
  fi
  
  echo
  echo "[Usage]"
  echo "  ./$FILENAME [-h] [-it]"
  echo
  echo "[Options]"
  echo "  -h,  --help             : 도움말을 출력합니다."
  echo "  -it, --interactive-tty  : 백그라운드(-d) 실행을 생략하고 포그라운드(Interactive TTY) 모드로 실행합니다."
  echo
}


INTERACTIVE_TTY=0
## 파라미터 읽기
while [ "$1" != "" ]; do
	case $1 in
		-h | --help)	 
			usage "--help"
			exit 0
			;;
    -it | --interactive-tty)
      INTERACTIVE_TTY=1
      ;;
		*)
			usage "Invalid option. option: $1"
			exit 1
			;;
	esac
	shift
done

##
# 시스템에 설치된 Docker Compose 명령어를 찾아 반환합니다.
# V2(docker compose)를 우선시하며, 없으면 V1(docker-compose)을 반환합니다.
##
get_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    echo "" # 둘 다 없으면 빈 문자열 반환
  fi
}

COMPOSE_CMD=$(get_compose_cmd)
if [ -z "$COMPOSE_CMD" ]; then
  echo "[ERROR] Docker Compose를 찾을 수 없습니다." >&2
  exit 1
fi

INSTALL_DIR="${install.dir}"
APP_NAME="${application.name}"
COMPOSE_YML="${INSTALL_DIR}/docker-compose.yml"

echo
echo "=============================================================================================="
echo "DIRECTORY: ${INSTALL_DIR}"
echo "APP_NAME : ${APP_NAME}"
echo "COMPOSE  : ${COMPOSE_CMD}"

# 👤 sudo 실행 여부와 관계없이 실제 계정의 정보(UID/GID, HOME, TIMEZONE, LOCALE)를 환경 변수로 내보냅니다.
ACTUAL_USER=${SUDO_USER:-$USER}
export HOST_UID=$(id -u "${ACTUAL_USER}")
export HOST_GID=$(id -g "${ACTUAL_USER}")
export HOST_USER_NAME=${ACTUAL_USER}
export HOST_USER_HOME=$(getent passwd $ACTUAL_USER | cut -d: -f6)
export HOST_TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Asia/Seoul" )
# 👇 추가: 호스트의 런타임 로케일 정보 추출 (기본값 안전장치 포함)
export HOST_LANG=${LANG:-"ko_KR.UTF-8"}

echo "HOST_NAME: ${HOST_USER_NAME} (UID: ${HOST_UID}, GID: ${HOST_GID})"
echo "USER_HOME: ${HOST_USER_HOME}"
echo "TIMEZONE : ${HOST_TIMEZONE}"
echo "LANG     : ${HOST_LANG}"

# 🌟 로컬 저장소에서 가장 최근에 생성된 이미지의 태그를 자동 감지
IMAGE_NAME="${build.name}"
# docker images 명령어는 기본적으로 생성일(최신순) 기준으로 정렬됩니다.
# latest 태그를 제외한 목록 중 가장 첫 번째(최신) 태그를 추출합니다.
DETECTED_TAG=$(docker images "${IMAGE_NAME}" --format '{{.Tag}}' | grep -v '^latest$' | head -n 1)
# 감지된 태그가 있으면 사용하고, 아예 없으면 기본값(latest)을 사용합니다.
export IMAGE_TAG=${DETECTED_TAG:-latest}

# -----------------------------------------------------------------------------
# 🌟 [자동화] docker-compose.yml의 volumes 항목에서 호스트 경로 동적 추출 및 생성
# -----------------------------------------------------------------------------
echo "Check and create volume directories from docker-compose.yml..."

# 1. grep: 공백 후 '- ' 기호 뒤에 절대경로('/')나 상대경로('./', '../')로 시작하는 볼륨 매핑 라인 추출
# 2. awk : ':' 구분자로 분리하여 첫 번째 필드(호스트 경로 영역)만 선택
# 3. sed : 앞부분의 여백과 '- ' 기호를 깔끔하게 제거
# 4. tr  : 혹시 모를 따옴표(", ') 제거
HOST_PATHS=$(grep -E '^\s*-\s*(\/|\.\/|\.\.\/)' "${COMPOSE_YML}" | awk -F':' '{print $1}' | sed 's/^[ \t]*-[ \t]*//' | tr -d '"'\''')

# 추출된 경로들을 순회하며 존재하지 않을 경우 현재 사용자 권한으로 생성
for HOST_PATH in $HOST_PATHS; do
  if [ ! -d "${HOST_PATH}" ]; then
    echo " - Create directory: ${HOST_PATH}"
    mkdir -p "${HOST_PATH}"
  fi  
done
# -----------------------------------------------------------------------------

# 1. 'up' 명령어에 추가할 옵션을 담을 배열 선언 (기본은 빈 배열)
UP_OPTS=()

# 2. 조건에 따라 배열에 '-d' 옵션 추가 (변수 참조 시 '$' 기호 추가)
if [ "$INTERACTIVE_TTY" -eq 0 ]; then
    UP_OPTS=("-d")
fi

# 3. 중복을 제거한 단일 실행 블록
# 공백이 포함될 수 있는 경로를 쌍따옴표로 안전하게 감싸서 직접 실행합니다.
{
    # "${UP_OPTS[@]}"는 배열이 비어있으면 아무것도 출력하지 않고, 요소가 있으면 안전하게 확장
    ${COMPOSE_CMD} -f "${COMPOSE_YML}" up "${UP_OPTS[@]}"
    
    # 로그 출력 시에는 ${UP_OPTS[*]}를 사용하여 배열 요소를 하나의 문자열로 출력
    echo "[SUCCESS] ${COMPOSE_CMD} -f \"${COMPOSE_YML}\" up ${UP_OPTS[*]}"
} || {
    echo "[FAIL] ${COMPOSE_CMD} -f \"${COMPOSE_YML}\" up ${UP_OPTS[*]}"
    exit 1
}

echo
echo "=============================================================================================="

exit 0

