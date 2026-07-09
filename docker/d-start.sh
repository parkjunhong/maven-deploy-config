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
  echo " dockker container 내부에서 실행되는 스크립트입니다."
  echo " Dockerfile 에서 'COPY d-start.sh ./start.sh'로 복사합니다."
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

INSTALL_DIR="${install.dir}"

# 1. 경로 공백 보호 및 이동 실패 시 방어 로직 추가
cd "${INSTALL_DIR}" || {
    echo "[ERROR] 디렉토리 이동 실패: ${INSTALL_DIR}"
    exit 1
}

## Java 확인
# 2. 가장 안전한 방식의 명령어 존재 여부 검증
if ! command -v java >/dev/null 2>&1; then
    echo "[ERROR] Java를 찾을 수 없습니다. (PATH에 존재하지 않음)"
    echo "Need JDK/JRE 25 or higher"
    exit 1
fi
JAVA_PATH=$(command -v java)

JAVA_OPTS="${java.parameters}"
EXEC_FILE="${execution.filename}"
APP_NAME="${application.name}"
APP_OPTS="${application.parameters}  --infra.deployment.type=container"

# begin: 커스터마이징 !!!
# end: 커스터마이징 !!!

echo
echo "=============================================================================================="
echo "DIRECTORY: ${INSTALL_DIR}"
echo "EXEC_FILE: ${EXEC_FILE}"
echo "APP_NAME : ${APP_NAME}"
echo "APP_OPTS : ${APP_OPTS}"
echo "JAVA_PATH: ${JAVA_PATH}"
echo "JAVA_OPTS: ${JAVA_OPTS}"

EXEC_ARGS=(
  "-jar"
  "-Dname=${APP_NAME}"
  ${JAVA_OPTS}
  "${EXEC_FILE}"
  ${APP_OPTS}
)

{
    # 3. eval을 제거하고 직접 실행. (Docker 환경에서는 exec를 사용하여 PID 1을 Java로 위임합니다.)
    echo "Starting Java application..."
    echo "Command: exec \"${JAVA_PATH}\" \"${EXEC_ARGS[@]}\""
    
    exec "${JAVA_PATH}" "${EXEC_ARGS[@]}"
    
} || {
    echo "[FAIL] Failed to execute command."
    echo "Command: exec \"${JAVA_PATH}\" \"${EXEC_ARGS[@]}\""
    exit 1
}

echo
echo "=============================================================================================="

exit 0

