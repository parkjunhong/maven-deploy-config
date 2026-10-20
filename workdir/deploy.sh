#!/usr/bin/env bash
# =======================================
# @author   : parkjunhong77@gmail.com
# @title    : Deploy Service Script
# @license  : Apache License 2.0
# @since    : 2026-07-03
# @desc     : support RHEL 6, 7, 8, 9 / Oracle Linux 7, 8, 9, 10 / Ubuntu 16, 18, 20, 22, 24 / RockyOS 9, 10
# @installation : 
#   1. insert 'source <path>/deploy.sh" into ~/bin/.bashrc or ~/bin/.bash_profile for a personal usage.
#   2. copy the above file to /etc/bash_completion.d/ or insert 'source <path>/deploy.sh' into 
# etc/bashrc for all users.
# =======================================

# 오류 발생시 즉시 종료
set -e

##
# 스크립트 도움말 출력 함수
#
# @param $1 {string} 발생한 오류의 원인 (cause)
# @param $2 {number} 오류가 발생한 라인 번호
#
# @return 없음 (표준 출력으로 도움말 표시)
##
help() {
  local FILENAME=$(basename $0)
  if [ ! -z "$1" ]; then
    local indent=10
    local formatl=" - %-${indent}s: %s\n"
    local formatr=" - %${indent}s: %s\n"
    echo
    echo "================================================================================"
    printf "$formatl" "filename" "$FILENAME"
    printf "$formatl" "line" "$2"
    printf "$formatl" "callstack"
    local idx=1
    for func in ${FUNCNAME[@]:1}; do  
      printf "$formatr" "[$idx]" $func
      ((idx++))
    done
    printf "$formatl" "cause" "$1"
    echo "================================================================================"
  fi  
  echo  
  echo "📞 >>> CALLED BY [[ $FILENAME ]]"
  echo
  echo "📖 [Usage]"
  echo " ./$FILENAME -c <configuration> [Options]"
  echo
  echo "⚙️ [Parameters]"
  echo " -c, --config        : (Optional) 설정파일 절대경로. 기본값: service.properties"
  echo " -r, --reg-svc       : O.S 서비스 등록 여부. N: 등록안함, Y: 등록함"
  echo " -s, --start-svc     : 프로그램 자동 시작 여부. N: 자동시작안함, Y: 자동시작함"
  echo ""
  echo "🐳 [Docker Deployment Options]"
  echo " -d, --docker        : Docker 컨테이너 기반으로 배포합니다."
  echo " -o, --build-only    : 컨테이너를 실행(배포)하지 않고 이미지만 생성합니다. (--docker 필요)"
  echo " -i, --offline-image : 환경을 위해 미리 생성된 Docker 이미지(tar)를 로드합니다. (--docker 필요)"
  echo ""
  echo "🛠️ [Options]"
  echo " -h, --help          : 도움말"
  echo
  echo "🖥️  ================ OPERATING SYSTEM INFORMATION ================ "
  cat /etc/*-release 2>/dev/null || echo "❌ OS Information not available"
  echo " =============================================================== "
}

support_msg() {
  echo
  echo "🖥️  ================ OPERATING SYSTEM INFORMATION ================ "
  echo
  echo "✅ Supporting System: CentOS 6, 7 and higher / Ubuntu 16, 18, 20 and higher / Red Had 6, 7, 8, 9 and higher / Oracle Linux 7, 8, 9 or higher "
  echo
  echo " -------------------------------------------------------------- "
  cat /etc/*-release 2>/dev/null || echo "❌ OS Information not available"
  echo " -------------------------------------------------------------- "
  echo " =============================================================== "
}

# 입력받은 경로를 절대 경로로 변경합니다.
normalize_path() {
    local path="$1"
    
   if [[ $# -eq 0 || "$path" =~ ^[[:space:]]*$ ]]; then
        echo "abspath: invalid empty path" >&2
        return 1
    fi

    if command -v realpath >/dev/null 2>&1; then
        realpath -m -- "$path"
    else
        readlink -m -- "$path"
    fi
}

# 기본설정 파일
CONFIG_FILE="service.properties"
SERVICE_REGISTERED=""
SERVICE_AUTO_START=""

# Docker 옵션 초기화
DOCKER_MODE="N"
BUILD_ONLY="N"
OFFLINE_IMAGE=""

## 파라미터 읽기
while [ "$1" != "" ]; do
  case $1 in
  -c | --config)
    shift
    CONFIG_FILE=$1
    ;;
  -r | --reg-svc)
    shift
    case $1 in
    y | Y) SERVICE_REGISTERED="Y" ;;
    n | N) SERVICE_REGISTERED="N" ;;
    esac
    ;;
  -s | --start-svc)
    shift
    case $1 in
    y | Y) SERVICE_AUTO_START="Y" ;;
    n | N) SERVICE_AUTO_START="N" ;;
    esac
    ;;
  -d | --docker)
    DOCKER_MODE="Y"
    ;;
  -o | --build-only)
    if [ -f "$OFFLINE_IMAGE" ]; then
      help "'-o | --build-only' 옵션과 '-i | --offline-image' 옵션은 동시에 사용할 수 없습니다." $LINENO
      exit 1
    fi 
    BUILD_ONLY="Y"
    ;;
  -i | --offline-image)
    if [ "$BUILD_ONLY" = "Y" ]; then
      help "'-i | --offline-image' 옵션과 '-o | --build-only' 옵션은 동시에 사용할 수 없습니다." $LINENO
      exit 1
    fi
    
    shift
    OFFLINE_IMAGE=$1
    if [ ! -f "$OFFLINE_IMAGE" ]; then
      help "오프라인 이미지 파일을 찾을 수 없습니다: $OFFLINE_IMAGE" $LINENO
      exit 1
    fi
    ;;
  -h | --help)
    help "" ""
    exit 0
    ;;
  *)
    help "지원하지 않는 옵션입니다: $1" $LINENO
    exit 1
    ;;
  esac
  shift
done

##
# 디렉토리 생성(중간 경로 포함)을 보장하는 함수
#
# @param $1 {string} 생성할 디렉토리 경로
#
# @return 없음
##
ensure_dir() {
  local target_dir="$1"
  if [ ! -d "$target_dir" ]; then
    mkdir -p "$target_dir" || sudo mkdir -p "$target_dir"
  fi
}

# $1 {string} variable name
# $2 {any} value
assign() {
  eval $1=\"$2\"
}


# Assigns a value input by a user to variable.
# $1 {string} Question Message.
# $2 {string} varaible
read_cli() {
  local variable="$2"
  local confirm="N"
  local answer=""

  while [ "$confirm" != "Y" ]; do
    echo
    read -p "$1 -> " answer
    read -p "Your answer is '$answer'. Right? [Y/N] -> " confirm
    local confirm=$(echo $confirm | tr [:lower:] [:upper:])
  done

  assign "$variable" "$answer"
}

# Loads OS name and OS version.
load_os_info() {
  # CentOS 7 or higher, Ubuntu 16 or higher, Red Hat 6 or higher, Oracle Linux 7 or higher
  local releasefile="/etc/os-release"

  if [ -f "$releasefile" ]; then
    echo
    echo "📄 ---> read $releasefile"
    OS_NAME=$(grep -v "#" /etc/os-release | grep -i "^id=" | sed -e "s/\"//g" | sed -e "s/id=//gi" | tr '[:upper:]' '[:lower:]')
    OS_VERSION=$(grep -v "#" /etc/os-release | grep -i "^VERSION_ID=" | sed -e "s/\"//g" | sed -e "s/VERSION_ID=//gi" | tr -dc '0-9.' | cut -d \. -f1)
  else
    # CentOS 6
    local releasefile="/etc/centos-release"
    if [ -f "$releasefile" ]; then
      echo
      echo "📄 ---> read $releasefile"
      OS_NAME=$(grep -v "#" /etc/centos-release | awk {'print $1'} | tr '[:upper:]' '[:lower:]')
      OS_VERSION=$(grep -v "#" /etc/centos-release | tr -dc '0-9.' | cut -d \. -f1)
    else
      support_msg
      echo
      read -p "Insert your OS Name. (See 'OPERATING SYSTEM INFORMATION' above.) " OS_NAME
      read -p "Insert your OS version (only Major value). (See 'OPERATING SYSTEM INFORMATION' above.) " OS_VERSION
    fi
  fi

  echo
  echo "📌 OS Name="${OS_NAME}
  echo "📌 OS Verson="${OS_VERSION}
}

# $1 {string} Question message.
# $2 {string} "Y"es string.
# $3 {string} "N"o string.
# $4 {string} response variable
yesOrNo() {
  local yesorno_answer=""
  while [ -z $yesorno_answer ] || ([ "$2" != "$yesorno_answer" ] && [ "$3" != "$yesorno_answer" ]); do
    echo
    read -p "$1 [$2/$3] ? " yesorno_answer

    local yesorno_answer=$(echo $yesorno_answer | tr [:lower:] [:upper:])
  done

  assign "$4" "$yesorno_answer"
}

# Pattern: ${...}
GLOBAL_REMATCH=""

# $1 {string} string
# $2 {string} regular expression
global_rematch() {
  GLOBAL_REMATCH=""
  local str="$1"
  local regex="$2"

  while [[ "$str" =~ $regex ]]; do
    GLOBAL_REMATCH+="${BASH_REMATCH[1]} "
    str="${str#*"${BASH_REMATCH[1]}"}"
  done

  GLOBAL_REMATCH="${GLOBAL_REMATCH% }" # 마지막 공백 제거
}

# 프로퍼티 발견 여부
RTV_PROP_CNT=0
# 프로퍼티 값
RTV_PROP_VAL=""
## 설정파일 읽기
# $1 {string} file
# $2 {string} prop_name
# $3 {any} default_value
prop() {
  local property=""

  # 프로퍼티 존재 여부 확인
  local cnt=$(grep -v -e "^#" ${1} | grep -e "^${2}=" | wc -l)
  if [ $cnt -lt 1 ]; then
    # 기본값을 전달받은 경우
    if [ ! -z "$3" ]; then
      RTV_PROP_CNT=1
      RTV_PROP_VAL="$3"
    else
      RTV_PROP_CNT=0
      RTV_PROP_VAL="$property"
    fi
    return
  fi

  # 프로퍼티 존재 설정
  RTV_PROP_CNT=1

  # 1. profile 에 기반한 설정부터 조회
  if [ ! -z "${1}" ]; then
    local property=$(grep -v -e "^#" ${1} | grep -e "^${2}\.${PROFILE}=" | cut -d"=" -f2-)
  fi

  # 2. profile에 기반한 설정이 없는 경우 기본 설정조회
  if [ -z "${property}" ]; then
    local property=$(grep -v -e "^#" ${1} | grep -e "^${2}=" | cut -d"=" -f2-)

    # 3. 기본설정이 없고 함수 호출시 기본값이 있는 경우
    if [ -z "${property}" ] && [ ! -z "$3" ]; then
      RTV_PROP_VAL="$3"
    else
      RTV_PROP_VAL="${property}"
    fi
  else
    RTV_PROP_VAL="${property}"
  fi
}

#
# @param $1 {string} property name
check_sys_prop() {
  case "$1" in
  "sys:user.home")
    echo ${HOME}
    ;;
  "sys:username")
    echo $(id -u -n)
    ;;
  *) ;;
  esac
}

REGEX_PROP_REF="\\\$\{([^\}]+)\}"
# $1 {string} absolute file path.
# $2 {string} prop_name
# $3 {any} default_value
read_prop() {
  prop "$1" "$2" "$3"
  local property="$RTV_PROP_VAL"
  global_rematch "${property}" "$REGEX_PROP_REF"

  if [ -z "$GLOBAL_REMATCH" ]; then
    if [ $RTV_PROP_CNT -eq 1 ]; then
      echo ${property}
    else
      echo "\${$2}"
    fi
  else
    local references=($(echo $GLOBAL_REMATCH))
    for ref in "${references[@]}"; do
      # check system property
      local ref_value=$(check_sys_prop ${ref})
      if [ ! -z "${ref_value}" ]; then
        property=${property//\$\{$ref\}/$ref_value}
      else
        local ref_value=$(read_prop "$1" "$ref")
        if [ ! -z "$ref_value" ]; then
          property=${property//\$\{$ref\}/$ref_value}
        elif [ $RTV_PROP_CNT -eq 1 ]; then
          property=${property//\$\{$ref\}/$ref_value}
        fi
      fi
    done
    echo ${property}
  fi
}

# Replace a old string to a new string.
# $1 {string} file path
# $2 {string} old string
# $3 {string} new string
update_property() {
  local targetfile=$1
  local oldstr=$2
  local safe_oldstr="${oldstr//\./\\.}"
  local newstr=$3
  local safe_newstr="${newstr//\//\\\/}"
  sed -i "s/\${${safe_oldstr}}/${safe_newstr}/g" "$targetfile"
}

# 큰따옴표(") 또는 작은 따옴표(')로 묶은 문자열을 찾는다.
# $1 {string} string
# $2 {string} variable
unwrap_quote() {
  global_rematch "$1" "^\"([^\"]+)\"$"
  if [ -z "$GLOBAL_REMATCH" ]; then
    global_rematch "$1" "^'([^']+)'$"
  fi

  if [ ! -z "$GLOBAL_REMATCH" ]; then
    assign "$2" "$GLOBAL_REMATCH"
  fi
}

# Replace a old string to a new string.
# $1 {string} file path
# $@:1 {any} properties
update_properties() {
  echo
  echo "🛠️ -------- ${FUNCNAME[0]} --------"

  local targetfile="$1"
  local arguments=(${@})
  local prop_value=""

  printf "  %-30s = %s\n" "filename" "${targetfile}"
  printf "  %-30s\n" "------------------------------"

  for prop in "${arguments[@]:1}"; do
    unwrap_quote "$prop" "prop"
    local prop_value=$(read_prop "${CONFIG_FILE}" "$prop")
    printf "  %-30s = %s\n" "$prop" "$prop_value"
    update_property "${targetfile}" "$prop" "$prop_value"
  done

  echo "--------------------------------------"
}

# check a file exists.
# $1 {string} filepath
# $2 {number} exit value
check_file_then_exit() {
  if [ ! -f "$1" ]; then
    echo
    echo "❌ [A file DOES NOT EXIST] file="$1
    exit $2
  fi
}

# check a directory exists.
# $1 {string} directory path
# $2 {number} exit value
check_dir_then_exit() {
  if [ ! -d "$1" ]; then
    echo
    echo "❌ [A directory DOES NOT EXIST] directory="$1
    exit $2
  fi
}

# Build 프로파일 읽기
# $1 {string} 빌드명
load_profile() {
  local build_name="$1"
  ## profile 검증
  if [ -f "./$build_name/.profile" ]; then
    BUILTIN_PROFILE=$(cat ./$build_name/.profile)
  fi

  if [ -z $BUILTIN_PROFILE ]; then
    echo "⚠️ !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "⚠️ !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo
    echo "❌  Cannot find a built-in profile."
    echo "🛑  So cannot verify this installation."

    yesOrNo " Do you want to process this installation" "Y" "N" "ANSWER"

    if [ "$ANSWER" == "N" ]; then
      clean_temp_dir "${build_name}"

      echo
      echo "⛔  +++ INSTALLATION is interrupted... +++"
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

      exit 0
    fi

    read -p " Please, input a new profile name. Or just push the enter key if no profile !!! " PROFILE

    echo "🎯  YOUR PROFILE is ${PROFILE}. "
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  else
    PROFILE=$BUILTIN_PROFILE
  fi
}

# $1 {string} full filepath
# $@:1 {any} properties
update_file() {
  local targetfile=$1

  if [ -f "${targetfile}" ]; then
    echo
    echo "🔎 [DETECTED] ${targetfile}"
    update_properties $@
  fi
}

#
# 배열에 값이 존재하는지 여부를 제공한다
#
# @param $1 {string} 배열 이름
# @param $2 {any} 찾는 값
# @return 'echo' 0: 없음, 1: 있음
contains() {
  local ar=$1
  local val=$2
  local has=0

  for v in $(eval "echo \${${ar}[@]}"); do
    if [ "${v}" == "${val}" ]; then
      has=1
      break
    fi
  done

  echo ${has}
}

## 소스 디렉토리 안의 파일을 대상 디렉토리로 복사
# @param $1 {string} from directory. (fullpath)
# @param $2 {string} to directory. (fullpath)
# @param $3 {string} 복사대상 식별정보
copy_files() {
  local source=$1
  local target=$2
  local filecontainer=$3
  local files=$(ls -ap ${source} | grep -v /)

  ## 'contains' 함수에서 사용하기 위해서 global 변수로 설정
  filesconfig=($(read_prop "${CONFIG_FILE}" "${filecontainer}.configuration.filenames"))
  for file in ${files}; do
    {
      echo "📦 * * * file=$file, container=$filecontainer, filesconfig=${filesconfig[@]}"
      local filesconfigprops=""
      if [ -f "${source}/${file}" ]; then
        if [ "${filesconfig}" == "\*" ]; then
          filesconfigprops=$(read_prop "${CONFIG_FILE}" "${filecontainer}.configuration.properties")
        elif [ $(contains "filesconfig" ${file}) -eq 1 ]; then
          filesconfigprops=$(read_prop "${CONFIG_FILE}" "${file}.configuration.properties")
        fi

        if [ ! -z "$filesconfigprops" ]; then
          update_file "${source}/${file}" "$filesconfigprops"
        fi

        if [ -f ${target} ]; then
          echo
          echo "🚨 ################ INVALID TARGET DIRECTORY ###############"
          echo
          echo "🛑 >>> ${target} is a FILE !!!!"

          exit 1
        fi

        if [ ! -d ${target} ]; then
          mkdir -p ${target}
        fi

        printf "[COPYing] "
        cp -v ${source}/${file} ${target}/
        echo "✅ [SUCCESS] cp ${source}/${file} ${target}/"
      else
        echo "❌ [FAIL] ${source}/${file} does NOT EXIST"
      fi
    } || {
      echo
      echo
      echo "🐛 [Errors] step: 'copy resource file', file: ${file}"
      echo
      echo
      exit 2
    }
  done
}

##
# 원본 스크립트를 서비스 구동 전용 경로로 복사하고, 기존 위치에는 심볼릭 링크를 생성합니다.
#
# @param $1 {string} 원본 설치 파일 경로 (배열의 0번째 요소)
# @param $2 {string} 서비스 실행 파일 경로 (배열의 1번째 요소)
#
# @return 작업 수행 과정 및 결과를 echo 로 출력
##
setup_service_link() {
  local origin_path="$1"
  local target_path="$2"

  echo
  echo "🔗 >>> Setup Symbolic Link Architecture: ${origin_path} -> ${target_path}"

  if [ ! -f "${origin_path}" ]; then
    echo "⏭️   [Skip] Source file does not exist: ${origin_path}"
    return 0
  fi

  local target_dir
  target_dir=$(dirname "${target_path}")
  
  if [ ! -d "${target_dir}" ]; then
    mkdir -p "${target_dir}"
  fi

  cp -vp "${origin_path}" "${target_path}"
  echo "📋  [Step 1] Copied to service path: ${target_path}"

  rm -f "${origin_path}"
  echo "🗑️   [Step 2] Removed original file: ${origin_path}"

  ln -s "${target_path}" "${origin_path}"
  echo "🔗  [Step 3] Created soft link: ${origin_path} -> ${target_path}"
}


#
# 시스템의 서비스 관리 도구(Service Manager / Init System)를 자동 감지합니다.
# @return {string} systemd | sysvinit | unsupported
#
detect_service_manager() {
  # 1. systemd 환경인지 확인 (PID 1 프로세스 확인 및 /run/systemd/system 디렉토리 확인)
  if [ -d /run/systemd/system ] || [ "$(ps -p 1 -o comm= 2>/dev/null)" = "systemd" ]; then
    echo "systemd"
    return 0
  fi

  # 2. 레거시 SysVinit 환경 확인 (필요한 경우에만 유지)
  if command -v chkconfig >/dev/null 2>&1 && command -v service >/dev/null 2>&1; then
    echo "sysvinit"
    return 0
  fi

  echo "unsupported"
  return 1
}

#
# 서비스 템플릿 파일의 변수를 치환하여 배포용 서비스 파일을 생성합니다.
# @param $1 {string} 원본 템플릿 파일 경로
# @param $2 {string} 대상 서비스 전체 경로 (svc_dir/svc_name)
#
render_service_template() {
  local tplfile="$1"
  local target_filepath="$2"
  local tplstring
  tplstring=$(cat "${tplfile}")

  global_rematch "${tplstring}" "$REGEX_PROP_REF"

  if [ -n "$GLOBAL_REMATCH" ]; then
    local properties=($(echo "$GLOBAL_REMATCH"))
    for prop_ref in "${properties[@]}"; do
      local property
      if [ "${prop_ref}" == "service.filepath" ]; then
        property="${target_filepath}"
      else
        property=$(read_prop "${CONFIG_FILE}" "${prop_ref}")
      fi

      printf "  %-30s = %s\n" "${prop_ref}" "${property}"
      # sed 치환 시 충돌 방지를 위해 슬래시(/) 및 앰퍼샌드(&) 이스케이프
      property=$(echo "${property}" | sed -e 's/[\/&]/\\&/g')
      sed -i "s/\${${prop_ref}}/${property}/g" "${tplfile}"
    done
  fi
}

# @param $1 {string} 명령어. start|stop|status|enable|copy|create|remove
handle_by_systemctl() {
  local cmd="$1"

  case "${cmd}" in
  create)
    local svc_name="$2.service"
    local svc_dir="$3"
    local tplfile="$4"

    render_service_template "${tplfile}" "${svc_dir}/${svc_name}"

    # Docker 배포 모드일 경우 oneshot 및 RemainAfterExit 적용
    if [ "$DOCKER_MODE" == "Y" ]; then
      echo "  🐳 [Docker Mode] 서비스 디스크립터 변경: Type=oneshot, RemainAfterExit=yes 추가"
      sed -i 's/^Type=.*/Type=oneshot\nRemainAfterExit=yes/g' "${tplfile}"
    fi
    ;;

  copy)
    local svc_file="$2"
    local svc_name="$3.service"
    local svc_dir="$4"

    echo
    sudo cp -vf "${svc_file}" "${svc_dir}/${svc_name}"
    sudo systemctl daemon-reload # 🌟 유닛 파일 복사 후 데몬 재로드 필수
    echo "✅ [SUCCESS] sudo cp -vf ${svc_file} ${svc_dir}/${svc_name} (daemon-reload 완료)"
    ;;

  enable)
    local svc_name="$2.service" # 🌟 local 키워드 보정

    sudo systemctl enable "${svc_name}"
    echo "✅ [SUCCESS] sudo systemctl enable ${svc_name}"
    ;;

  start)
    local svc_name="$2.service"

    sudo systemctl start "${svc_name}"
    echo
    echo "▶️ [SUCCESS] sudo systemctl start ${svc_name}"
    ;;

  status)
    local svc_name="$2.service"

    sudo systemctl status -l "${svc_name}" --no-pager
    echo
    echo "ℹ️ [SUCCESS] sudo systemctl status -l ${svc_name} --no-pager"
    ;;

  stop)
    local svc_name="$2.service"

    sudo systemctl stop "${svc_name}"
    echo
    echo "⏹️ [SUCCESS] sudo systemctl stop ${svc_name}"
    ;;

  remove)
    local svc_name="$2.service"
    local svc_dir="$3"

    echo
    echo "⚙️ service: ${svc_dir}/${svc_name}"
    if [ -f "${svc_dir}/${svc_name}" ]; then
      echo "🗑️ FORCE to remove old 'Service Unit' file."
      # 🌟 안전한 제거 순서: stop -> disable -> rm -> daemon-reload
      sudo systemctl stop "${svc_name}" 2>/dev/null || true
      sudo systemctl disable "${svc_name}" 2>/dev/null || true
      echo "✅ [SUCCESS] sudo systemctl disable ${svc_name}"
      
      sudo rm -vf "${svc_dir}/${svc_name}"
      sudo systemctl daemon-reload # 🌟 파일 삭제 후 데몬 재로드 필수
      sudo systemctl reset-failed 2>/dev/null || true
      echo "✅ [SUCCESS] sudo rm -vf ${svc_dir}/${svc_name} (daemon-reload 완료)"
    fi
    ;;

  *)
    echo "❌ Unsupported command.(= ${cmd})"
    exit 1
    ;;
  esac
}

