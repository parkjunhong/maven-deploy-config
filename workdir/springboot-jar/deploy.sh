#!/bin/bash

echo
echo "###############################################################"
echo "### -------------------- deploy.sh ------------------------ ###"
echo "### -------------------- deploy.sh ------------------------ ###"
echo "### -------------------- deploy.sh ------------------------ ###"
echo "###############################################################"

# $1 {string} variable name
# $2 {any} value
assign(){
    eval $1=\"$2\"
}

usage(){
	echo
	echo ">>> CALLED BY [[ $1 ]]"
	echo
	echo "[Usage]"
	echo
	echo "./deploy.sh -c <configuration>"
	echo
	echo "[Option]"
	echo " -c, --config     : (Optional) 설정파일 절대경로. 기본값: service.properties"
	echo " -h, --help       : 도움말"
	echo
	echo
	echo " ================ OPERATING SYSTEM INFORMATION ================ "
	cat /etc/*-release
	echo " =============================================================== "
}

support_msg(){
	echo 
	echo " ================ OPERATING SYSTEM INFORMATION ================ "
	echo
	echo " Supporting System: CentOS 6, 7 / Ubuntu 16, 18"
	echo
	echo " -------------------------------------------------------------- "
	cat /etc/*-release
	echo " -------------------------------------------------------------- "
	echo " =============================================================== "
}

# 기본설정 파일
CONFIG_FILE="service.properties"

## 파라미터 읽기
while [ "$1" != "" ]; do
	case $1 in
		-c | --config)
			shift
			CONFIG_FILE=$1
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

validate() {
	local INP_VALUE=$1
	local SYS_VALUE=$2
	
	if [ "$INP_VALUE" != "$SYS_VALUE" ]
	then
		echo
		echo
		echo " ============ SYSTEM INFORMATION============ "
		cat /etc/*-release
		echo " =========================================== "
		echo
		echo
		usage "Illegal System Information"
		exit 2
	fi
}

# Assigns a value input by a user to variable.  
# $1 {string} Question Message.
# $2 {string} varaible
read_cli(){
    local variable="$2"
    local confirm="N"
    local answer=""

    while [ "$confirm" != "Y" ];
    do
        echo
        read -p "$1 -> " answer
        read -p "Your answer is '$answer'. Right? [Y/N] -> " confirm
        local confirm=$(echo $confirm | tr [:lower:] [:upper:])
    done

    assign "$variable" "$answer"
}

# Loads OS name and OS version. 
load_os_info(){
	# CentOS 7 or higher, Ubuntu 16 or higher
	local releasefile="/etc/os-release"
	
	if [ -f "$releasefile" ];
	then
		echo
		echo " ---> read $releasefile"
		OS_NAME=$(cat /etc/os-release | grep -i "^id=" | sed -e "s/\"//g" | sed -e "s/id=//gi" | tr [:upper:] [:lower:])
		OS_VERSION=$(cat /etc/os-release | grep -i "^VERSION_id=" | sed -e "s/\"//g" | sed -e "s/version_id=//gi" | tr -dc '0-9.' | cut -d \. -f1)			
	else
		# CentOS 6
		local releasefile="/etc/centos-release" 
		if [ -f "$releasefile" ];
		then
			echo
			echo " ---> read $releasefile"
			OS_NAME=$(cat /etc/centos-release | awk {'print $1'} | tr [:upper:] [:lower:])
			OS_VERSION=$(cat /etc/centos-release | tr -dc '0-9.'|cut -d \. -f1)
		else
			support_msg
			echo
			read -p "Insert your OS Name. (See 'OPERATING SYSTEM INFORMATION' above.) " OS_NAME			
			read -p "Insert your OS version (only Major value). (See 'OPERATING SYSTEM INFORMATION' above.) " OS_VERSION
		fi
	fi
	
	echo
	echo "OS Name="$OS_NAME
	echo "OS Verson="$OS_VERSION
}

check_centos(){
	echo
	echo "-------- ${FUNCNAME[0]} --------"
	
	local OSN=$(cat /etc/centos-release | awk {'print $1'} | tr [:upper:] [:lower:])
	validate $OS_NAME $OSN
	
	local OSV=$(cat /etc/centos-release | tr -dc '0-9.'|cut -d \. -f1)
	validate $OS_VERSION $OSV
}

check_ubuntu(){
	echo
	echo "-------- ${FUNCNAME[0]} --------"
		
	local OSN=$(cat /etc/os-release | grep -i "^NAME=" | sed -e "s/\"//g" | sed -e "s/name=//gi" | tr [:upper:] [:lower:])
	validate $OS_NAME $OSN
		
	local OSV=$(cat /etc/os-release | grep -i "^VERSION=" | sed -e "s/\"//g" | sed -e "s/version=//gi" | tr -dc '0-9.' | cut -d \. -f1)
	validate $OS_VERSION $OSV	
}


# $1 {string} Question message.
# $2 {string} "Y"es string.
# $3 {string} "N"o string.
# $4 {string} response variable
yesOrNo(){
	local yesorno_answer=""
	while [ -z $yesorno_answer ] || ( [ "$2" != "$yesorno_answer" ] && [ "$3" != "$yesorno_answer" ] );
	do
		echo
		read -p "$1 [$2/$3] ? " yesorno_answer
			
		local yesorno_answer=$(echo $yesorno_answer | tr [:lower:] [:upper:] )
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

# Build 프로파일 읽기
# $1 {string} 빌드명
load_profile(){
	local build_name="$1"
	## profile 검증
	if [ -f "./$build_name/.profile" ];
	then
		BUILTIN_PROFILE=$(cat ./$build_name/.profile)
	fi
	
	if [ -z $BUILTIN_PROFILE ];
	then
		echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
		echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
		echo
		echo "	Cannot find a built-in profile."
		echo "	So cannot verify this installation."
		
		yesOrNo "	Do you want to process this installation" "Y" "N" "ANSWER"
		
		if [ "$ANSWER" == "N" ];
		then
			clean_temp_dir
			
			echo
			echo "	+++ INSTALLATION is interrupted... +++"
			echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
			
			exit 0
		fi
		
		read -p "	Please, input a new profile name. Or just push the enter key if no profile !!! " PROFILE
		
		echo "	YOUR PROFILE is $PROFILE. "
		echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	else
		PROFILE=$BUILTIN_PROFILE
	fi
}

## 설정파일이 전달되지 않은 경우 종료
if [ -f "$CONFIG_FILE" ]
then
	echo "[Configurations] $CONFIG_FILE FOUND!"
else
	echo "[Configurations] $CONFIG_FILE NOT FOUND!"

	usage "No Configuration file"

	exit 0
fi


## 서비스 등록 여부
AS_A_SERVICE=$(read_prop "$CONFIG_FILE"  "service.registration")
# 서비스로 등록하는 경우
if [ "$AS_A_SERVICE" == "Y" ];
then
	load_os_info
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

echo "========================================================="


## 설정파일 절대 경로
CONFIG_FILE_PATH=$(pwd)/$CONFIG_FILE

CUR_DIR=$(pwd)
## 임시 디렉토리 설정
TMP_DIR=$(read_prop "$CONFIG_FILE" "work_tmp_dir")
if [ -d $TMP ];
then
	mkdir -p $TMP_DIR
fi

clean_temp_dir(){
	cd $CUR_DIR
	rm -rf $TMP_DIR
}

echo
BUILD_NAME=$(read_prop "$CONFIG_FILE" "build.name")
BUILD_FILE=$(read_prop "$CONFIG_FILE" "build.file")
echo
cp ./deploy.sh $TMP_DIR/
echo "[SUCCESS] cp ./deploy.sh $TMP_DIR/"
echo
cp ./service.properties $TMP_DIR/
echo "[SUCCESS] cp ./service.properties $TMP_DIR/"
echo
cp ./$BUILD_FILE $TMP_DIR/
echo "[SUCCESS] cp ./$BUILD_FILE $TMP_DIR/"
echo
echo

## 임시 디렉토리 이동
cd $TMP_DIR/

## 이전 설치파일 디렉토리 삭제
BUILD_NAME=""
echo
echo "Remove a old directory"
{
	BUILD_NAME=$(read_prop "$CONFIG_FILE" "build.name")
	rm -rf $BUILD_NAME
	echo "[SUCCESS]  rm -rf $BUILD_NAME"
}||{
	
	clean_temp_dir
	
	echo " >>>>>>>>>>>>>>> OooooooooooooooPs !!! <<<<<<<<<<<<<< "
	exit 1
}
echo "OK!"

## 설치파일 압축 해제
echo
echo "Extract a new deployment file."
{
	tar -zxf $BUILD_FILE
	echo "[SUCCESS]  tar -zxf $BUILD_FILE"
	
	load_profile "$BUILD_NAME"
	
}||{
	clean_temp_dir
	echo " >>>>>>>>>>>>>>> OooooooooooooooPs !!! <<<<<<<<<<<<<< "
	exit 1
}
echo "OK!"

echo
echo " ==============================================================================="
echo " >>>>>>>>>>>>>>>>>> INSTALL '$PROFILE' version >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo " ==============================================================================="


## 프로그램 설치모듈 경로
INST_MODULE_DIR="./"$(read_prop "$CONFIG_FILE" "build.name")/$(read_prop "$CONFIG_FILE" "install.module.directory")
## 프로그램 설치모듈 shell 파일
INST_MODULE_SH=$(read_prop "$CONFIG_FILE" "install.module.script")

echo
echo "Go into a installation directory: "$INST_MODULE_DIR
cd $INST_MODULE_DIR
echo "directory: "$(pwd)
echo

echo "Run a installation shell, ./"$INST_MODULE_SH
{
	echo
	
	# 서비스로 등록하는 경우
	if [ "$AS_A_SERVICE" = "Y" ];
	then
		echo
		echo "./$INST_MODULE_SH -config $CONFIG_FILE_PATH --profile $PROFILE --os-name $OS_NAME --os-version $OS_VERSION"
		./$INST_MODULE_SH --config $CONFIG_FILE_PATH --profile $PROFILE --os-name $OS_NAME --os-version $OS_VERSION
	else
		echo
		echo "./$INST_MODULE_SH --config $CONFIG_FILE_PATH --profile $PROFILE"
		./$INST_MODULE_SH --config $CONFIG_FILE_PATH --profile $PROFILE
	fi
	echo
	echo "------------------------------------------------"
	echo "------------------------------------------------"
	echo "------------------------------------------------"
}||{
	clean_temp_dir
	
	echo 
	
	echo
	echo " >>>>>>>>>>>>>>> OooooooooooooooPs !!! <<<<<<<<<<<<<< "
	echo 
	
	exit 1
}

clean_temp_dir

echo "------------------------------------------------"
echo "------------------------------------------------"
echo "------------------------------------------------"
echo
echo "Bye~"
