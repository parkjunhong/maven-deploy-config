#!/usr/bin/env bash

echo
echo "##############################################################"
echo "### -------------------- start.sh ------------------------ ###"
echo "### -------------------- start.sh ------------------------ ###"
echo "### -------------------- start.sh ------------------------ ###"
echo "##############################################################"

usage(){
	echo
	echo ">>> CALLED BY [[ $1 ]]"
	echo
	echo "[Usage]"
	echo
	echo "./start.sh [-h]"
	echo
	echo "[Option]"
	echo " -h, --help   : 도움말"
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

# 👤 sudo 실행 여부와 관계없이 실제 계정의 UID/GID를 환경 변수로 내보냅니다.
ACTUAL_USER=${SUDO_USER:-$USER}
export HOST_UID=$(id -u "${ACTUAL_USER}")
export HOST_GID=$(id -g "${ACTUAL_USER}")
export HOST_USER_NAME=${ACTUAL_USER}
export HOST_USER_HOME=$(getent passwd $ACTUAL_USER | cut -d: -f6)
export HOST_TIMEZONE=$(timedatectl show --property=Timezone --value)
echo "HOST_USER: ${ACTUAL_USER} (UID: ${HOST_UID}, GID: ${HOST_GID}), USER_HOME: ${HOST_USER_HOME}, TIMEZONE: ${HOST_TIMEZONE}"

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

# eval을 사용하지 않고, 공백이 포함될 수 있는 경로를 쌍따옴표로 안전하게 감싸서 직접 실행합니다.
{
  ${COMPOSE_CMD} -f "${COMPOSE_YML}" up -d
  echo "[SUCCESS] ${COMPOSE_CMD} -f \"${COMPOSE_YML}\" up -d"
} || {
  echo "[FAIL] ${COMPOSE_CMD} -f \"${COMPOSE_YML}\" up -d"
  exit 1 # 명령어 실패 시 스크립트를 중단하는 것이 안전합니다.
}

echo
echo "=============================================================================================="

exit 0

