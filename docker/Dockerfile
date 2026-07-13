# 1. Base Image 설정
FROM ${dockerfile.baseimage}

# 2. 빌드 시 주입받을 변수 설정
ARG GROUP_NAME=${group}
ARG BUILD_NAME=${build.name}

# 3. 컨테이너 내부의 작업 디렉토리 환경 변수 설정 및 이동
ENV APP_HOME=/app/${GROUP_NAME}/${BUILD_NAME}
WORKDIR ${APP_HOME}

# 4. 필수 바이너리 및 실행 스크립트 복사
# (Build Context가 임시 디렉토리로 지정되어야 아래 COPY가 정상 동작합니다)
COPY ${BUILD_NAME}.jar .
COPY d-start.sh ./start.sh
COPY lib/ ./lib/

# 5. 스크립트 실행 권한 부여
RUN chmod +x start.sh

# 6. 컨테이너 실행 시 기본 커맨드 지정
ENTRYPOINT ["./start.sh"]