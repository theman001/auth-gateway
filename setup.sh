#!/bin/bash

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}== Auth-Gateway & Nginx 자동 설정 시작 ==${NC}"

# 1. 필수 패키지 설치 확인
install_if_missing() {
    if ! dpkg -s "$1" >/dev/null 2>&1; then
        echo -e "📦 $1 설치 중..."
        sudo apt-get install -y "$1"
    else
        echo -e "✅ $1 이미 설치됨"
    fi
}

sudo apt-get update
install_if_missing "nginx"
install_if_missing "golang-go"
install_if_missing "ufw"
install_if_missing "jq" # YAML 처리를 돕기 위한 도구

# 2. config.yaml에서 필요한 값 추출 (단순 파싱)
get_config() {
    grep "$1" config.yaml | sed "s/.*: //" | sed 's/"//g' | tr -d '\r'
}

AUTH_PORT=$(get_config "port")
TARGET_URL=$(get_config "target_url")
DOMAIN=$(hostname -I | awk '{print $1}') # 기본값으로 현재 IP 사용 (사용자가 나중에 수정 가능)

echo -e "⚙️  설정 로드 완료: Auth($AUTH_PORT) -> Target($TARGET_URL)"

# 3. Nginx 설정 파일 자동 생성
NGINX_CONF="/etc/nginx/sites-available/auth-gateway"

echo "📝 Nginx 설정 생성 중: $NGINX_CONF"
sudo bash -c "cat > $NGINX_CONF" <<EOF
server {
    listen 80;
    server_name _; # 실제 도메인이 있다면 여기에 입력

    location / {
        auth_request /auth-verify;
        proxy_pass $TARGET_URL;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location = /auth-verify {
        internal;
        proxy_pass http://127.0.0.1:$AUTH_PORT/api/verify;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
    }

    location /login {
        proxy_pass http://127.0.0.1:$AUTH_PORT/login;
        proxy_set_header Host \$host;
    }

    location /admin {
        proxy_pass http://127.0.0.1:$AUTH_PORT/admin;
        proxy_set_header Host \$host;
    }

    location /api/admin/ {
        proxy_pass http://127.0.0.1:$AUTH_PORT/api/admin/;
        proxy_set_header Host \$host;
    }
}
EOF

# 4. Nginx 설정 활성화 및 재시작
sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx

# 5. Go 서버 빌드 및 서비스 등록 (기존 로직)
go mod tidy
go build -o auth-gateway main.go

# 6. 방화벽 설정
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 22/tcp
sudo ufw --force enable

echo -e "${GREEN}== 모든 설치 및 Nginx 설정이 완료되었습니다! ==${NC}"
echo -e "접속 주소: http://$DOMAIN/login"