# @param $1 {string} 명령어. start|stop|status|enable|copy|create|remove
handle_by_service() {
  local cmd="$1"

  case "${cmd}" in
  create)
    local svc_name="$2"
    local svc_dir="$3"
    local tplfile="$4"

    render_service_template "${tplfile}" "${svc_dir}/${svc_name}"
    ;;

  copy)
    local svc_file="$2"
    local svc_name="$3"
    local svc_dir="$4"

    echo
    sudo cp -vf "${svc_file}" "${svc_dir}/${svc_name}"
    sudo chmod +x "${svc_dir}/${svc_name}"
    echo "✅ [SUCCESS] sudo cp -vf & chmod +x ${svc_dir}/${svc_name}"
    ;;

  enable)
    local svc_name="$2"

    echo
    sudo chkconfig --add "${svc_name}"
    echo "✅ [SUCCESS] sudo chkconfig --add ${svc_name}"
    ;;

  start)
    local svc_name="$2"

    sudo service "${svc_name}" start
    echo "▶️ [SUCCESS] sudo service ${svc_name}" start
    ;;

  status)
    local svc_name="$2"

    echo
    sudo service "${svc_name}" status
    echo "ℹ️ [SUCCESS] sudo service ${svc_name} status"
    ;;

  stop)
    local svc_name="$2"
    local status_msg
    status_msg=$(service "${svc_name}" status 2>/dev/null | grep -i [p]id || true)

    # 🌟 버그 수정: $$ 오타 제거 및 [ -n ] 사용
    if [ -n "${status_msg}" ]; then
      echo
      sudo service "${svc_name}" stop
      echo "⏹️ [SUCCESS] sudo service ${svc_name} stop"
    else
      echo
      echo "💤 [INFO] Service is not running."
    fi
    ;;

  remove)
    local svc_name="$2"
    local svc_dir="$3"

    echo "⚙️ service: ${svc_dir}/${svc_name}"
    if [ -f "${svc_dir}/${svc_name}" ]; then
      echo "🗑️ FORCE to remove old 'Service Unit' file."
      sudo service "${svc_name}" stop 2>/dev/null || true
      sudo chkconfig "${svc_name}" off 2>/dev/null || true
      sudo chkconfig --del "${svc_name}" 2>/dev/null || true
      sudo rm -vf "${svc_dir}/${svc_name}"
      echo "✅ [SUCCESS] sudo rm -vf ${svc_dir}/${svc_name}"
    fi
    ;;

  *)
    echo "❌ Unsupported command.(= ${cmd})"
    exit 1
    ;;
  esac
}

