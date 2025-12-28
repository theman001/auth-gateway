package main

import (
	"database/sql"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/godror/godror"
	"golang.org/x/crypto/bcrypt"
	"gopkg.in/yaml.v3"
)

// Config 구조체: config.yaml 매핑
type Config struct {
	Database struct {
		User          string `yaml:"user"`
		Password      string `yaml:"password"`
		ConnectString string `yaml:"connect_string"`
		WalletPath    string `yaml:"wallet_path"`
	} `yaml:"database"`
	Server struct {
		Host      string `yaml:"host"`
		Port      string `yaml:"port"`
		TargetUrl string `yaml:"target_url"`
	} `yaml:"server"`
	Security struct {
		SessionName   string `yaml:"session_name"`
		SessionExpiry string `yaml:"session_expiry"`
	} `yaml:"security"`
	UI struct {
		Title        string `yaml:"title"`
		DefaultTheme string `yaml:"default_theme"`
	} `yaml:"ui"`
}

var (
	db   *sql.DB
	conf Config
)

func init() {
	// 설정 파일 로드
	f, err := os.Open("config.yaml")
	if err != nil {
		log.Fatal("설정 파일을 찾을 수 없습니다: ", err)
	}
	defer f.Close()
	decoder := yaml.NewDecoder(f)
	err = decoder.Decode(&conf)
	if err != nil {
		log.Fatal("설정 파일 파싱 실패: ", err)
	}

	// Oracle 환경 변수 설정
	os.Setenv("TNS_ADMIN", conf.Database.WalletPath)
}

func main() {
	// DB 연결
	var err error
	dsn := fmt.Sprintf(`user="%s" password="%s" connectString="%s"`,
		conf.Database.User, conf.Database.Password, conf.Database.ConnectString)
	db, err = sql.Open("godror", dsn)
	if err != nil {
		log.Fatal("DB 연결 실패: ", err)
	}
	defer db.Close()

	// 라우터 설정
	http.HandleFunc("/login", loginHandler)
	http.HandleFunc("/api/verify", verifyHandler)
	http.HandleFunc("/admin", adminOnly(adminPageHandler))
	http.HandleFunc("/api/admin/users", adminOnly(adminUserCreateHandler))

	addr := fmt.Sprintf("%s:%s", conf.Server.Host, conf.Server.Port)
	fmt.Printf("🚀 %s 가 구동 중입니다: %s\n", conf.UI.Title, addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}

// --- 인증 및 권한 로직 (기존 로직 유지하되 Config 참고) ---

func verifyHandler(w http.ResponseWriter, r *http.Request) {
	cookie, err := r.Cookie(conf.Security.SessionName)
	if err != nil {
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	var userID string
	err = db.QueryRow("SELECT USER_ID FROM SESSIONS WHERE SESSION_ID = :1 AND EXPIRES_AT > CURRENT_TIMESTAMP", cookie.Value).Scan(&userID)
	if err != nil {
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func adminOnly(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie(conf.Security.SessionName)
		if err != nil {
			http.Redirect(w, r, "/login", http.StatusSeeOther)
			return
		}
		var isAdmin int
		err = db.QueryRow(`SELECT u.IS_ADMIN FROM USERS u JOIN SESSIONS s ON u.USER_ID = s.USER_ID 
			WHERE s.SESSION_ID = :1 AND s.EXPIRES_AT > CURRENT_TIMESTAMP`, cookie.Value).Scan(&isAdmin)
		if err != nil || isAdmin != 1 {
			http.Error(w, "Access Denied", http.StatusForbidden)
			return
		}
		next(w, r)
	}
}

// ... 기타 핸들러 (loginHandler, adminPageHandler 등) 기존 로직에서 변수명만 수정 ...
