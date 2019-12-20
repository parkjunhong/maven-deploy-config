#!/bin/bash

echo
echo "####################################################################"
echo "### -------------------- run-install.sh ------------------------ ###"
echo "### -------------------- run-install.sh ------------------------ ###"
echo "### -------------------- run-install.sh ------------------------ ###"
echo "####################################################################"

# 동적으로 변수에 값을 할당한다.
# $1 {string} variable name
# $2 {any} value
assign(){
    eval $1=\"$2\"
}

usage(){
	echo
	echo "Called by [[$1]]"
	echo "[Usage]"
	echo
	echo "./run-install.sh -c <configuration> -p <profile> -on <os-name> -ov  <os-version> -h"
	echo
	echo "[Option]"
	echo " -c, --config     : 설정파일 경로"
	echo " -p, --profile    : build profile"
	echo " -on, --os-name   : 운영체제 이름. 현재 [centos|ubuntu] 지원. (서비스로 등록할 경우 필수)"
	echo " -ov, --os-version: 운영체제 버전. --os-name 이 centos 6/7, ubuntu 16. (서비스로 등록할 경우 필수)"
	echo " -h, --help       : 도움말"
	echo
	echo
	echo " ================ OPERATING SYSTEM INFORMATION ================ "
	cat /etc/*-release
	echo "=============================================================== "	
}

# 파라미터가 없는 경우 종료
if [ "$1" == "" ];
then
	usage "No Parametes"
	exit 2
fi

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
		-on | --os-name)
			shift
			OS_NAME=$1
			;;
		-ov | --os-version)
			shift
			OS_VERSION=$1
			;;
		-h | --help)
			usage "--help"
			exit 0
			;;
		*)
			usage "invalid options. $1"
			exit 2
			;;
	esac
	shift
done

# Pattern: ${...}
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
			local ref_value=$(read_prop "$1" "$ref")
			if [ ! -z "$ref_value" ];
			then
				local property=${property//\$\{$ref\}/$ref_value}
			fi
		done
		echo $property
	fi
}

# Replace a old string to a new string.
# $1 {string} file path
# $2 {string} old string
# $3 {string} new string
update_property(){
	# 데이터에 경로구분자(/)가 포함된 경우 변경
	local targetfile=$1
	local oldstr=$2
	local newstr=$3
	local newstr=${newstr//\//\\\/}
	# format of a variable in xxx.service file is ${variable_name}.
	eval "sed -i 's/\${$oldstr}/$newstr/g' $targetfile" 
}

# 큰따옴표(") 또는 작은 따옴표(')로 묶은 문자열을 찾는다.
# $1 {string} string
# $2 {string} variable
unwrap_quote(){
    global_rematch "$1" "^\"([^\"]+)\"$"
    if [ -z "$GLOBAL_REMATCH" ];
    then    
        global_rematch "$1" "^'([^']+)'$"
    fi
    
	if [ ! -z "$GLOBAL_REMATCH" ];
	then
		assign "$2" "$GLOBAL_REMATCH"
	fi    
}

# Replace a old string to a new string.
# $1 {string} file path
# $@:1 {any} properties
update_properties(){
	echo
	echo "-------- ${FUNCNAME[0]} --------"
	
	local targetfile="$1"
	local arguments=(${@})
	local prop_value=""
	
	printf "	%-30s = %s\n" "filename" "$targetfile"
	
	for prop in "${arguments[@]:1}";
	do
		# 큰/작은 따옴표 제거
		unwrap_quote "$prop" "prop"
		
		local prop_value=$(read_prop "$CONFIG_FILE" "$prop")
		if [ ! -z "$prop_value" ];
		then
			printf "	%-30s = %s\n" "$prop" "$prop_value"
			update_property "$targetfile" "$prop" "$prop_value"	
		fi
	done
	
	echo "--------------------------------"
}

# check a file exists.
# $1 {string} filepath
# $2 {number} exit value
check_file_then_exit(){
	if [ ! -f "$1" ];
	then
		echo
		echo "[A file DOES NOT EXIST] file="$1
		
		exit $2
	fi
}

# check a directory exists.
# $1 {string} directory path
# $2 {number} exit value
check_dir_then_exit(){
	if [ ! -d "$1" ];
	then
		echo
		echo "[A directory DOES NOT EXIST] directory="$1
		
		exit $2
	fi
}

## 설정파일이 전달되지 않은 경우 종료
if [ -f "$CONFIG_FILE" ]
then
	echo "[Configurations] $CONFIG_FILE FOUND!"
else
	echo
	echo "[Configurations] $CONFIG_FILE NOT FOUND!"
	
	echo
	usage "No Configuration file."

	exit 1
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
	echo
	echo "[PROFILE] $PROFILE NOT FOUND!"

	echo
	usage "No Profile"

	exit 1
else
	echo "[PROFILE] $PROFILE FOUND!"
fi

echo
echo "#############################################################################"
echo $(read_prop "$CONFIG_FILE" "service.registration.message")
echo "#############################################################################"
## 현재 디렉토리, 설치 디렉토리 정보 확인.
## 
CUR_DIR=$(pwd)
INST_DIR=$(read_prop "$CONFIG_FILE" "install.dir")

echo
echo "current_dir: "$CUR_DIR
echo "install_dir: "$INST_DIR
echo

echo
echo "This module is installed at $INST_DIR/"
echo

## 설치디렉토리가 설정되지 않은 경우 종료
if [ ! $INST_DIR ]
then
	echo "Installation Directory MUST BE SET."
	
	exit 2
fi

## 현재 디렉토리와 설치 디렉토리가 동일한 경우 종료
if [[ "$INST_DIR" == "$CUR_DIR" ]];
then
	echo
	
	echo
	echo "Current directory is equal to a install directory."
	echo
	
	echo
	
	exit 2
fi


## 서비스 등록 여부
AS_A_SERVICE=$(read_prop "$CONFIG_FILE" "service.registration")

# 서비스로 등록하는 경우
if [ "$AS_A_SERVICE" = "Y" ];
then
	## 기존 서비스 정지
	echo "## 기존 서비스 정지"
	OS_SERVICE_DIR=$CUR_DIR/$OS_NAME/$OS_VERSION
	check_dir_then_exit "$OS_SERVICE_DIR" 1
	
	echo "cd $OS_SERVICE_DIR"
	cd $OS_SERVICE_DIR
	INST_SVC_SH=$(read_prop "$CONFIG_FILE" "service.registration.script")
	# 서비스 정지
	{
		./$INST_SVC_SH --config $CONFIG_FILE --exec-cmd stop --profile $PROFILE
	}||{
		echo
		
		echo
		echo " >>>>>>>>>>>>>>> OooooooooooooooPs !!! <<<<<<<<<<<<<< "
		echo
		
		echo
		exit 2
	}
fi

sleep 1

echo
echo "cd $CUR_DIR"
cd $CUR_DIR

## 설치디렉토리 무조건 초기화
echo
echo "Initialize a installation directory" 
echo
{
	if [ -d $INST_DIR ];
	then
		rm -rf $INST_DIR/*
	else
		rm -rf $INST_DIR
		mkdir -p $INST_DIR	
	fi
}||{
	echo
	
	echo
	echo "[Error] Fail to create a directory, $INST_DIR/" >2
	echo
	
	echo
	
	exit 2
}

echo 
echo "### copy resource directories ###" 
echo

# $1 {string} full filepath
# $@:1 {any} properties
update_file(){
	local targetfile=$1
	
	if [ -f "$targetfile" ];
	then
		echo
		echo "[DETECTED] $targetfile"
		update_properties $@
	fi
}

## begin: 디렉토리 복사
RES_DIRS=($(read_prop "$CONFIG_FILE" "resources.directories"))
for res_dir in "${RES_DIRS[@]}";
do
	{	
		if [  -d "$CUR_DIR/../$res_dir" ]; then
			# begin: 디렉토리별로 추가작업을 처리
			case "$res_dir" in
				config)
					# 로그파일 설정적용
					logfilename=$(read_prop "$CONFIG_FILE" "log.configuration.filename")
					logproperties=$(read_prop "$CONFIG_FILE" "log.configuration.properties")
					if [ ! -z "$logfilename" ] && [ ! -z "$logproperties" ];
					then
						update_file "$CUR_DIR/../$res_dir/$logfilename" "$logproperties"
					fi
					;;
				crontab)
					# crontab 설정 적용
					cronfilename=$(read_prop "$CONFIG_FILE" "cron.configuration.filename")
					cronproperties=$(read_prop "$CONFIG_FILE" "cron.configuration.properties")
					if [ ! -z "$cronfilename" ] && [ ! -z "$cronproperties" ];
					then
						update_file "$CUR_DIR/../$res_dir/$cronfilename" "$cronproperties"
					fi
					;;
				monitor)
					# 모니터링 파일 설정 설정 적용
					mtrfilenames=$(read_prop "$CONFIG_FILE" "monitor.configuration.filename")
					mtrproperties=$(read_prop "$CONFIG_FILE" "monitor.configuration.properties")
					if [ ! -z "$mtrfilenames" ] && [ ! -z "$mtrproperties" ];
					then
						# 디렉토리에 있는 모든 파일
						if [ "$mtrfilenames" == "\*" ];
						then
							_files=$(ls -p $CUR_DIR/../$res_dir/ | grep -v "/")
							for _file in ${_files[@]}
							do
								update_file "$CUR_DIR/../$res_dir/$_file" "$mtrproperties"																
							done
						else
							_files=($mtrfilenames)
							for _file in ${_files[@]}
							do
								update_file "$CUR_DIR/../$res_dir/$_file" "$mtrproperties"																
							done
						fi
					fi
					;;					
			esac
			# end: 디렉토리별로 추가작업을 처리
			
			# 복사
			cp -R $CUR_DIR/../$res_dir $INST_DIR/
			echo "[SUCCESS] cp -R $CUR_DIR/../$res_dir $INST_DIR/"
		else
			echo "[FAIL] $CUR_DIR/../$res_dir does NOT EXIST !!!"
		fi
	}||{
		echo
		
		echo
		echo "[Errors] step: 'copy resource directories', directory: $res_dir"
		echo
		
		echo
		
		exit 2
	}
done
## end: 디렉토리 복사

## 소스 디렉토리 안의 파일을 대상 디렉토리로 복사
copy_files(){
	local SOURCE=$1
	local TARGET=$2
	local files=$(ls -ap $SOURCE | grep -v /)
	
	for file in $files;
	do
		{
			if [ -f "$SOURCE/$file" ]; then
				cp $SOURCE/$file $TARGET/
				echo "[SUCCESS] cp $SOURCE/$file $TARGET/" 
			else
				echo "[FAIL] $SOURCE/$file does NOT EXIST"
			fi
		}||{
			echo
			
			echo
			echo "[Errors] step: 'copy resource file', file: $file"
			echo
			
			echo
			
			exit 2
		}
	done 
} 

echo 
echo "### copy resoureces files ###" 
echo
## 모듈 관련 파일 복사 
copy_files $CUR_DIR/.. $INST_DIR

echo 
echo "### copy configuration files ###" 
echo
## 서비스 설정 파일 복사(/workdir/service.propertites)
echo
{
	cp $CONFIG_FILE $INST_DIR/
	echo "[SUCCESS] cp $CONFIG_FILE $INST_DIR/"
}||{
	echo
	
	echo
	echo "[Errors] step: 'copy configuration file', file: $CONFIG_FILE" 
	echo
	
	echo
	
	exit 2
}
echo

sleep 0.2

## WAR 파일 설정 확인
WAR_FILE=$(read_prop "$CONFIG_FILE" "war_file")
if [ ! -z "$WAR_FILE" ]
then
	echo " ---- DETECTED 'WAR' configuration ----"
	echo "COPY WAR file  "
	WARFILE_PATH=$CUR_DIR/../war/$WAR_FILE.war
	TOMCAT_DIR=$(read_prop "$CONFIG_FILE" "apache_tomcat_dir")
	
	if [ -f "$WARFILE_PATH" ]
	then
	  echo "[WAR file] $WARFILE_PATH FOUND!"
	else
	  echo "[WAR file] $WARFILE_PATH NOT FOUND!"
	  
	  exit 2
	fi
	
	if [ -d "$TOMCAT_DIR" ]
	then
	  echo "[TOMCAT] $TOMCAT_DIR FOUND!"
	else
	  echo "[TOMCAT] $TOMCAT_DIR NOT FOUND!"
	  
	  exit 2
	fi
	
	rm -rf $TOMCAT_DIR/webapps/$WAR_FILE/
	echo "[SUCCESS] rm -rf $TOMCAT_DIR/webapps/$WAR_FILE/"
	
	rm -rf $TOMCAT_DIR/webapps/$WAR_FILE.war
	echo "[SUCCESS] rm -rf $TOMCAT_DIR/webapps/$WAR_FILE.war"
	
	echo
	cp $WARFILE_PATH $TOMCAT_DIR/webapps/
	echo "[SUCCESS] cp $WARFILE_PATH $TOMCAT_DIR/webapps/"
fi

sleep 0.2

## 서비스로 등록하는 경우
if [ "$AS_A_SERVICE" = "Y" ];
then
	## 서비스 등록
	echo
	echo "## [REGISTER] Service Unit ##"
	echo
	
	## 운영체제 버전 디렉토리로 이동
	cd $OS_SERVICE_DIR
	./$INST_SVC_SH --config $CONFIG_FILE  --profile $PROFILE
	
	echo
	echo "GOTO '$INST_DIR'"
fi

echo
echo "bye~"
echo