#
# @param $1 {string} command (create | copy | enable | start | stop | status | remove)
# @param $~ {any} 명령어별 필요 인자
#
handle_service() {
  local svc_cmd="$1"
  local svc_cmd_args=("${@:2}")
  
  # 서비스 관리자 감지 (systemd 등)
  local svc_mgr
  svc_mgr=$(detect_service_manager)

  echo
  echo "🚀 >>> Service Manager: [${svc_mgr}] / Command: ${svc_cmd} ${svc_cmd_args[*]}"

  case "${svc_mgr}" in
  systemd)
    handle_by_systemctl "${svc_cmd}" "${svc_cmd_args[@]}"
    ;;
  sysvinit)
    handle_by_service "${svc_cmd}" "${svc_cmd_args[@]}"
    ;;
  *)
    echo
    echo "❌ 지원하지 않거나 인식할 수 없는 서비스 관리 환경입니다. (Init: ${svc_mgr})"
    exit 1
    ;;
  esac
}

# =========================================================
# 1. 설정 및 초기화
# =========================================================
if [ -f "${CONFIG_FILE}" ]; then
  echo "✅ [Configurations] ${CONFIG_FILE} FOUND!"
else
  echo "❌ [Configurations] ${CONFIG_FILE} NOT FOUND!"
  help "설정 파일을 찾을 수 없습니다: ${CONFIG_FILE}" $LINENO
  exit 1
