# History
변경 이력을 기록합니다.

---

[2025/06/26]
- 디렉토리를 지정하고 그 하위의 파일을 복사하는 경우, 하위 디렉토리 구조를 유지하도록 추가.
  - &lt;useDefaultExcludes&gt;false&lt;/useDefaultExcludes&gt;
- kr.co.ymtech.dev.spring-boot:ymtech-spring-boot-start-parent 버전 변경: 0.2.0-SNAPSHOT

[2020/03/24]
- 배포, 설치 및 서비스 등록을 위한 스크립트 통합
- 서비스 등록을 위한 템플릿 및 제어 스크립트 이관 (shell/install -> workdir/install)
- 제어 스크립트 동적 생성 적용
- assembly용 xml 내용 변경

[2019/11/21]
- war 파일 빌드 적용 및 jar 와 분리
