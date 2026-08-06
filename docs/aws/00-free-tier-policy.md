# AWS 무료 정책 — 확인된 사실 정리

2026년 8월 기준. **AWS 공식 문서**에서 확인한 내용만 담았습니다.
출처는 문서 맨 아래에 있습니다.

> 인터넷에 도는 "AWS 750시간 무료" 글은 **2025년 7월 15일 이전 계정** 기준이라
> 지금 새로 가입하는 사람에게는 해당되지 않습니다. 이 문서가 지금 기준입니다.

---

## 1. 2025년 7월 15일부터 완전히 다른 제도입니다

| | 2025-07-15 **이전** 가입 | **이후** 가입 (지금) |
|---|---|---|
| 방식 | 서비스별 무료 사용량 | **크레딧** |
| EC2 | t2/t3.micro **750시간/월 무료** | **무료 시간 없음** |
| 기간 | 12개월 | **6개월** |
| 받는 것 | 무료 사용량 | **$100 크레딧** (+활동 시 추가) |

**핵심: 지금 가입하면 EC2 무료 시간이 아예 없습니다.**
모든 EC2 사용은 크레딧에서 차감됩니다. "무료 티어"라는 이름이지만
실제로는 **기간 한정 체험 크레딧**입니다.

---

## 2. 크레딧

- 가입 시 **$100**
- 콘솔의 온보딩 활동을 완료하면 **추가 적립** (총 최대 $200)
- 크레딧 자체의 유효기간은 **계정 개설일로부터 12개월**
  (단, 아래 무료 플랜은 6개월에 끝나므로 실질 한도는 6개월)

---

## 3. Free plan vs Paid plan

가입 마지막에 둘 중 하나를 고릅니다. **이 선택이 중요합니다.**

|  | **Free plan** | Paid plan |
|---|---|---|
| 크레딧 소진 후 | **계정 만료. 청구 없음** | **바로 과금 시작** |
| 기간 | 6개월 또는 크레딧 소진 (먼저 오는 쪽) | 제한 없음 |
| 쓸 수 있는 것 | Always Free 상품만 | Always Free + 단기 체험판 |
| 제외되는 것 | Savings Plans, 예약 인스턴스,<br>일부 Marketplace 상품 등<br>**크레딧을 한 번에 소진시킬 수 있는 것들** | 전부 사용 가능 |
| 다른 프로모션 크레딧 | **받을 수 없음** | 가능 |

**처음이라면 Free plan을 고르세요.** 실수로 큰 요금이 나올 일이 없습니다.

### ⚠️ Free plan이 저절로 Paid plan으로 바뀌는 경우

아래 중 하나라도 하면 **자동으로 유료 플랜이 됩니다.** 그때부터는 실제 청구가 발생합니다.

- AWS Organizations 가입
- AWS Control Tower 랜딩 존 설정
- AWS 파트너 네트워크(APN) 가입
- Professional Services 계약 체결
- Enterprise Agreement 체결
- AWS Skill Builder 팀 구독 구매
- 계정을 HIPAA 또는 SEC 규정 준수 대상으로 지정

마인크래프트 서버만 돌린다면 건드릴 일이 없는 항목들이지만,
모르고 누르지 않도록 알아두세요.

---

## 4. EC2 인스턴스 유형이 6개로 제한됩니다

2025년 7월 15일 이후 가입 계정이 쓸 수 있는 유형:

| 유형 | vCPU / RAM | 아키텍처 | 선릿밸리 |
|---|---|---|---|
| t3.micro | 2 / 1 GB | x86 | ❌ |
| t4g.micro | 2 / 1 GB | ARM | ❌ |
| t3.small | 2 / 2 GB | x86 | ❌ |
| t4g.small | 2 / 2 GB | ARM | ❌ |
| c7i-flex.large | 2 / 4 GB | x86 | ❌ |
| **m7i-flex.large** | **2 / 8 GB** | **x86** | **✅ 유일** |

`m7g.large`, `m6g.large`, `m7i.large` 같은 유형은 **목록에 아예 없습니다.**

### 여기서 사람들이 막힙니다