fi

## sudo 필요 여부 확인
SUDO=$(read_prop "${CONFIG_FILE}" "system.sudo")
if [ "$SUDO" == "true" ]; then
  if (($EUID != 0)); then
    echo
    echo "🛑 You MUST run this script as a 'ROOT' or 'sudoers'".
    echo
    exit 100
  fi
fi

# 현재 디렉토리 확인
CUR_DIR=$(pwd)

BUILD_NAME=$(read_prop "${CONFIG_FILE}" "build.name")
BUILD_FILE=$(read_prop "${CONFIG_FILE}" "build.file")

#
# 전달받은 디렉토리를 안전하게 삭제합니다.
#
clean_temp_dir() {
  local targets=()

  if [ -z "$1" ]; then
    if [ -n "${BUILD_NAME}" ]; then
      targets=("${BUILD_NAME}")
    fi
  else
    targets=( "$@" )
  fi
  
  echo
  echo "🧹🧹🧹 임시 디렉토리를 삭제합니다. "
  for dir in "${targets[@]}"; do
    echo " - $(normalize_path ${dir})"
    
    if [ -z "${dir}" ] || [ "${dir}" == "/" ] || [ "${dir}" == "." ] || [ "${dir}" == ".." ]; then
      echo "⚠️ [경고] 유효하지 않거나 시스템에 치명적인 경로입니다. 삭제를 건너뜁니다: '${dir}'" >&2
      continue
    fi
    
    rm -rf -- "${dir}" || sudo rm -rf -- "${dir}"   
  done
}

