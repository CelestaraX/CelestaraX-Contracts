# Web3ite Contract

이 컨트랙트는 **"온체인(블록체인) 상에서 HTML 페이지를 생성하고, 수정하고, 수수료(Fees)를 관리하는 DApp"** 을 구현하기 위한 예시입니다.

사용자는 페이지 소유권(Ownership)을 아래 세 가지 유형 중 하나로 설정할 수 있습니다.

- **Single (개인 소유)**
- **MultiSig (멀티시그 소유)**
- **Permissionless (누구나 수정 가능)**

각 페이지마다 **수정 요청 시 지불해야 하는 수수료(Update Fee)** 가 있으며, 페이지 유형에 따라 수수료가 어떻게 보관되고 출금되는지가 달라집니다.

## 주요 기능 및 동작 원리

### 1. 페이지 생성 (createPage)

#### 함수 시그니처:

```solidity
function createPage(
    string calldata _initialHtml,
    OwnershipType _ownershipType,
    address[] calldata _multiSigOwners,
    uint256 _multiSigThreshold,
    uint256 _updateFee
) external returns (uint256 pageId);
```

- 새로운 HTML 페이지를 온체인에 등록합니다.
- `_initialHtml`: 페이지 초기 HTML
- `_ownershipType`: 소유권 유형 (Single/MultiSig/Permissionless)
- 멀티시그인 경우, `_multiSigOwners` 및 `_multiSigThreshold`를 통해 오너 목록과 승인 임계치(Threshold)를 설정합니다.
- `_updateFee`: 페이지 수정 요청 시 납부해야 할 금액 (Wei 단위)
- 반환값 `pageId`: 페이지 식별용 ID (1부터 증가)

### 2. 수정 요청 (requestUpdate)

#### 함수 시그니처:

```solidity
function requestUpdate(uint256 _pageId, string calldata _newHtml)
    external
    payable;
```

- `_pageId`에 해당하는 페이지를 수정하고자 할 때 호출합니다.
- `msg.value`가 페이지별 `Update Fee` 이상이어야 하며, 그렇지 않으면 트랜잭션이 실패합니다.
- 페이지 유형에 따라 동작이 달라집니다.
  - **Permissionless**: 수정 요청 즉시 반영 (승인 절차 없음). 해당 페이지에 대한 수정 수수료는 컨트랙트 내 `pageBalances[pageId]`에 쌓입니다.
  - **Single / MultiSig**: 수정 요청이 "대기 상태(Queue)"로 쌓이고, 이후 승인 절차(`approveRequest`)를 통해 최종 반영됩니다.

### 3. 승인 (approveRequest)

#### 함수 시그니처:

```solidity
function approveRequest(uint256 _pageId, uint256 _requestId) external;
```

- `Permissionless`가 아닌 페이지(`Single/MultiSig`)에서, 대기 중인 수정 요청에 대해 오너(혹은 멀티시그 오너)가 승인합니다.
  - **Single**: 오너가 승인하면 즉시 실행
  - **MultiSig**: 오너 여러 명 중 `threshold`만큼 승인하면 실행
- 실행되면 `UpdateExecuted` 이벤트가 발생하고, 페이지 HTML이 `_newHtml`로 업데이트됩니다.

### 4. 수수료 출금 (withdrawPageFees)

#### 함수 시그니처:

```solidity
function withdrawPageFees(uint256 _pageId) external;
```

- **Single 페이지**: 오너(`singleOwner`)가 호출하면, 해당 `pageId`에 쌓인 수수료 전액을 출금합니다.
- **MultiSig 페이지**: 오너 목록에 포함된 계정이 호출하면, 모든 멀티시그 오너에게 균등하게 수수료를 분배합니다. (나머지는 컨트랙트에 남음)
- **Permissionless 페이지**: 출금 불가능(`revert`), 대신 `distributePageTreasury` 등을 통해 수정 요청에 참여한 사람들에게 랜덤 분배 가능.

### 5. 소유권 변경 (changeOwnership)

#### 함수 시그니처:

```solidity
function changeOwnership(
    uint256 _pageId,
    OwnershipType _newOwnershipType,
    address[] calldata _newMultiSigOwners,
    uint256 _newMultiSigThreshold
) external;
```

- **Single 페이지**에서만 소유권 유형을 변경할 수 있습니다. (`MultiSig`, `Permissionless` 상태에서는 변경 불가)
- 소유권 타입이 바뀌면, 기존 오너 정보는 초기화되고 새로운 값으로 교체됩니다.
  - 예: `Single → MultiSig`, `Single → Permissionless` 가능

### 6. (선택 기능) Permissionless 페이지 트레저리 분배 (distributePageTreasury)

#### 함수 시그니처:

```solidity
function distributePageTreasury(uint256 _pageId) external;
```

- `Permissionless` 페이지에 쌓인 수수료(`pageBalances[_pageId]`)를, 이전에 수정 요청을 보냈던 참가자들 중 랜덤으로 1명에게 전액 지급하는 예시 로직입니다.
- 블록 해시 기반의 단순 난수이므로, 실제 메인넷 서비스에는 보안적 한계가 있습니다. (`Chainlink VRF` 등 대안 권장)

---

## 컨트랙트 구조

### `IWeb3ite.sol`
- 인터페이스(Interface)로, 주요 함수/이벤트 시그니처를 정의합니다.