인스턴스 유형 목록은 **AMI 아키텍처로 걸러집니다.**
Ubuntu 이미지를 **Arm으로 고르면** 위 표에서 ARM인 것만 남아
**`t4g.micro`(1GB)와 `t4g.small`(2GB) 둘뿐**이 됩니다.

→ **반드시 x86 이미지를 고르세요.** 그래야 `m7i-flex.large`가 보입니다.

### m7i-flex는 t 계열보다 마크에 적합합니다

`t` 계열은 CPU 크레딧을 쌓았다 쓰는 방식이라, 오래 켜두면 성능이 제한됩니다.
`m7i-flex`는 그 방식이 아니고, AWS가 **"24시간 평균으로 95%의 시간 동안 전체 CPU
성능, 나머지 5%도 최소 40%"** 를 보장합니다. 마인크래프트처럼 꾸준히 도는
워크로드에 훨씬 잘 맞습니다.

---

## 5. ⚠️ 6개월 뒤 계정이 닫히고 데이터가 삭제됩니다

이게 가장 중요한 함정입니다.

```
  가입 ──── 6개월 ────▶ Free plan 만료 (또는 크레딧 소진 시 그 시점)
                          │
                          ├─ 90일 안에 Paid plan 전환 → 데이터 복구 가능
                          │
                          └─ 90일 경과 → 계정 영구 폐쇄, 모든 리소스 삭제
```

**월드가 통째로 사라집니다.**

대비:
- 저장소의 백업 스크립트가 매일 자동 백업을 돌립니다
- 그것과 **별개로 본인 PC에도 주기적으로 내려받으세요**

```bash
scp -i 키파일 ubuntu@서버IP:/opt/minecraft/backups/world-*.tar.gz ./
```

---

## 6. 그래서 실제 비용은

EC2는 **초 단위 과금**이고 무료 시간이 없으므로, **켜둔 시간만큼** 크레딧이 나갑니다.

`m7i-flex.large` $0.0958/시간 (us-east-1) 기준:

| 운영 방식 | 월 합계 | $100 크레딧으로 |
|---|---|---|
| 24시간 가동 | 약 $82 | **1.2개월** |
| 하루 6시간 | 약 $22 | 4.5개월 |
| **하루 4시간** | **약 $16** | **6개월 (기간 다 채움)** |

> 서울 리전은 10~15% 더 비쌉니다. EBS 50GB($4/월)와 IP 비용 포함한 값입니다.

**결론: [유휴 자동 종료](02-auto-onoff.md)가 없으면 크레딧이 한 달 만에 사라집니다.**
반드시 설치하세요.

---

## 이 문서의 한계

- AWS 공식 문서를 **검색을 통해** 확인했습니다. 이 작업 환경에서 `aws.amazon.com`
  직접 접근이 차단돼 있어 원문 페이지를 통째로 읽지는 못했습니다
- `m7i-flex.large`의 2 vCPU / 8 GiB는 AWS 공식 "large ~ 16xlarge, 최대 64 vCPU /
  256 GiB" 기재와 M 계열의 1:4 비율, 그리고 복수의 가격 정보 사이트로 교차 확인한
  값입니다
- 가격은 변동될 수 있으니 실제 금액은 콘솔에서 확인하세요
- **가입 후 콘솔 홈이나 결제 대시보드에서 크레딧 잔액과 만료일을 직접 확인**하시길
  권합니다. 정책이 또 바뀔 수 있습니다

## 출처

- [Track your Free Tier usage for Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html) — 인스턴스 유형 6개 목록
- [Choosing a plan (AWS Billing)](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html) — Free/Paid plan 차이, 자동 업그레이드 조건
- [AWS Free Tier Terms](https://aws.amazon.com/free/terms/) — 6개월 기간, 90일 유예, 계정 폐쇄
- [Explore AWS services with AWS Free Tier](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier.html)
- [AWS Free Tier update: up to $200 in credits](https://aws.amazon.com/blogs/aws/aws-free-tier-update-new-customers-can-get-started-and-explore-aws-with-up-to-200-in-credits/)
- [Amazon EC2 M7i and M7i-flex instances](https://aws.amazon.com/ec2/instance-types/m7i/)