##
# Docker 및 Docker Compose 설치 여부를 확인 및 사용자 계정 권한을 검증합니다.
##
check_docker_installed() {
  echo "🐳 >>> 시스템에 Docker 환경이 구성되어 있는지 검증합니다..."

  if ! command -v docker >/dev/null 2>&1; then
    echo
    echo "❌ [ERROR] Docker가 설치되어 있지 않거나 PATH에 존재하지 않습니다." >&2
    exit 1
  fi

  local docker_version=$(sudo docker --version 2>/dev/null)
  echo "  ✅ - [OK] ${docker_version}"

  if sudo docker compose version >/dev/null 2>&1; then
    local compose_version=$(sudo docker compose version 2>/dev/null)
    echo "  ✅ - [OK] ${compose_version} (Plugin)"
  elif command -v docker-compose >/dev/null 2>&1; then
    local compose_version=$(sudo docker-compose --version 2>/dev/null)
    echo "  ✅ - [OK] ${compose_version} (Standalone)"
  else
    echo "❌ [ERROR] Docker Compose가 설치되어 있지 않습니다." >&2
    exit 1
  fi
  
  # 🌟 [신규 추가] 현재 스크립트 실행 계정을 docker 그룹에 자동 추가 및 Snap 예외 처리
  local ACTUAL_USER=${SUDO_USER:-$USER}
  if ! groups "$ACTUAL_USER" | grep -q '\bdocker\b'; then
    echo "🔑 >>> 현재 계정($ACTUAL_USER)을 'docker' 그룹에 추가합니다..."
    
    # 1. 시스템에 docker 그룹이 없을 경우를 대비해 안전하게 생성
    if ! getent group docker >/dev/null 2>&1; then
      sudo groupadd --system docker
    fi
    
    # 2. 계정을 docker 그룹에 편입
    sudo usermod -aG docker "$ACTUAL_USER"
    echo "  ✅ - [OK] 그룹 추가 완료. (systemctl 서비스 실행 시 자동 적용됩니다)"
    
    # 3. 🚨 [Snap 환경 특별 처리] Docker가 Snap으로 설치된 경우 소켓 권한 갱신을 위해 재시작 필수
    if command -v docker | grep -q '/snap/'; then
      echo "  🔄 [Snap Docker 감지] 그룹 권한 갱신을 위해 Snap Docker 데몬을 재시작합니다..."
      sudo snap disable docker
      sudo snap enable docker
      echo "  ✅ - [OK] Snap Docker 권한 갱신 완료."
      sleep 2
    fi
  fi

  if ! sudo docker info >/dev/null 2>&1; then
    echo
    echo "❌ [ERROR] Docker 데몬이 실행 중이지 않거나, 현재 사용자에게 접근 권한이 없습니다." >&2
    exit 1
  fi

  echo "✅ [SUCCESS] Docker 환경 검증 완료."
  echo
}


# docker 설치 검증
if [ "$DOCKER_MODE" == "Y" ]; then
  check_docker_installed
fi

## 이전 설치파일 디렉토리 삭제
echo
echo "🗑️ Remove a old directory"
{
  rm -rfv -- ${BUILD_NAME}
  echo "✅ [SUCCESS]  rm -rfv -- ${BUILD_NAME}"
} || {
  echo
  echo "💥  >>>>>>>>>>>>>>> OooooooooooooooPs !!! <<<<<<<<<<<<<< "

  clean_temp_dir "${BUILD_NAME}"
  exit 1
}
echo "👌 OK!"

## 설치파일 압축 해제
echo
echo "📦 Extract a new deployment file."
{
  tar -zxf ${BUILD_FILE}
  echo "✅ [SUCCESS]  tar -zxf ${BUILD_FILE}"

  load_profile "${BUILD_NAME}"

} || {
  echo
  echo "💥  >>>>>>>>>>>>>>> OooooooooooooooPs !!! <<<<<<<<<<<<<< "

  clean_temp_dir "${BUILD_NAME}"
  exit 1
}

echo "👌 OK!"

echo
echo " ================================================================================="
echo "🚀  >>>>>>>>>>>>>>>>>> INSTALL '${PROFILE}' version >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo "🚀  >>>>>>>>>>>>>>>>>> INSTALL '${PROFILE}' version >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo "🚀  >>>>>>>>>>>>>>>>>> INSTALL '${PROFILE}' version >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo " ================================================================================="

# 설치 디렉토리 검증
GROUP_NAME=$(read_prop "${CONFIG_FILE}" "group")
INST_DIR=$(read_prop "${CONFIG_FILE}" "install.dir")

echo
echo "📂 current_dir: "${CUR_DIR}
echo "📂 install_dir: "${INST_DIR}

echo
echo "📍 This module is installed at ${INST_DIR}/"

## 설치디렉토리가 설정되지 않은 경우 종료
if [ ! ${INST_DIR} ]; then
  echo
  echo "🛑 Installation Directory MUST BE SET."

  clean_temp_dir "${BUILD_NAME}"
  exit 1
fi

## 현재 디렉토리와 설치 디렉토리가 동일한 경우 종료
if [[ "${INST_DIR}" == "${CUR_DIR}" ]]; then
  echo
  echo "⚠️ Current directory is equal to a install directory."

  clean_temp_dir "${BUILD_NAME}"
  exit 2
fi


## 서비스 등록 여부
AS_A_SERVICE=$(read_prop "${CONFIG_FILE}" "service.registration")
# 서비스로 등록하는 경우
if [ "$AS_A_SERVICE" == "Y" ]; then
  load_os_info
fi

# 서비스 명
SVC_NAME=$(read_prop "${CONFIG_FILE}" "service.name")
# 서비스 설치 디렉토리
SVC_MGR=$(detect_service_manager)
SVC_DIR=$(read_prop "${CONFIG_FILE}" "service.dir.${SVC_MGR}")
# 만약 설정 파일에 없더라도 systemd 표준 경로(/etc/systemd/system)를 안전하게 기본값으로 적용
SVC_DIR=${SVC_DIR:-/etc/systemd/system}

# 서비스로 등록하는 경우
if [ "$AS_A_SERVICE" = "Y" ]; then
  ## 기존 서비스 정지
  echo "🛑 ## 기존 서비스 정지"
  {
    handle_service "stop" "${SVC_NAME}"
  } || {
    echo
    echo "💥  >>>>>>>>>>>>>>> OooooooooooooooPs !!! <<<<<<<<<<<<<< "

    clean_temp_dir
    exit 2
  }
