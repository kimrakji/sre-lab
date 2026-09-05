# Day 03

> "Pod가 Running이라는 것과 트래픽을 받을 준비가 됐다는 것은 왜 다른가?"

### 1. 기존 환경 복구 및 상태 확인

(vm) 기존 상태 확인:
```sh
sudo k3s kubectl get node

sudo k3s kubectl get deployment

sudo k3s kubectl get pod
```

### 2. Kubernetes Service 생성

k8s/service.yaml 생성:
```yaml
apiVersion: v1
kind: Service
metadata: 
  name: sre-lab
spec:
  selector:
    app: sre-lab
  ports:
  - port: 80
    targetPort: 8080
```
- `ports[].port` = Service 자체가 노출하는 포트
- `ports[].targetPort` = Service가 실제 Pod로 전달할 목적지 포트
- `ports`가 리스트인 이유는 하나의 Service가 여러 포트를 노출할 수도 있기 때문임.
- 사실 `spec.type`에 값이 있지만 생략할 경우 기본값은 `ClusterIP`
  - ClusterIP: 클러스터 내부에서만 접근 가능한 서비스 타입.

흐름으로 보면:
```txt
Client
  ↓
Service :80
  ↓
Pod :8080
  ↓
Go App
```

(local) service.yaml 파일 복사(Mac → VM):
```sh
scp k8s/service.yaml rakji@192.168.105.6:~/
```

(vm) VM에서 적용:
```sh
sudo k3s kubectl apply -f ~/service.yaml
```

(vm) 적용 확인:
```sh
sudo k3s kubectl get service
```

### 3. Service를 통한 요청 확인

Service가 실제로 어떤 Pod들을 바라보는지 확인:
```sh
sudo k3s kubectl get endpoints sre-lab
# OR
sudo k3s kubectl get ep sre-lab
```
또는 최신 방식으로:
```sh
sudo k3s kubectl get endpointslice
```
- Pod IP 2개가 연결되어있으면 됨:
  - Deployment에서 `replicas: 2`로 만든 Pod가 2개이기 때문
- EndpointSlice = 특정 'Service가 실제로 트래픽을 보낼 대상들의 목록'.
  - Service 자체에 Pod IP가 박혀 있는 게 아님:
    - k8s가 Service의 selector와 Pod의 label을 보고 실제 목적지를 찾아서 ==EndpointSlice라는 별도의 k8s 리소스에 기록==함.

Pod IP를 확인해보면 재밌음:
```sh
sudo k3s kubectl get pods -o wide
```
- 흐름이 다음과 같이 된다는 것을 알 수 있음:
  - Service → *selector* → *Pod label* → EndpointSlice

> 이제 Service를 통해 실제 Go 앱에 요청을 보내보자.

(vm) Service의 ClusterIP 확인:
```sh
sudo k3s kubectl get svc sre-lab
```

(vm) ClusterIP의 Service를 통해 실제 요청:
```sh
curl http://<CLUSTER_IP>:80
```
정상이면 다음과 같이 나옴:
```txt
hello from sre-lab
```

현재 요청 흐름은 다음과 같음:
```txt
curl
  ↓
Service ClusterIP :80
  ↓
EndpointSlice
 ├─ Pod A :8080
 └─ Pod B :8080
  ↓
Go App
```

### 4. Readiness Probe 추가

`/health`는 k8s가 **이 애플리케이션이 지금 요청을 받아도 되는 상태인가?**를 확인할 때 사용하기 위한 용도의 엔드포인트

현재 Go 앱에 /health를 추가해서 정상일 때는:
```txt
HTTP 200 OK
```
를 반환하게 만들어보자.

---

k8s의 Readiness Probe가 주기적으로:
```txt
GET /health
```
이 엔드포인트를 호출함.

응답이 200이면:
```txt
Ready ✅
```

응답 실패나 에러면:
```txt
Ready ❌
```
가 됨. 

중요한 것은 Readiness 실패가 Pod를 죽이는 건 아님:
```txt
Pod
├── Running ✅
└── Ready   ❌
```
즉, 이 상태가 가능함.

그리고 이 상태가 되면 Service가 그 Pod에 정상 트래픽을 보내지 않게 되는 게 이번 실험의 핵심.

즉, `/health`는 그냥:
```txt
"나 지금 트래픽 받아도 됨"
```
이라고 애플리케이션이 k8s에 알려주는 확인 지점이라고 보면 됨.

---
실제로 작업을 진행해보자.

main.go에 다음 코드를 추가:
```go
http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
  w.WriteHeader(http.StatusOK)
  fmt.Fprintln(w, "ok")
})
```

main()은 대략 다음과 같아짐:
```go
func main() {
  http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintln(w, "hello from sre-lab")
  })

  http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    fmt.Fprintln(w, "ok")
  })

  http.ListenAndServe(":8080", nil)
}
```

로컬에서 실행:
```sh
go run .
```

다른 터미널에서:
```sh
curl -i localhost:8080/health
```

여기서 응답이 다음과 같이 나오면 됨:
```txt
HTTP/1.1 200 OK
...
ok
```

> k8s가 /health를 실제로 사용하도록 Readiness Probe를 Deployment에 추가하자.

`k8s/deployment.yaml`의 컨테이너 설정에 추가:
```yaml
...
containers:
- name: sre-lab
  image: sre-lab:0.1
  imagePullPolicy: IfNotPresent
  ports:
  - containerPort: 8080
  readinessProbe:
    httpGet:
      path: /health
      port: 8080
```

의미는 다음과 같음:
```txt
k8s
  ↓
Get Pod_IP:8080/health
  ↓
200 OK
  ↓
Ready ✅
```

새 도커 이미지 버전 생성:
```sh
docker build -t sre-lab:0.2 .
```

