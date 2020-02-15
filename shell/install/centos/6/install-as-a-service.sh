#!/bin/bash
## for CentOS 6

echo
echo "#############################################################################"
echo "### -------------------- install-as-a-service.sh ------------------------ ###"
echo "### -------------------- install-as-a-service.sh ------------------------ ###"
echo "### -------------------- install-as-a-service.sh ------------------------ ###"
echo "#############################################################################"

usage(){
	echo "[Usage]"
    echo
    echo "./install-as-a-service.sh -c <configuration> -p <profile> -e <execution command> -h"
    echo
    echo "[Option]"
    echo " -c,--config   : 설정파일 경로"
	echo " -p, --profile : build profile"    
    echo " -e, --exec-cmd: 실행 명령. [ install | stop ]"  
    echo " -h, --help    : 도움말"
}

# 파라미터가 없는 경우 종료
if [ "$1" == "" ];
then
	usage
	exit 2
fi

PROFILE=""
# 기본 명령어
COMMAND="install"
## 파라미터 읽기
while [ "$1" != "" ]; do
	case $1 in
		-c | --config)
			shift
			CONFIG_FILE=$1
    		;;
		-p | --profile)
			shift
			PROFILE=$1
			;;			    		
		-e | --exec-cmd) 
			shift
			COMMAND=$1
			;;
		-h | --help)     
			usage
			exit 0
			;;
		*)
			usage
			exit 2
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

#
# @param $1 {string} property name
check_sys_prop(){
	 case "$1" in 
	 	"sys:user.home")
	 		echo ${HOME}
	 		;;
	 	"sys:username")
	 		echo ${USER}
	 		;;
	 	*)
	 		;;
	 esac
}

