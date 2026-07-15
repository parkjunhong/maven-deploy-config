#!/usr/bin/env bash

echo
echo "##############################################################"
echo "### -------------------- status.sh ------------------------ ###"
echo "### -------------------- status.sh ------------------------ ###"
echo "### -------------------- status.sh ------------------------ ###"
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
  echo "  -h,  --help : 도움말을 출력합니다."
  echo
}


## 파라미터 읽기
while [ "$1" != "" ]; do
	case $1 in
		-h | --help)	 
			usage "--help"
			exit 0
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

# 👤 [추가] sudo 실행 여부와 관계없이 실제 계정의 UID/GID를 환경 변수로 내보냅니다.
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

# eval을 사용하지 않고, 공백이 포함될 수 있는 경로를 쌍따옴표로 안전하게 감싸서 직접 실행합니다.
{
  ${COMPOSE_CMD} -f "${COMPOSE_YML}" ps
  echo "[SUCCESS] ${COMPOSE_CMD} -f \"${COMPOSE_YML}\" ps"
} || {
  echo "[FAIL] ${COMPOSE_CMD} -f \"${COMPOSE_YML}\" ps"
  exit 1 # 명령어 실패 시 스크립트를 중단하는 것이 안전합니다.
}

echo
echo "=============================================================================================="

exit 0