빌드 후 확인:
```sh
docker image ls | grep sre-lab
```

deployment.yaml의 이미지 버전 수정:
```yaml
image: sre-lab:0.2
```

이미지를 아카이브 파일로 생성:
```sh
docker save sre-lab:0.2 -o sre-lab-0.2.tar
```

VM으로 이미지 아카이브 파일 복사:
```sh
scp sre-lab-0.2.tar rakji@192.168.105.6:~/
```

(vm) 이미지를 k3s의 containerd에 import:
```sh
sudo k3s ctr image import ~/sre-lab-0.2.tar
```

(vm) 이미지 import 확인:
```sh
sudo k3s ctr image ls | grep sre-lab
```

VM으로 `deployment.yaml` 파일 복사:
```sh
scp k8s/deployment.yaml rakji@192.168.105.6:~/
```

(vm) `새로운 deployment.yaml` 파일 적용:
```sh
sudo k3s kubectl apply -f ~/deployment.yaml
```

(vm) 적용 후 확인:
```sh
sudo k3s kubectl get pod
```

현재 상태:
```txt
Go App
├── /
└── /health

Deployment
└── readinessProbe
    └── GET :8080/health

Pod
├── Running ✅
└── Ready   ✅
```

### 5. Readiness Failure 실험

deployment.yaml에서 Readiness Probe의 포트를 일부러 틀리게 변경:
```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 9999
```

(local) 수정된 `deployment.yaml`을 VM에 복사 :
```sh
scp k8s/deployment.yaml rakji@192.168.105.6:~/
```

(vm) 변경사항 적용:
```sh
sudo k3s kubectl apply -f ~/deployment.yaml
```

(vm) Pod 상태 확인:
```sh
sudo k3s kubectl get pod
```

확인 결과:
```txt
NAME                       READY   STATUS    RESTARTS   AGE
sre-lab-594894f54-2vrzk    1/1     Running   0          37m
sre-lab-594894f54-hzr4r    1/1     Running   0          37m
sre-lab-69fd9b5b5d-6f6f8   0/1     Running   0          15m
```
- **기존 Pod 2개와 새로운 Pod 1개가 동시에 존재**함.

Deployment의 기본 업데이트 전략은 ==RollingUpdate== 방식임.
즉, 기존 Pod를 모두 제거한 뒤 새로운 Pod를 만드는 것이 아니라, 새로운 Pod가 Ready 상태가 되는 것을 확인하면서 기존 Pod를 점진적으로 교체함.

하지만 새 Pod의 Readiness Probe는 9999 포트로 요청하고 있고, 실제 Go 애플리케이션은 8080에서 Listen하고 있으므로 Probe가 실패함.

```txt
새 Pod 생성
    ↓
Container 실행
    ↓
STATUS = Running
    ↓
Readiness Probe 실패
    ↓
READY = 0/1
    ↓
RollingUpdate 진행 정체
    ↓
기존 Ready Pod 2개 유지
```

즉, Running과 Ready는 서로 다른 상태임.
- **Running**: Pod의 컨테이너가 실행 중인 상태
- **Ready**:  해당 컨테이너가 Service 트래픽을 받을 준비가 되었다고 k8s가 판단한 상태

(vm) EndpointSlice도 확인:
```sh
sudo k3s kubectl describe endpointslice
```

확인 결과 세 Pod 모두 Service의 selector와 일치하므로 EndpointSlice에 등록되어 있음:
```txt
EndpointSlice
├── 기존 Pod A → Ready: true
├── 기존 Pod B → Ready: true
└── 새로운 Pod C → Ready: false
```
새 Pod 역시 Service의 selector에 매칭되므로 EndpointSlice에는 등록되지만, Readiness Probe가 실패했기 때문에 Ready: false 상태이며 정상적인 Service 트래픽 대상에서는 제외됨.

역할을 구분하면:
```txt
Deployment / ReplicaSet
→ Pod 생성 ⋅ 삭제 ⋅ 교체 ⋅ 개수 유지

Service / EndpointSlice
→ 생성된 Pod 중 트래픽을 전달할 endpoint 관리
```

이번 실험에서는 RollingUpdate가 기존 정상 Pod를 유지하고, Readiness가 비정상 Pod를 Service 트래픽에서 제외하면서 잘못된 새 Pod가 서비스에 영향을 주는 것을 방지하는 모습을 확인할 수 있었음.

### 6. Readiness 복구 및 원리 정리

(local) k8s/deployment.yaml 복구:
```yaml
readinessProbe:
  httpGet:
    port: 8080
    path: /health
```

(local) 수정된 k8s/deployment.yaml VM으로 전송
```sh
scp k8s/deployment.yaml rakji@192.168.105.6:~/
```

(vm) 정상적으로 전송되었는지 내용 확인:
```sh
cat ~/deployment.yaml
```

(vm) apply 직후 변화 과정을 실시간으로 볼 수 있도록 준비:
```sh
sudo k3s kubectl get pod -w
```
- `-w`: 
  - `--watch`의 약자.
  - 계속 실행되면서 Pod 상태가 변할 때마다 출력.

(vm @새로운 터미널) 수정된 deployment.yaml 적용:
```sh
sudo k3s kubectl apply -f ~/deployment.yaml
```

(vm) 적용 확인:
```sh
sudo k3s kubectl get pod
```

(vm) EndpointSlice 상태 확인:
```sh
sudo k3s kubectl describe endpointslice
```

(vm) Pod 상태 확인:
```sh
sudo k3s kubectl get pod
```

(vm) Service 요청 확인:
```sh
curl http://<CLUSTER_IP>:80
```

(vm) 정상 응답일 경우 응답:
```sh
hello from sre-lab
```