else
  ## 기존 서비스 정지
  echo "🛑 ## 기존 서비스 정지"
  {
    STOP_CMD=$(read_prop "${CONFIG_FILE}" "install.file.stop")
    if [ -f "$STOP_CMD" ]; then
      echo "▶️ '$STOP_CMD'를 실행합니다."
      $STOP_CMD
    else
      echo
      echo "⚠️ * '$STOP_CMD'은 존재하지 않습니다. 'service.file.exec_stop' 속성 경로를 확인합니다."
      STOP_CMD=$(read_prop "${CONFIG_FILE}" "service.file.exec_stop")
      if [ -f "$STOP_CMD" ]; then
        echo "▶️ '$STOP_CMD'를 실행합니다."
        $STOP_CMD
      fi
    fi
  } || {
    echo
    echo "💥  >>>>>>>>>>>>>>> OooooooooooooooPs !!! <<<<<<<<<<<<<< "

    clean_temp_dir
    exit 2
  }
fi


# 서비스 배포 파일을 임시공간에 설치합니다.
install_service_temporarily(){
  # =========================================================
  # 2. 서비스 임시 설치
  # =========================================================
  rm -rf "$HOME/tmp/${BUILD_NAME}."*
  mkdir -p "$HOME/tmp/"
  TMP_INST_DIR=$(mktemp -d $HOME/tmp/${BUILD_NAME}.XXXXXXXXXX)
  
  echo
  echo " --------------------------------------------------------------------------------"
  echo "📁  ------------------ 'temporary directory  '${PROFILE}' version ------------------"
  echo "📁  ------------------ 'temporary directory  '${PROFILE}' version ------------------"
  echo " --------------------------------------------------------------------------------"
  
  echo
  echo "📋 >>> ### copy resource directories ###"
  ##
  ## begin: 디렉토리 복사
  RES_DIRS=($(read_prop "${CONFIG_FILE}" "resources.directories"))
  echo "==========================================================="
  for dir_name in "${RES_DIRS[@]}"; do
    {
      res_dir="${BUILD_NAME}/${dir_name}"
      if [ -d "${res_dir}" ]; then
        copy_files ${res_dir} "${TMP_INST_DIR}/${dir_name}" "${dir_name}"
      else
        echo "❌ [FAIL] ${res_dir} does NOT EXIST !!!"
      fi
      echo "==========================================================="
    } || {
      echo
      echo "🐛 [Errors] step: 'copy resource directories', directory: $res_dir"
  
      exit 2
    }
  done
  echo "🏁 <<<"
  ## end: 디렉토리 복사
  
  echo
  echo "📋 >>> ### copy resoureces files ###"
  
  ## 모듈 관련 파일 복사
  copy_files "${BUILD_NAME}" "${TMP_INST_DIR}" "files"
  echo "🏁 <<<"
}


install_service_temporarily

# =========================================================
# 3. 배포 모드에 따른 설치
# =========================================================
if [ "$DOCKER_MODE" == "N" ];then
  # ---------------------------------------------------------
  ensure_dir "$INST_DIR"
  
  # 일반 배포 모드
  # ---------------------------------------------------------
  echo "🖥️ >>> [일반 배포 모드] Host 환경에 직접 설치합니다."
  
  # 임시설치 파일(${TMP_INST_DIR})의 모든 정보를 설치경로(${INST_DIR})에 복사합니다.
  rm -rf "${INST_DIR}"
  cp -rv "${TMP_INST_DIR}/." "${INST_DIR}/"
