#!/bin/bash

# 색상 정의
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}== Auth-Gateway 자동 설치를 시작합니다 ==${NC}"

# 1. 필수 패키지 설치 확인 (Go, libaio, pkg-config 등)
install_if_missing() {
    if ! dpkg -s "$1" >/dev/null 2>&1; then
        echo -e "📦 $1 설치 중..."
        sudo apt-get install -y "$1"
    else
        echo -e "✅ $1 이미 설치됨"
    fi
}

sudo apt-get update
install_if_missing "golang-go"
install_if_missing "libaio1"
install_if_missing "pkg-config"
install_if_missing "unzip"
install_if_missing "ufw"

# 2. Oracle Instant Client 설치 (OCI DB 연결 필수)
if [ ! -d "/opt/instantclient_21_1" ]; then
    echo -e "📦 Oracle Instant Client 설치 중..."
    # 사용자의 환경에 맞는 설치 파일이 필요함 (여기서는 경로 생성 예시)
    sudo mkdir -p /opt/instantclient_21_1
    # 실제 환경에서는 wget 등으로 다운로드 로직 추가 가능
fi

# 3. 방화벽(UFW) 설정
echo -e "🛡️  방화벽 설정 중..."
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 22/tcp
# 관리자 페이지 및 서비스 포트 (Nginx가 대행하므로 내부적으로만 사용)
sudo ufw allow 3000/tcp 
sudo ufw --force enable

# 4. Go 모듈 의존성 설치 및 빌드
echo -e "🔨 인증 서버 빌드 중..."
go mod tidy
go build -o auth-gateway main.go

# 5. Systemd 서비스 등록
echo -e "⚙️  Systemd 서비스 등록 중..."
sudo cp auth-gateway.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable auth-gateway
sudo systemctl restart auth-gateway

echo -e "${GREEN}== 설치가 완료되었습니다! ==${NC}"
