// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IWeb3ite
 * @notice 페이지 생성/수정 기능을 제공하는 DApp 컨트랙트의 인터페이스
 */
interface IWeb3ite {
    // 소유권 타입
    enum OwnershipType {
        Single,         // 0 - 개인
        MultiSig,       // 1 - 멀티시그
        Permissionless  // 2 - 누구나 수정 가능
    }

    // 이벤트들
    event PageCreated(
        uint256 indexed pageId,
        address indexed creator,
        OwnershipType ownershipType,
        uint256 updateFee
    );
    event UpdateRequested(
        uint256 indexed pageId,
        uint256 indexed requestId,
        address indexed requester
    );
    event Approved(
        uint256 indexed pageId,
        uint256 indexed requestId,
        address indexed approver
    );
    event UpdateExecuted(
        uint256 indexed pageId,
        uint256 indexed requestId,
        string newHtml
    );
    event PageFeesWithdrawn(
        uint256 indexed pageId,
        address indexed receiver,
        uint256 amount
    );
    event OwnershipChanged(
        uint256 indexed pageId,
        OwnershipType oldType,
        OwnershipType newType
    );
    // 새로 추가: 페이지 트레저리 분배 이벤트
    event PageTreasuryDistributed(
        uint256 indexed pageId,
        address indexed winner,
        uint256 amount
    );

    /**
     * @notice 새로운 HTML 페이지를 생성한다.
     * @param _initialHtml 페이지의 초기 HTML
     * @param _ownershipType 소유권 타입 (0=Single,1=MultiSig,2=Permissionless)
     * @param _multiSigOwners 멀티시그 소유자들 (Single/Permissionless일 경우 빈 배열)
     * @param _multiSigThreshold 멀티시그 threshold
     * @param _updateFee 이 페이지를 수정할 때마다 지불해야 하는 개별 수수료
     * @return pageId 생성된 페이지의 식별자
     */
    function createPage(
        string calldata _initialHtml,
        OwnershipType _ownershipType,
        address[] calldata _multiSigOwners,
        uint256 _multiSigThreshold,
        uint256 _updateFee
    ) external returns (uint256 pageId);

    /**
     * @notice 페이지 수정 요청(또는 Permissionless 시 즉시 반영)을 등록한다.
     * @param _pageId 수정하고자 하는 페이지 ID
     * @param _newHtml 제안하는 새 HTML
     */
    function requestUpdate(uint256 _pageId, string calldata _newHtml) external payable;

    /**
     * @notice Single/MultiSig 페이지의 수정 요청을 승인한다.
     *         threshold 도달 시 실제 HTML 업데이트 실행
     * @param _pageId 페이지 ID
     * @param _requestId 수정 요청 ID
     */
    function approveRequest(uint256 _pageId, uint256 _requestId) external;

    /**
     * @notice 페이지별로 누적된 수수료를 출금한다.
     *         Single 오너 => 본인만
     *         MultiSig => 오너 중 한 명(간단 구현)
     *         Permissionless => 없음(예시)
     * @param _pageId 페이지 ID
     */
    function withdrawPageFees(uint256 _pageId) external;

    function changeOwnership(
        uint256 _pageId,
        OwnershipType _newOwnershipType,
        address[] calldata _newMultiSigOwners,
        uint256 _newMultiSigThreshold
    ) external;

    // 새로 추가: Permissionless page의 treasury를 분배
    function distributePageTreasury(uint256 _pageId) external;

    // 조회 함수들
    function getCurrentHtml(uint256 _pageId) external view returns (string memory);
    function getMultiSigOwners(uint256 _pageId) external view returns (address[] memory);
    function getUpdateRequest(
        uint256 _pageId, 
        uint256 _requestId
    ) external view returns (string memory newHtml, bool executed, uint256 approvalCount);

    // 페이지별 누적된 수수료
    function pageBalances(uint256 _pageId) external view returns (uint256);
    function pageCount() external view returns (uint256);
}