REGEX_PROP_REF="\\\$\{([^\}]+)\}"
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
			# check system property
			local ref_value=$(check_sys_prop ${ref})
			if [ ! -z "${ref_value}" ] ;
			then
				property=${property//\$\{$ref\}/$ref_value}
			else
				local ref_value=$(read_prop "$1" "$ref")
				if [ ! -z "$ref_value" ];
				then
					property=${property//\$\{$ref\}/$ref_value}
				fi
			fi
		done
		echo $property
	fi
}


## 설정파일이 전달되지 않은 경우 종료
if [ -f "$CONFIG_FILE" ]
then
	echo "[Configurations] $CONFIG_FILE FOUND!"
else
	echo
	
	echo
	echo "[Configurations] $CONFIG_FILE NOT FOUND!"
	echo

    usage

    exit 0
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

## 프로파일이 전달되지 않은 경우 종료
if [ -z "$PROFILE" ]
then
	echo "[PROFILE] $PROFILE NOT FOUND!"

	usage "No Profile"

	exit 0
else
	echo "[PROFILE] $PROFILE FOUND!"
fi

# 서비스 템플릿 파일에 설정정보를 적용한다.
# $1 {string} 서비스 이름
# $2 {string} 설정 파일
create_service(){
	echo
	echo "-------- ${FUNCNAME[0]} --------"
	local tplfile="service.template"
	local tplstring=$(cat "$tplfile")
	
	global_rematch "$tplstring" "$REGEX_PROP_REF"
	
	if [ ! -z "$GLOBAL_REMATCH" ];
	then
		local properties=($(echo $GLOBAL_REMATCH))
		for prop_ref in "${properties[@]}";
		do
			if [ "$prop_ref" == "service.filepath" ];
			then
				local property="$SVC_DIR/$SVC_NAME"			
			else
				local property=$(read_prop "$2" "$prop_ref")
			fi
			
			printf "	%-30s = %s\n" "$prop_ref" "$property"
			# 데이터에 경로구분자(/)가 포함된 경우 변경
			local property=${property//\//\\\/}
			# format of a variable in xxx.service file is ${variable_name}.
			eval "sed -i 's/\${$prop_ref}/$property/g' $tplfile"
		done
	fi
	
	echo
	mv $tplfile $1
	echo "[SUCCESS] mv $tplfile $1"
}

## 기존 서비스 삭제
# $1 {string} 서비스 이름
# $2 {string} 서비스 파일 디렉토리
remove_service(){
	echo	
	echo "-------- ${FUNCNAME[0]} --------"
	
	SVC_NAME=$1
	SVC_DIR=$2
	
	echo "service: $SVC_DIR/$SVC_NAME"
	if [ -f "$SVC_DIR/$SVC_NAME" ]
	then
		echo "FORCE to remove a old 'Service Unit' file."
		echo 
		echo "sudo chkconfig $SVC_NAME off"
		sudo chkconfig $SVC_NAME off
		echo "sudo chkconfig --del $SVC_NAME"
		sudo chkconfig --del $SVC_NAME
		echo "sudo rm -rf  $SVC_DIR/$SVC_NAME"
		sudo rm -rf  $SVC_DIR/$SVC_NAME	
	fi
}

## 서비스 파일 복사
copy_service(){
	echo 
	echo "-------- ${FUNCNAME[0]} --------"
	
	SVC_NAME=$1
	SVC_DIR=$2
	
	echo "sudo cp -uf $SVC_NAME $SVC_DIR/"
	sudo cp -uf $SVC_NAME $SVC_DIR/
}

## 서비스 등록
enable_service(){
	echo	
	echo "-------- ${FUNCNAME[0]} --------"
	
	SVC_NAME=$1
	
	echo "sudo chkconfig --add $SVC_NAME"
	sudo chkconfig --add $SVC_NAME
}

## 서비스 시작
start_service(){
	echo	
	echo "-------- ${FUNCNAME[0]} --------"
	
	SVC_NAME=$1
	
	echo "service $SVC_NAME start"
	service $SVC_NAME start
}
	
## 서비스 상태 조회
status_service(){
	
	echo	
	echo "-------- ${FUNCNAME[0]} --------"
	
	SVC_NAME=$1
	
	echo "service $SVC_NAME status"
	service $SVC_NAME status
}

## 서비스 정지
stop_service(){
	echo	
	echo "-------- ${FUNCNAME[0]} --------"
	
	SVC_NAME=$1
	
	STATUS_MSG=$(service $SVC_NAME status | grep [p]id)
	if [ "$STATUS_MSG" != "" ]
	then
		echo "service $SVC_NAME stop"
		service $SVC_NAME stop
	else
		echo "No running"
	fi
}

## 서비스 설정
SVC_DIR=/etc/init.d
SVC_NAME=$(read_prop "$CONFIG_FILE" "service.name")


## 명령어 실행
case $COMMAND in
	"stop")
		# 기존 서비스 중지
		stop_service $SVC_NAME
		;;
	"install")
	
		echo "#############################################################################"
		echo "### "$(read_prop "$CONFIG_FILE" "service.file.description")
		echo "#############################################################################"
	
		# 기존 서비스 삭제
		remove_service $SVC_NAME $SVC_DIR
		
		sleep 0.5
		
		# 서비스 파일 생성
		create_service $SVC_NAME $CONFIG_FILE
		
		sleep 0.5		
		
		# 서비스 파일 복사
		copy_service $SVC_NAME $SVC_DIR
		
		sleep 0.5
		
		# 서비스 활성화
		enable_service $SVC_NAME
		
		sleep 0.5
		
		# 서비스 정지
		stop_service $SVC_NAME
		
		sleep 1
		
		AUTOSTART=$(read_prop "$CONFIG_FILE" "service.autostart")
		if [ "$AUTOSTART" = "Y" ];
		then
			# 서비스 시작
			start_service $SVC_NAME
			
			sleep 0.5
			
			# 서비스 상태 조회
			status_service $SVC_NAME
		fi
		;;
	*)
		usage
		exit 2
		;;
esac

exit 0