### `Web3ite.sol`
- 인터페이스를 구현한 실제 컨트랙트.
- `Page` 구조체로 각 페이지 상태를 보관 (`currentHtml`, `ownershipType`, `updateFee`, 멀티시그 정보 등).
- `requestUpdate` → `approveRequest` → `_executeUpdate` 흐름으로 수정 반영.
- `withdrawPageFees`, `changeOwnership` 등으로 수수료 출금, 소유권 변경 등 수행.

---

## 간단한 사용 예시

### 1. 페이지 생성 (Single 타입 예시)

```solidity
uint256 pageId = web3ite.createPage(
    "Hello On-Chain HTML!",
    IWeb3ite.OwnershipType.Single,
    new address[](0),  // MultiSig 오너 없음
    0,                 // MultiSig threshold 없음
    1e15              // 예: 0.001 ETH as update fee
);
```

### 2. 수정 요청

```solidity
// fee(0.001 ETH) 이상을 보내며 호출
web3ite.requestUpdate{value: 1e15}(pageId, "<h1>Updated HTML</h1>");
```

### 3. 승인 (Single)

```solidity
// singleOwner가 승인하면 즉시 반영
web3ite.approveRequest(pageId, 0);
```

### 4. 수수료 출금

```solidity
// singleOwner가 수수료 전액 출금
web3ite.withdrawPageFees(pageId);
```


## 추후 개발 계획 / 개선 사항
### HTML 전체로 저장하는 문제

현재 demo 버전은 HTML 전체를 통째로 저장하지만, 추후 HTML을 요소별로 분할하여 저장하고 관리할 수 있는 기능을 추가할 예정입니다. 이를 통해 특정 부분은 Permissionless하게 수정 가능하도록 하고, 중요한 부분은 Page Owner의 승인을 받아야 수정할 수 있도록 컨트랙트를 확장할 계획입니다. 각 요소에 대해 edit permission을 부여하는 방식으로 유연성을 제공할 수 있습니다.

### Page 소유권 (최우선 순위는 아니지만)

MillionDollar Page 같은 경우처럼 특정 페이지가 수익을 창출할 수 있기 때문에, Page Owner가 존재하면 지속적인 수입원이 될 수 있습니다. 이를 고려하여, Page 소유권을 NFT로 토큰화하고, 소유권을 양도할 수 있도록 구현할 계획입니다.

NFT를 발행하여 소유권을 표현하고, 이를 마켓플레이스에서 거래 가능하도록 설정합니다.

소유권을 보유한 사용자에게 페이지 수정 권한 및 수수료 수익 분배를 제공하는 구조를 도입합니다.

### Domain 부분?

사용자가 직접 DA에 올라가 있는 페이지를 띄울 수 있도록 하기 위해, 다음과 같은 방안을 고려 중입니다:

ENS / DNS 연동: ENS 또는 IPFS 기반 도메인 서비스를 통해 블록체인 상의 데이터를 브라우저에서 쉽게 조회할 수 있도록 지원합니다.

DA Layer 통합: DA Layer에서 직접 블록체인에 저장된 데이터를 제공하는 API를 설계하여, 페이지를 바로 로드할 수 있도록 합니다.

### 멀티시그 부분

현재는 단순한 multisig 방식을 구현했지만, Gnosis Safe 같은 검증된 멀티시그 솔루션을 활용하여 다음과 같은 기능을 추가할 계획입니다:

Gnosis Safe 연동: 다수의 오너가 트랜잭션을 승인할 수 있도록 Safe 모듈을 추가.

멀티시그 Threshold 조정 가능: 각 페이지별로 필요에 따라 threshold를 동적으로 변경할 수 있는 기능 제공.

### Permissionless 페이지의 난수 안전성 개선

현재 distributePageTreasury 함수는 블록 해시 기반의 pseudo-random 방식을 사용하고 있지만, 이는 채굴자/검증인이 결과를 유리하게 조작할 수 있는 위험이 있습니다. 이를 해결하기 위해 다음과 같은 대안을 도입할 예정입니다:

Chainlink VRF 사용: 안전한 난수를 생성하기 위해 Chainlink VRF(Verifiable Random Function)를 활용.

Commit-Reveal 방식 적용: 사용자들이 사전에 난수값을 커밋하고 이후 공개하는 방식으로, 조작 가능성을 차단.

Threshold Signature 기반 난수 생성: 여러 노드가 서명하여 난수를 생성하는 방식으로 보안을 강화.

### 누구나에 대한 페이지 로직?

현재 Permissionless 페이지는 누구나 HTML을 수정할 수 있지만, 무분별한 수정으로 인해 문제가 발생할 가능성이 큽니다. 이를 해결하기 위해 다음과 같은 접근 방식을 고려하고 있습니다:

스테이킹 기반 수정 권한: 수정 요청을 할 때 일정량의 토큰을 스테이킹하도록 요구하고, 수정이 유효하면 반환, 악용하면 소각하는 방식.

투표 기반 승인: Permissionless 페이지라도 커뮤니티의 투표를 통해 수정이 최종 반영되도록 하는 거버넌스 시스템 추가.

기여도 기반 수정 제한: 기여도가 높은 사용자가 우선적으로 수정할 수 있도록, 과거 수정 기록 및 기여도를 반영한 가중치 시스템 도입.

AI 및 콘텐츠 필터링: 자동으로 부적절한 내용이 등록되지 않도록 AI 기반 필터링 및 자동 승인 프로세스 추가.