else
  # ---------------------------------------------------------
  # Docker 배포 모드 (--docker)
  # ---------------------------------------------------------
  echo "🐳 >>> [Docker 배포 모드] 활성화"
  
  # 태그가 없는(<none>) 찌꺼기 이미지들을 일괄 삭제하여 디스크 용량 확보
  echo "💥 >>> 태그가 없는(<none>) 찌꺼기 이미지들을 일괄 삭제합니다."
  sudo docker image prune -f
  
  if [ ! -z "$OFFLINE_IMAGE" ]; then
    echo "📥 >>> 오프라인 이미지 로드 시작: ${OFFLINE_IMAGE}"
    sudo docker load -i "${OFFLINE_IMAGE}"
    echo "✅ [SUCCESS] Docker 이미지 로드 완료."
    
    # 'docker image' 생성 정보를 설치경로에 '참고'정보로 제공
    # 복사할 파일: 'Dockerfile', 'd-start.sh'
    copy_files "${BUILD_NAME}/docker" "${TMP_INST_DIR}" "docker"
  else
    # 일반 설치시 제어 파일 삭제.
    rm -fv "${TMP_INST_DIR}/start.sh" "${TMP_INST_DIR}/stop.sh" "${TMP_INST_DIR}/status.sh"
    
    # 'docker image' 버전 정보를 Maven Project 'pom.xml' 의 '<project><versoin>' 정보를 이용.
    IMAGE_VERSION="latest"
    if [ -f "./${BUILD_NAME}/.version" ]; then
      IMAGE_VERSION=$(cat ./${BUILD_NAME}/.version)
    fi
  
    # 'docker image' 생성을 위한 파일
    echo "📝 [BEGIN] Docker 이미지 빌드 시작."
    # 복사할 파일: 'Dockerfile', 'd-start.sh'
    copy_files "${BUILD_NAME}/docker" "${TMP_INST_DIR}" "docker"
    
     # 컨테이너 내부 절대경로 변환 (Host 경로 -> Container 경로)
    echo "🔄 >>> 내부 스크립트의 경로를 컨테이너 환경으로 치환합니다."
    find "${TMP_INST_DIR}" -type f -name "*.sh" -exec sed -i 's|'"${INST_DIR}"'|/app/'"${GROUP_NAME}"'/'"${BUILD_NAME}"'|g' {} +
    
    IMAGE_TAG="${BUILD_NAME}:${IMAGE_VERSION}"
    echo "🔨 >>> Docker 이미지 (${IMAGE_TAG}) 빌드 시작..."
    sudo docker build -f "${TMP_INST_DIR}/Dockerfile" -t "${IMAGE_TAG}" "${TMP_INST_DIR}"
    
    echo "✅ [SUCCESS] Docker 이미지 빌드 완료."
  fi
  
  # 'log4j2.yml'의 로그파일 생성경로를 'docker-compose.yml' 의 'volume' 설정 정보로 변경.
  #LOG_DIR=$(read_prop "${CONFIG_FILE}" "log.dir")
  #find "${TMP_INST_DIR}" -type f -name "log4j2.yml" -exec sed -i 's|'"${LOG_DIR}"'|/log/'"${GROUP_NAME}"'/'"${BUILD_NAME}"'|g' {} +
  
  # -----------------------------------------------------------------------------
  # 'docker-compose.yml'의 'volumes' 설정 정보를 기반으로 컨테이너 내부 경로 후처리
  # -----------------------------------------------------------------------------
  DVL_PREFIX="docker-compose.volumes.linker"

  # 설정 문자열을 읽어 globbing 없이 공백 기준으로 안전하게 배열로 변환합니다.
  read -r -a DC_VOL_LINKERS <<< "$(read_prop "${CONFIG_FILE}" "${DVL_PREFIX}")"

  for linker_id in "${DC_VOL_LINKERS[@]}"; do
    # 설정이 존재하지 않아 read_prop()가 원본 property 표현식을 반환하거나,
    # 비어있는 경우 후처리하지 않습니다.
    if [[ -z "${linker_id}" || "${linker_id}" == "\${${DVL_PREFIX}}" ]]; then
      continue
    fi

    TARGET_FILE=$(read_prop "${CONFIG_FILE}" "${DVL_PREFIX}.${linker_id}.file")
    HOST_PATH=$(read_prop "${CONFIG_FILE}" "${DVL_PREFIX}.${linker_id}.host")
    CONTAINER_PATH=$(read_prop "${CONFIG_FILE}" "${DVL_PREFIX}.${linker_id}.container")

    # linker별 property key
    TARGET_FILE_KEY="${DVL_PREFIX}.${linker_id}.file"
    HOST_PATH_KEY="${DVL_PREFIX}.${linker_id}.host"
    CONTAINER_PATH_KEY="${DVL_PREFIX}.${linker_id}.container"

    # 필수 설정값 검증
    if [[ -z "${TARGET_FILE}" || "${TARGET_FILE}" == "\${${TARGET_FILE_KEY}}" || \
          -z "${HOST_PATH}" || "${HOST_PATH}" == "\${${HOST_PATH_KEY}}" || \
          -z "${CONTAINER_PATH}" || "${CONTAINER_PATH}" == "\${${CONTAINER_PATH_KEY}}" ]]; then
      echo "⚠️ [WARNING] Volume Linker ID '${linker_id}'의 설정 정보가 불완전하여 후처리를 건너뜁니다."
      continue
    fi

    echo "🔄 >>> [Volume Linker: ${linker_id}] '${TARGET_FILE}' 파일 내 '${HOST_PATH}' 경로를 '${CONTAINER_PATH}'(으)로 치환합니다."

    # sed search pattern에서 정규식 특수문자가 의미를 갖지 않도록 escape 합니다.
    SED_HOST_PATH=$(printf '%s' "${HOST_PATH}" | sed 's/[][\/.^$*+?(){}|\\]/\\&/g')

    # sed replacement에서 특수문자가 의미를 갖지 않도록 escape 합니다.
    SED_CONTAINER_PATH=$(printf '%s' "${CONTAINER_PATH}" | sed 's/[&|\\]/\\&/g')

    # 실제 치환 작업 수행
    find "${TMP_INST_DIR}" -type f -name "${TARGET_FILE}" -exec sed -i "s|${SED_HOST_PATH}|${SED_CONTAINER_PATH}|g" {} +
  done
    
  if [ "$BUILD_ONLY" == "Y" ]; then
    echo "🏁 >>> [--build-only] 옵션이 켜져 있어 이미지를 다운로드 및 배포 데이터를 생성합니다."
    
    # 오프라인 배포용 디렉토리 경로 계산 (<빌드프로파일>-dockerimage)
    CURRENT_DIR_NAME=$(basename "${CUR_DIR}")
    PARENT_DIR=$(dirname "${CUR_DIR}")
    EXPORT_DIR="${PARENT_DIR}/${CURRENT_DIR_NAME}-dockerimage"
    
    # 이전 데이터가 존재한다면 삭제합니다.
    rm -rf "${EXPORT_DIR}"
    
    echo "📁 >>> 오프라인 배포용 디렉토리를 생성합니다: ${EXPORT_DIR}"
    mkdir -p "${EXPORT_DIR}"

    # 1. 폐쇄망(Offline) 환경 배포를 위한 이미지 추출
    OFFLINE_IMAGE_FILE="${EXPORT_DIR}/${BUILD_NAME}.tar"
    echo "💾 >>> 오프라인 배포를 위해 이미지를 파일로 추출합니다: ${OFFLINE_IMAGE_FILE}"
    
    # if문으로 명시적 에러 처리 및 -o 대신 파일 리다이렉션(>)으로 권한 문제 우회
    if sudo docker save "${IMAGE_TAG}" > "${OFFLINE_IMAGE_FILE}"; then
      echo "✅ [SUCCESS] sudo docker save > \"${OFFLINE_IMAGE_FILE}\""
      
      # 🌟 이미지를 파일로 추출한 후 로컬 Docker 저장소에서 삭제합니다.
      echo "🗑️ >>> 추출이 완료된 이미지를 로컬 저장소에서 삭제(정리)합니다."
      if sudo docker rmi "${IMAGE_TAG}" >/dev/null 2>&1; then
        echo "✅ [SUCCESS] sudo docker rmi \"${IMAGE_TAG}\""
      else
        # 삭제 중 오류(컨테이너가 사용 중 등)가 발생해도 스크립트 진행에는 방해되지 않도록 경고만 출력합니다.
        echo "⚠️ [WARNING] 로컬 이미지 삭제 실패. 무시하고 진행합니다."
      fi
    else
      echo "❌ [FAIL] Docker 이미지를 저장하는 데 실패했습니다."
      clean_temp_dir "${BUILD_NAME}" "${TMP_INST_DIR}"
      exit 1
    fi
    
    # 2. 서비스 바이너리 파일을 제외한 나머지 파일(설정파일, 제어 파일 등등)을 압축/이관 합니다.
    echo "📋 >>> 서비스 바이너리 파일을 제외한 나머지 파일(설정파일, 제어 파일 등등)을 압축 및 이관합니다."
    # 서비스 바이너리 파일 삭제
    rm -rf "${CUR_DIR}/${BUILD_NAME}/${BUILD_NAME}.jar" "${CUR_DIR}/${BUILD_NAME}/lib" "${CUR_DIR}/${BUILD_NAME}/start.sh" "${CUR_DIR}/${BUILD_NAME}/stop.sh" "${CUR_DIR}/${BUILD_NAME}/status.sh"
    # 나머지 파일(설정파일, 제어 파일 등등) 압축 및 이관
    tar -zcf "${EXPORT_DIR}/${BUILD_NAME}.tar.gz" -C "${CUR_DIR}" "${BUILD_NAME}"
          
    # 3. 배포 스크립트 및 설정 파일 복사.
    echo "📋 >>> 배포 스크립트와 설정 파일을 오프라인 배포 디렉토리로 복사합니다."
    cp -v "$0" "${EXPORT_DIR}/deploy.sh"
    cp -v "${CONFIG_FILE}" "${EXPORT_DIR}/"
    echo "✅ [SUCCESS] 필수 파일 복사 완료"

    clean_temp_dir "${BUILD_NAME}" "${TMP_INST_DIR}"
    exit 0
  fi
  
  # 'docker image'에 포함된 파일 삭제
  rm -rf -- "${TMP_INST_DIR}/${BUILD_NAME}.jar" "${TMP_INST_DIR}/lib" "${TMP_INST_DIR}/start.sh"
  
  # 'docker image' 생성 정보를 설치경로에 '참고'정보로 제공
  echo
  echo "📋 >>> docker 이미지 생성용 정보를 제공합니다."
  mkdir -p "${TMP_INST_DIR}/.docker-image"    
  mv -v "${TMP_INST_DIR}/Dockerfile" "${TMP_INST_DIR}/.docker-image/"
  mv -v "${TMP_INST_DIR}/d-start.sh" "${TMP_INST_DIR}/.docker-image/"
  
  echo
  echo "🐳 >>> 'docker compose 기반 환경'을 생성합니다."
  # 복사할 파일: 'docker-compose.yml', 'dc-start.sh', 'dc-stop.sh', 'dc-status.sh', 'dot.env'
  copy_files "${BUILD_NAME}/docker-compose" "${TMP_INST_DIR}" "docker-compose"
  
  # 'docker-compose' 정보 보정
  # 1. `${docker.extra_hosts.host_gateway}` 값을 설정파일에서 읽어온 정보로 치환. 없는 경우 "host.docker.internal"  
  host_gateway=$(read_prop "${CONFIG_FILE}" "docker.extra_hosts.host_gateway")
  if [ "${host_gateway}" = "\${docker.extra_hosts.host_gateway}" ] || [[ "${host_gateway}" =~ ^[[:space:]]*$ ]]; then
    host_gateway="host.docker.internal"
  fi
  # 2. 'docker-compose.yml' 파일 변경
  #find "${TMP_INST_DIR}" -type f -name "docker-compose.yml" -exec sed -i 's|${docker-extra_hosts-host_gateway}|'"${host_gateway}"'|g' {} +
  # 2. 'dot.env' 파일 변경
  find "${TMP_INST_DIR}" -type f -name "dot.env" -exec sed -i 's|${docker-extra_hosts-host_gateway}|'"${host_gateway}"'|g' {} +
  
  # 이전 데이터가 존재한다면 삭제.
  rm -rf "${INST_DIR}"
  mkdir -p "${INST_DIR}"
  cp -rv "${TMP_INST_DIR}/." "${INST_DIR}/"
  
  mv -v "${INST_DIR}/dc-start.sh" "${INST_DIR}/start.sh"
  mv -v "${INST_DIR}/dc-stop.sh" "${INST_DIR}/stop.sh"
  mv -v "${INST_DIR}/dc-status.sh" "${INST_DIR}/status.sh"
  mv -v "${INST_DIR}/dot.env" "${INST_DIR}/.env"
