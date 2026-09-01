# Day 02

```txt
VM / k3s 환경을 직접 구성
        ↓
로컬 이미지를 containerd에 직접 넣음
        ↓
Deployment → ReplicaSet → Pod를 실제로 확인
        ↓
Pod를 죽이고 reconciliation을 직접 관찰
```

### 1. Ubuntu VM 준비

UTM에서 사용할 Ubuntu Server ARM64 이미지 다운로드:
```txt
Ubuntu Server
Architecture: ARM64 (aarch64)
```

UTM 실행 후 VM 생성:
```txt
Create a New Virtual Machine
→ Virtualize
→ Linux
```

```txt
CPU:    2 Core
Memory: 4 GB
Disk:   30 GB

VM Name: sre-lab
```

Ubuntu 설치 시 설정할 것:
```txt
Username: <원하는 이름>
Hostname: sre-lab

[X] Install OpenSSH server
```
- 나머지는 특별히 건드릴 것이 없음

ip 주소 확인:
```sh
ip addr
```
- 출력에서 네트워크 인터페이스의 inet 값을 찾으면 됨.

출력 예시:
```txt
inet 192.168.64.8/24
```

Mac → Ubuntu VM SSH 연결 확인:
```sh
ssh rakji@192.168.252.8
```

### 2. k3s 설치

> 1. 시스템 업데이트
> 2. k3s 설치 및 확인(설치, 클러스터)
> 3. k3s 클러스터 정상 여부 확인

시스템 업데이트:
```sh
sudo apt update
```

k3s 설치:
- https://k3s.io/
```sh
curl -sfL https://get.k3s.io | sh - 
```
- k3s 공식 설치 스크립트를 받아 실행하는 방식

k3s 설치 성공 여부 확인:
```sh
sudo systemctl status k3s
```

k3s 클러스터가 정상인지 확인:
```sh
sudo k3s kubectl get nodes
```
- STATUS가 `Ready`로 나와야 함.
- k3s는 자체 kubectl을 포함하고 있으므로, `sudo k3s kubectl` 형태로 바로 사용할 수 있음.


### 3. K8s Deployment 작성

> 1. k8s 디렉터리 준비
> 2. k8s/deployment.yaml 생성

k8s 디렉터리 준비:
```sh
mkdir -p k8s
```

k8s/deployment.yaml 생성:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sre-lab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sre-lab
  template:
    metadata:
      labels:
        app: sre-lab
    spec:
      containers:
      - name: sre-lab
        image: sre-lab:0.1
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
```
- `imagePullPolicy`: k8s가 컨테이너 이미지를 언제 외부 레지스트리에서 pull할지 정하는 정책.
  - 사용 가능한 값으로 `Always`, `IfNotPresent`, `Never` 가 있음:
    - `Always`: 항상 pull 시도.
    - `IfNotPresent`: 노드에 해당 이미지가 이미 있으면 그걸 사용하고, 없을 때만 pull 시도.
    - `Never`: 절대 pull하지 않고 로컬 이미지만 사용.
- `ports[].containerPort`: 이 컨테이너의 애플리케이션이 8080 포트를 사용한다고 명시하는 정보.
  - ❗이 설정 자체가 8080 포트를 열어주는 것은 아님.
  - 실제로 8080에서 Listen하는 건 작성한 Go 애플리케이션
  - *환경변수를 공유해서 deployment.yaml과 애플리케이션 코드 모두 사용할 수 있도록 할 수 있지 않을까?*
    → **k8s가 컨테이너 환경변수를 주입하고 Go 앱이 그 값을 읽게 하는 방법이 있음**

### 4. Docker 이미지를 k3s에 전달

> 1. (local) 이미지를 아카이브 파일로 생성 및 확인
> 2. (local) VM으로 이미지 파일 복사
> 3. (vm) 이미지를 k3s가 사용하는 containerd 이미지 저장소에 import
> 4. (vm) import 된 이미지 확인

로컬(Mac)에 있는 `sre-lab:0.1` 이미지를 파일로 생성
```sh
docker save sre-lab:0.1 -o sre-lab.tar
```
- `docker save <이미지 이름:태그> -o <출력 파일명>`: Docker 이미지를 파일 형태로 저장
  - 컨테이너를 저장하는 게 아니라 ==이미지 자체를 저장==

생성 확인:
```sh
ls -lh sre-lab.tar
```

`.tar`로 만든 이유는 로컬(mac)의 Docker에 있는 이미지를 Ubuntu VM으로 복사한 뒤, k3s containerd에 넣기 위함.

Mac에서 VM으로 파일 복사:
```sh
scp sre-lab.tar rakji@192.168.252.8:~/
```

VM에서 해당 파일 확인:
```sh
ls -lh ~/sre-lab.tar
```

이미지를 k3s의 containerd에 import:
```sh
sudo k3s ctr images import ~/sre-lab.tar
```
- `k3s ctr`: k3s에 포함된 containerd CLI 사용
  - `ctr`: containerd의 저수준 CLI
- `images import`: 이미지 아카이브(tar)를 containerd에 가져오기

이미지가 들어왔는지 확인:
```sh
sudo k3s ctr images list | grep sre-lab
```
- sre-lab:0.1이 보이면 성공

### 5. Deployment 적용 및 확인

(local) k8s/deployment.yaml 파일을 vm으로 복사:
```sh
scp k8s/deployment.yaml rakji@192.168.252.8:~/
```

(vm) 복사 결과 확인:
```sh
ls -l ~/deployment.yaml
```

Deployment 생성:
```sh
sudo k3s kubectl apply -f ~/deployment.yaml
```

적용 후 확인:
```sh
sudo k3s kubectl get deployment

sudo k3s kubectl get rs

sudo k3s kubectl get pod
```
- 이걸 확인하면 Deployment → ReplicaSet → Pod 관계가 보임.
  - Deployment: 배포 전략과 원하는 상태 관리
  - ReplicaSet: Pod 개수 유지
  - Pod: 실제로 실행되는 컨테이너

### 6. Reconciliation 실험

Pod 이름 확인:
```sh
sudo k3s kubectl get pods
```

Pod 2개 중 아무거나 하나 골라서 삭제:
```sh
sudo k3s kubectl delete pod <pod_name>
```

다시 확인:
```sh
sudo k3s kubectl get pod
```
- Reconciliation은 순식간에 일어남

Kubernetes의 중요한 감각:
- "특정 Pod를 지킨다"가 아니라, "원하는 상태를 계속 맞춘다"

위 Reconciliation 과정의 흔적을 이벤트에서 확인하려면:
```sh
sudo k3s kubectl get events --sort-by=.lastTimestamp
```

---

Kubernetes를 잘 살펴보자.

우리가 명령한 건 사실:
```txt
"Pod가 죽으면 새로 만들어"
```
가 아니었음.

처음에 단지:
```yaml
replicas: 2
```
라고 ==원하는 상태(desired state)==를 선언했을 뿐임.

그런데 Pod 삭제 후 실제 상태가:
```txt
Desired: 2
Actual: 1
```
이 되어버리니까 **ReplicaSet Controller**가 다시:
```txt
Desired: 2
Actual: 2
```
로 맞춘 것임.
