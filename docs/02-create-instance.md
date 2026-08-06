# 2단계 — 인스턴스(서버 컴퓨터) 만들기

여기서 실제 서버가 될 가상 컴퓨터를 만듭니다.
**"Out of host capacity" 벽**이 있어서 이 단계가 가장 오래 걸릴 수 있습니다.

---

## 생성 절차

OCI 콘솔(https://cloud.oracle.com) 로그인 후:

**좌측 햄버거 메뉴 → 컴퓨트(Compute) → 인스턴스(Instances) → 인스턴스 생성**

### ① 이름과 구획

- 이름: `minecraft-sunlit` (아무거나)
- 구획(Compartment): 기본값 그대로

### ② 이미지 및 shape — **가장 중요한 부분**

**"편집(Edit)"** 을 눌러야 바꿀 수 있습니다.

**이미지:**
- **Canonical Ubuntu 22.04** 를 선택하세요.
- 스크립트가 우분투 전용입니다. Oracle Linux를 고르면 동작하지 않습니다.

**Shape:**
1. **shape 변경(Change shape)** 클릭
2. 인스턴스 유형: **가상 머신**
3. shape 계열: **Ampere** 탭 선택
4. **VM.Standard.A1.Flex** 체크
5. OCPU 수: **2**  /  메모리(GB): **12**
6. **"항상 무료 적격" 초록 라벨**이 보이는지 확인 → 선택

> ⚠️ AMD 탭의 `VM.Standard.E2.1.Micro`도 무료지만 RAM이 1GB라 모드팩 서버는
> 절대 돌아가지 않습니다. 반드시 **Ampere ARM**이어야 합니다.

### ③ 부트 볼륨

- **부트 볼륨 사용자 정의** 체크
- 크기: **100 GB** (기본 50GB도 되지만, 백업과 월드가 쌓이므로 넉넉하게)
- 무료 블록 스토리지 총량은 **200GB**입니다. 이 안에서만 쓰세요.

### ④ 네트워킹

- **새 가상 클라우드 네트워크 생성** 선택 (VCN이 없다면 자동으로 만들어집니다)
- 서브넷: **공용 서브넷(Public Subnet)**
- **"공용 IPv4 주소 지정" 체크** ← 안 하면 인터넷에서 접속이 불가능합니다

### ⑤ SSH 키 — 잃어버리면 서버에 못 들어갑니다

- **키 쌍 자동 생성(Generate a key pair for me)** 선택
- **"개인 키 저장(Save private key)"** 을 눌러 `.key` 파일을 다운로드
- 이 파일을 안전한 곳에 보관하세요. 다시 받을 수 없고, 잃어버리면 인스턴스를
  새로 만들어야 합니다.

### ⑥ 생성

**생성(Create)** 클릭.

---

## "Out of host capacity" 가 뜬다면

무료 ARM은 수요가 많아서 자리가 없다는 에러가 자주 뜹니다. **계정 문제가 아닙니다.**

에러 메시지 예시:
```
Out of host capacity.
```
```
Out of capacity for shape VM.Standard.A1.Flex in availability domain ...
```

### 대처법 (효과 순서대로)

**1. 가용성 도메인(AD)을 바꿔가며 시도**
도쿄처럼 AD가 여러 개인 리전이라면, 생성 화면에서 AD-1, AD-2, AD-3을 각각
시도해보세요. AD 하나가 꽉 찼어도 다른 AD에는 자리가 있는 경우가 많습니다.
AD가 1개뿐인 리전이면 이 방법은 건너뛰고 아래로 넘어가세요.

**2. 사양을 낮춰서 시도**
2 OCPU / 12GB가 안 되면 **1 OCPU / 6GB**로 먼저 만든 뒤, 나중에 자리가 나면
인스턴스를 정지하고 사양을 올릴 수 있습니다.
다만 6GB로는 선릿밸리가 매우 빠듯하니 어디까지나 임시 방편입니다.

**3. 시간대를 바꿔서 재시도**
한국 시간 **새벽 3~7시**에 성공률이 눈에 띄게 높습니다.
누군가 인스턴스를 지우면 그 자리가 풀리는 구조라, 꾸준히 재시도하면 대체로 됩니다.

**4. Pay As You Go(종량제)로 전환** ← 가장 확실
콘솔 우측 상단 → **업그레이드(Upgrade)**.
전환해도 **Always Free 리소스는 계속 무료**이고, 무료 범위만 쓰면 청구는 0원입니다.
대신 용량 배정에서 우선순위가 생겨서 "capacity" 에러가 거의 사라집니다.

> 종량제 전환 후에는 실수로 유료 리소스를 만들면 실제로 청구됩니다.
> 1단계에서 안내한 **예산 알림**을 꼭 걸어두세요.

---

## 공인 IP를 고정하기 (권장)

기본으로 붙는 공인 IP는 **임시(Ephemeral)** 라서, 인스턴스를 정지했다 켜면
**주소가 바뀝니다.** 친구들한테 매번 새 주소를 알려주게 됩니다.

**인스턴스 상세 → 연결된 VNIC → IPv4 주소 → 우측 ⋮ → 편집
→ 공용 IP 유형을 "예약된 공용 IP"로 변경**

무료 티어에 예약 IP가 포함되어 있어 추가 비용은 없습니다.

### 더 편하게: 도메인 붙이기 (선택)

숫자 IP 대신 `내서버.duckdns.org` 같은 주소를 쓰고 싶다면
[DuckDNS](https://www.duckdns.org) 에서 무료로 만들 수 있습니다. IP가 바뀌어도
자동으로 따라가서 편합니다.

---

## SSH로 접속하기

인스턴스 상세 화면에서 **공용 IP 주소**를 복사합니다.

### 윈도우 (PowerShell)

```powershell
# 다운로드한 키 파일이 있는 폴더로 이동
cd $HOME\Downloads

# 키 파일 권한 정리 (이걸 안 하면 접속이 거부됩니다)
icacls .\ssh-key-XXXX.key /inheritance:r
icacls .\ssh-key-XXXX.key /grant:r "$($env:USERNAME):(R)"

# 접속
ssh -i .\ssh-key-XXXX.key ubuntu@공인IP
```

### 맥 / 리눅스

```bash
chmod 600 ~/Downloads/ssh-key-XXXX.key
ssh -i ~/Downloads/ssh-key-XXXX.key ubuntu@공인IP
```

`ubuntu@minecraft-sunlit:~$` 같은 프롬프트가 뜨면 성공입니다.

> 사용자 이름은 우분투 이미지면 `ubuntu`, Oracle Linux면 `opc` 입니다.
> `root`로는 접속되지 않습니다.

---

## 다음

→ [3단계: 네트워크 열기](03-network.md)