fi


echo
echo "###########################################################################################"
echo "🚚 ### -------------------- Copy files & directories to specified locations. ------------- ###"
echo "🚚 ### -------------------- Copy files & directories to specified locations. ------------- ###"
echo "🚚 ### -------------------- Copy files & directories to specified locations. ------------- ###"
echo "###########################################################################################"

PROP_COPY="additional.action.copy"
ACTIONS=$(read_prop "${CONFIG_FILE}" $PROP_COPY)

if [ "\${$PROP_COPY}" != "${ACTIONS}" ]; then
  for action in ${ACTIONS[@]}; do
    _cp_conf_=$(read_prop "${CONFIG_FILE}" $PROP_COPY"."$action)
    if [ -z "$_cp_conf_" ]; then
      continue
    fi

    IFS="," read -a _cp_cfgs_ <<<"${_cp_conf_}"
    for _cp_cfg_ in ${_cp_cfgs_[@]}; do
      IFS="|" read -a _cp_info_ <<<"${_cp_cfg_}"
      if [ ${#_cp_info_[@]} -ne 2 ]; then
        echo
        echo "❌ [Invalid] step: 'copy addtional resources', resource='$PROP_COPY.$action=${_cp_info_[@]}'"
        continue
      fi

      if [ -f "${_cp_info_[1]}" ]; then
        echo
        echo "❌ [Invalid] 'DESTnation' MUST be a directory. NOT a file. path=${_cp_info_[1]}"
        continue
      fi

      [ ! -d "${_cp_info_[1]}" ] && mkdir -p "${_cp_info_[1]}"

      echo
      eval cp -v -- "${_cp_info_[0]}" "${_cp_info_[1]}/"
      echo "✅ [SUCCESS] cp" "${_cp_info_[0]}" "${_cp_info_[1]}"
    done
  done
else
  echo "ℹ️ [DETECTED] No files..."
fi


AUTOSTART=$(read_prop "${CONFIG_FILE}" "service.autostart")
if [ "$SERVICE_REGISTERED" = "Y" ] || ([ -z "$SERVICE_REGISTERED" ] && [ "$AS_A_SERVICE" = "Y" ]); then
  SYSTEMD_GROUP_DIR=$(read_prop "${CONFIG_FILE}" "systemd.group.dir")
  if [[ "${INST_DIR}" != "${SYSTEMD_GROUP_DIR}"* ]]; then
    echo
    echo "###########################################################################################"
    echo "🔗 ### ----------- Apply Single Source of Truth (Symlink to systemd.dir) ----------------- ###"
    echo "###########################################################################################"
    
    sudo mkdir -p "${SYSTEMD_GROUP_DIR}"
    
    ACTUAL_USER=${SUDO_USER:-$USER}
    sudo chown -R $ACTUAL_USER:$ACTUAL_USER "${SYSTEMD_GROUP_DIR}"

    START_CMDS=("$(read_prop "${CONFIG_FILE}" "install.file.start")" "$(read_prop "${CONFIG_FILE}" "service.file.exec_start")")
    STOP_CMDS=("$(read_prop "${CONFIG_FILE}" "install.file.stop")" "$(read_prop "${CONFIG_FILE}" "service.file.exec_stop")")
    STATUS_CMDS=("$(read_prop "${CONFIG_FILE}" "install.file.status")" "$(read_prop "${CONFIG_FILE}" "service.file.exec_status")")
    
    setup_service_link "${START_CMDS[0]}" "${START_CMDS[1]}"
    setup_service_link "${STOP_CMDS[0]}" "${STOP_CMDS[1]}"
    setup_service_link "${STATUS_CMDS[0]}" "${STATUS_CMDS[1]}"
  fi
  
  echo
  echo "###########################################################################################"
  echo "⚙️ ### -------------------- Install '${BUILD_NAME}' as a Service  ------------------------ ###"
  echo "⚙️ ### -------------------- Install '${BUILD_NAME}' as a Service  ------------------------ ###"
  echo "⚙️ ### -------------------- Install '${BUILD_NAME}' as a Service  ------------------------ ###"
  echo "###########################################################################################"

  INST_MOD_DIR=$(read_prop "${CONFIG_FILE}" "install.module.directory")
  
  # 감지된 서비스 관리 도구에 맞는 템플릿 파일 선택 (예: install/systemd/service.template)
  SVC_MGR=$(detect_service_manager)
  SVC_TEMPLATE_FILE="${BUILD_NAME}/${INST_MOD_DIR}/${SVC_MGR}/service.template"

  echo
  echo "🏷️ ### "$(read_prop "${CONFIG_FILE}" "service.file.description")

  handle_service "remove" "${SVC_NAME}" "${SVC_DIR}"
  sleep 0.5

  handle_service "create" "${SVC_NAME}" "${SVC_DIR}" "${SVC_TEMPLATE_FILE}"
  sleep 0.5

  handle_service "copy" "${SVC_TEMPLATE_FILE}" "${SVC_NAME}" "${SVC_DIR}"
  sleep 0.5

  handle_service "enable" "${SVC_NAME}"
  sleep 0.5

  handle_service "stop" "${SVC_NAME}"
  sleep 1
fi

echo "------------------------------------------------"
echo "------------------------------------------------"
echo "------------------------------------------------"
echo
echo "👋 Bye~"

clean_temp_dir "${BUILD_NAME}" "${TMP_INST_DIR}"

if [ "$SERVICE_AUTO_START" = "Y" ] || ([ -z "$SERVICE_AUTO_START" ] && [ "${AUTOSTART}" = "Y" ]); then
  if [ "$SERVICE_REGISTERED" = "Y" ] || ([ -z "$SERVICE_REGISTERED" ] && [ "$AS_A_SERVICE" = "Y" ]); then
    handle_service "start" "${SVC_NAME}"
    handle_service "status" "${SVC_NAME}"
  else
    _start_cmd_=$(read_prop "${CONFIG_FILE}" "install.file.start")
    echo "▶️ _start_cmd_=${_start_cmd_}"
    eval ${_start_cmd_}
    
    _status_cmd_=$(read_prop "${CONFIG_FILE}" "service.file.exec_status")
    echo "ℹ️ _status_cmd_=${_status_cmd_}"
    eval ${_status_cmd_}
  fi
fi

exit 0