#!/bin/bash

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}== Auth-Gateway 초정밀 자동 설치 시작 (SSL & Oracle Client 포함) ==${NC}"

# 1. 필수 패키지 설치
sudo apt-get update
packages=(nginx golang-go ufw jq unzip libaio1 certbot python3-certbot-nginx wget)
for pkg in "${packages[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        echo -e "📦 $pkg 설치 중..."
        sudo apt-get install -y "$pkg"
    fi
done

# 2. config.yaml 값 추출 함수
get_config() {
    grep "$1" config.yaml | sed "s/.*: //" | sed 's/"//g' | tr -d '\r'
}

AUTH_PORT=$(get_config "port")
TARGET_URL=$(get_config "target_url")
WALLET_PATH=$(get_config "wallet_path")
DOMAIN=$(get_config "domain") # config.yaml에 domain 항목 추가 필요

# 3. Oracle Instant Client 자동 설치
IC_PATH="/opt/oracle/instantclient"
if [ ! -d "$IC_PATH" ]; then
    echo -e "📦 Oracle Instant Client 다운로드 및 설정 중..."
    sudo mkdir -p /opt/oracle
    cd /opt/oracle
    sudo wget https://download.oracle.com/otn_software/linux/instantclient/211000/instantclient-basic-linux.x64-21.1.0.0.0.zip
    sudo unzip instantclient-basic-linux.x64-21.1.0.0.0.zip
    sudo mv instantclient_21_1 instantclient
    sudo rm *.zip
    
    # 환경 변수 등록
    echo "export LD_LIBRARY_PATH=$IC_PATH:\$LD_LIBRARY_PATH" | sudo tee -a /etc/environment
    echo "export TNS_ADMIN=$WALLET_PATH" | sudo tee -a /etc/environment
    source /etc/environment
    cd -
fi

# 4. Nginx 설정 생성 (SSL 미적용 상태로 우선 생성)
NGINX_CONF="/etc/nginx/sites-available/auth-gateway"
sudo bash -c "cat > $NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

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

    location /login { proxy_pass http://127.0.0.1:$AUTH_PORT/login; }
    location /admin { proxy_pass http://127.0.0.1:$AUTH_PORT/admin; }
    location /api/admin/ { proxy_pass http://127.0.0.1:$AUTH_PORT/api/admin/; }
}
EOF

sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl restart nginx

# 5. SSL 인증서 자동 발급 (Certbot)
if [ "$DOMAIN" != "" ] && [ "$DOMAIN" != "localhost" ]; then
    echo -e "🔒 SSL 인증서(HTTPS) 발급 중..."
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN
fi

# 6. Go 빌드 및 서비스 등록
go mod tidy
go build -o auth-gateway main.go

# Systemd 서비스 파일 생성 및 등록
sudo bash -c "cat > /etc/systemd/system/auth-gateway.service" <<EOF
[Unit]
Description=Auth Gateway Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/auth-gateway
Restart=always
Environment="LD_LIBRARY_PATH=$IC_PATH"
Environment="TNS_ADMIN=$WALLET_PATH"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable auth-gateway
sudo systemctl restart auth-gateway

# 7. 방화벽 설정
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 22/tcp
sudo ufw --force enable

echo -e "${GREEN}== 모든 설치 및 보안 설정(HTTPS/Firewall)이 완료되었습니다! ==${NC}"
