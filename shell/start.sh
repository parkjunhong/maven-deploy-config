#!/bin/bash

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
	echo "./start.sh -c <configuration> [-h] [-jdwp]"
	echo
	echo "[Option]"
	echo " -c, --config : (optional) 설정파일 경로. 기본값: service.propertites"
	echo " -h, --help   : 도움말"
	echo " -jdwp        : (optional) 설정되는 경우 원격디버깅 포트 개방"
	echo
}


JDWP=0
CONFIG_FILE="service.properties"
## 파라미터 읽기
while [ "$1" != "" ]; do
	case $1 in
		-c | --config)
			shift
			CONFIG_FILE=$1
			;;
		-jdwp)
			JDWP=1
			;;
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

# Pattern: ${...}
REGEX_PROP_REF="\\\$\{([^\}]+)\}"
GLOBAL_REMATCH=""

# $1 {string} string
# $2 {string} regular expression
global_rematch() {
	GLOBAL_REMATCH=""
	local str="$1"
	local regex="$2"
	
	while [[ $str =~ $regex ]];
	do
		if [ -z "$GLOBAL_REMATCH" ];
		then
			GLOBAL_REMATCH="${BASH_REMATCH[1]}"
		else
			GLOBAL_REMATCH="$GLOBAL_REMATCH ${BASH_REMATCH[1]}"
		fi
		local str=${str#*"${BASH_REMATCH[1]}"}
	done
}

## 설정파일 읽기
# $1 {string} file
# $2 {string} prop_name
# $3 {any} default_value
prop(){
	local property=""
	# 1. profile 에 기반한 설정부터 조회 
	if [ ! -z "$PROFILE" ];
	then
		local property=$(grep -v -e "^#" ${1} | grep -e "^${2}\.$PROFILE=" | cut -d"=" -f2-)
	fi
	
	# 2. profile에 기반한 설정이 없는 경우 기본 설정조회
	if [ -z "$property" ];
	then
		local property=$(grep -v -e "^#" ${1} | grep -e "^${2}=" | cut -d"=" -f2-)
		
		# 3. 기본설정이 없고 함수 호출시 기본값이 있는 경우
		if [ -z "$property" ] && [ ! -z "$3" ];
		then
			echo $3
		else
			echo $property
		fi
	else
		echo $property
	fi
}

# $1 {string} absolute file path.
# $2 {string} prop_name
# $3 {any} default_value
read_prop(){
	local property=$(prop "$1" "$2" "$3")
	global_rematch "$property" "$REGEX_PROP_REF"
	
	if [ -z "$GLOBAL_REMATCH" ];
	then
		echo $property
	else
		local references=($(echo $GLOBAL_REMATCH))
		for ref in "${references[@]}";
		do
			local ref_value=$(read_prop "$1" "$ref")
			if [ ! -z "$ref_value" ];
			then
				local property=${property//\$\{$ref\}/$ref_value}
			fi
		done
		echo $property
	fi
}

## 설정파일이 전달되지 않은 경우 종료
if [ ! -f "$CONFIG_FILE" ]
then
	echo "[Configurations] 'CONFIG_FILE' NOT FOUND!"
	usage "Check 'config_file': --config"
	
	exit 2
fi

## sudo 필요 여부 확인
SUDO=$(read_prop "$CONFIG_FILE" "system.sudo")
if [ "$SUDO" == "true" ];
then
	# Check whether a user is one of 'root' and 'sudoers' or not.
	if (( $EUID != 0 ));
	then
		echo
		echo "You MUST run this script as a 'ROOT' or 'sudoers'".
		echo
		
		exit 100
	fi
fi

# ###########################################################################

# 설치  디렉토리로 이동
DIR=$(read_prop "$CONFIG_FILE" "install.dir")
cd $DIR

# Build 프로파일 읽기
if [ -f "$DIR/.profile" ];
then
	PROFILE=$(cat ./.profile)
fi

## Java 확인
JAVA_PATH=$(command -v java)
if [ ! $JAVA_PATH ];
then
	echo "\$JAVA_PATH is null."
	echo "Need JDK/JRE 1.8 or higher"

	exit 1
fi

APP_NAME=$(read_prop "$CONFIG_FILE" "application.name")
EXEC_FILE=$(read_prop "$CONFIG_FILE" "execution.filename")

echo
echo "=============================================================================================="
echo "PROFILE      : $PROFILE"
echo "APP_NAME     : $APP_NAME"
echo "DIRECTORY    : $DIR"
echo "EXEC_FILE    : $EXEC_FILE"
echo "JAVA_PATH    : $JAVA_PATH"

#
# Log4j-2.x Making All Loggers Asynchronous
JAVA_OPTS="-DLog4jContextSelector=org.apache.logging.log4j.core.async.AsyncLoggerContextSelector -DAsyncLogger.ThreadNameStrategy=UNCACHED"

# 실행 명령어
EXEC_CMD="nohup $JAVA_PATH"


if [ "$JDWP" = 1 ]
then
	JDWP_PORT=$(read_prop "$CONFIG_FILE" "jdwp.port")
	JDWP_OPTS="-Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=y,address="$JDWP_PORT
	
	EXEC_CMD=$EXEC_CMD" $JDWP_OPTS"
fi

# begin: 커스터마이징 !!!
# 
# end: 커스터마이징 !!!

# 프로그램 설정정보
EXEC_CMD=$EXEC_CMD" -jar -Dname=$APP_NAME $JAVA_OPTS $EXEC_FILE > /dev/null 2>&1 &"

{
	eval $EXEC_CMD
	echo "[SUCCES] $EXEC_CMD"
} || {
	echo "[FAIL] $EXEC_CMD"
}

echo
echo "=============================================================================================="

exit 0
