# Day 01

### 1. Go 모듈 초기화

Go 모듈 초기화:
```sh
go mod init github.com/kimrakji/sre-lab
```
- Go에서 모듈 이름을 보통 실제 저장소 경로와 맞추는 관례가 있음.

참고로 수정도 가능함:
- go.mod의 첫 줄:
```go
module github.com/kimrakji/sre-lab
```
- 이 부분을 바꾸면 됨.

### 2. Go 애플리케이션 생성

main.go 생성:
```go
package main

import (
	"fmt"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "hello from sre-lab")
	})

	http.ListenAndServe(":8080", nil)
}
```

실행:
```sh
go run .
```

테스트:
```sh
curl localhost:8080
```

결과:
```sh
hello from sre-lab
```

### 3. Dockerfile 작성

Dockerfile 작성:
```sh
touch Dockerfile
```

```dockerfile
FROM golang:1.26 AS builder
# Go가 설치된 이미지를 빌드 전용으로 사용
# go.mod의 go directive에 프로젝트가 요구하는 최소 Go 버전이 명시되어 있으므로, builder도 이를 만족하는 Go 버전을 사용해야 함.
# "AS builder"는 이 단계에 builder라는 이름을 붙인 것

WORKDIR /app
# 컨테이너 내부 작업 디렉터리를 /app으로 설정
# shell에서의 `cd /app`과 유사

COPY . .
# 현재 프로젝트 파일들을 현재 디렉터리(/app)으로 복사
# COPY <source> <destination>
# 첫 번째 .  = build context의 현재 디렉터리
# 두 번째 .  = 이미지 내부 현재 WORKDIR (/app)

RUN CGO_ENABLED=0 GOOS=linux go build -o sre-lab .
# go build로 실행 파일을 하나로 만듦.
# CGO_ENABLED=0 : CGO를 끄겠다 = C 라이브러리에 의존하지 않는 독립적인 Go 바이너리로 빌드
# GOOS=linux : 이 바이너리는 Linux용으로 빌드
# -o sre-lab : 출력 파일(바이너리) 이름 지정

FROM scratch
# 완전히 새로운 이미지 시작
# scratch는 사실상 아무 것도 없는 빈 이미지
# 즉 최종 컨테이너에는: Go 컴파일러 없음 / shell 없음 / apt 없음 / 소스코드 없음

COPY --from=builder /app/sre-lab /sre-lab
# 빌드 단계에서 만든 실행 파일 하나(/sre-lab)만 가져옴

ENTRYPOINT ["/sre-lab"]
# 컨테이너가 시작되면 sre-lab 바이너리를 실행하라는 뜻
```
- FROM - WORKDIR(/app) - COPY - RUN(build)
- FROM - COPY - ENTRYPOINT

전체 흐름을 보면:
```txt
main.go
  ↓
golang:1.26
  ↓
go build
  ↓
sre-lab 바이너리
  ↓
scratch
  ↓
최종 컨테이너
```
- 이 방식을 ==multi-stage build==라고 함.
- 최종 이미지에 Go 개발환경을 전부 넣지 않고 아티팩트 하나만 넣을 수 있어서 아주 단순하게 만들 수 있음.

### 4. 도커 이미지 빌드

도커 이미지 빌드:
```sh
docker build -t sre-lab:0.1 .
```
- `docker build -t <이미지명:태그명> <build_context>`
- `-t sre-lab:0.1` : 이미지에 sre-lab이라는 이름과, 0.1이라는 태그를 붙임
- Dockerfile은 기본적으로 그 build_context의 Dockerfile을 찾음.

빌드 결과 확인:
```sh
docker image ls | grep sre-lab
```

컨테이너 run (빌드된 이미지 테스트):
```sh
docker run --rm -p 8080:8080 sre-lab:0.1
```
- `--rm`: 컨테이너 종료 시 컨테이너 자동 삭제

정상 작동 확인:
```sh
curl localhost:8080
```

### 5. Git에 반영

변경사항 확인 - 커밋 - 푸시:
```sh
git status

git add .
git commit -m "feat: add initial Go service container"

git push
```

- Go 앱 작성 → 로컬 실행 → 이미지 빌드 → 컨테이너 실행 → HTTP 응답 검증 → 커밋
- K8s에 올릴 최소 Go 서비스 하나를 만들고, 컨테이너로 실행 가능하다는 것까지 검증한 것
