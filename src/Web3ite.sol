// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IWeb3ite.sol";

/**
 * @title Web3ite
 * @notice
 *  - Single/MultiSig 페이지는 기존처럼 fee 출금 가능, 소유권 변경은 Single만 가능
 *  - Permissionless 페이지:
 *      1) requestUpdate 시 즉시 HTML 반영
 *      2) 납부 fee는 pageBalances[pageId]에 쌓임 (별도 treasury)
 *      3) withdrawPageFees 불가 (revert)
 *      4) "distributePageTreasury(pageId)"로
 *          지금까지 수정 요청했던 사람들(중복 방지)에 랜덤 1명을 뽑아 전액 지급
 */
contract Web3ite is IWeb3ite {

    // 수정 요청 구조체
    struct UpdateRequest {
        string newHtml;
        bool executed;
        uint256 approvalCount;          
        mapping(address => bool) voted; // MultiSig 승인 여부
    }

    // 페이지 구조체
    struct Page {
        string currentHtml;
        OwnershipType ownershipType;

        address singleOwner;        
        address[] multiSigOwners;   
        uint256 multiSigThreshold;  

        uint256 updateRequestCount;
        mapping(uint256 => UpdateRequest) updateRequests;

        uint256 updateFee;          
    }

    // 페이지 식별
    uint256 private _pageCount;
    mapping(uint256 => Page) private _pages;
    // 페이지별 누적 수수료
    mapping(uint256 => uint256) private _pageBalances;

    // -----------------------------
    // Permissionless 참여자 기록
    // -----------------------------
    // pageId => 배열(중복 없이)
    mapping(uint256 => address[]) private _pageParticipants;
    // pageId => (address => bool) : 이미 참여했는지
    mapping(uint256 => mapping(address => bool)) private _hasParticipated;

    // -----------------------------
    // 조회
    // -----------------------------
    function pageCount() external view override returns (uint256) {
        return _pageCount;
    }
    function pageBalances(uint256 _pageId) external view override returns (uint256) {
        return _pageBalances[_pageId];
    }

    // -----------------------------
    // 페이지 생성
    // -----------------------------
    function createPage(
        string calldata _initialHtml,
        OwnershipType _ownershipType,
        address[] calldata _multiSigOwners,
        uint256 _multiSigThreshold,
        uint256 _updateFee
    )
        external
        override
        returns (uint256 pageId)
    {
        pageId = ++_pageCount;

        Page storage newPage = _pages[pageId];
        newPage.currentHtml = _initialHtml;
        newPage.ownershipType = _ownershipType;
        newPage.updateFee = _updateFee;

        if (_ownershipType == OwnershipType.Single) {
            newPage.singleOwner = msg.sender;
        } 
        else if (_ownershipType == OwnershipType.MultiSig) {
            require(_multiSigOwners.length > 0, "No owners for multi-sig");
            require(
                _multiSigThreshold > 0 && _multiSigThreshold <= _multiSigOwners.length,
                "Invalid multiSigThreshold"
            );
            for(uint256 i=0; i < _multiSigOwners.length; i++){
                newPage.multiSigOwners.push(_multiSigOwners[i]);
            }
            newPage.multiSigThreshold = _multiSigThreshold;
        } 
        else if (_ownershipType == OwnershipType.Permissionless) {
            // 누구나 수정 가능
        } 
        else {
            revert("Invalid ownership type");
        }

        emit PageCreated(pageId, msg.sender, _ownershipType, _updateFee);
    }

    // -----------------------------
    // 수정 요청
    // -----------------------------
    function requestUpdate(uint256 _pageId, string calldata _newHtml)
        external
        payable
        override
    {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];

        // fee
        require(msg.value >= page.updateFee, "Insufficient fee");
        _pageBalances[_pageId] += msg.value;

        if (page.ownershipType == OwnershipType.Permissionless) {
            // 즉시 반영
            page.currentHtml = _newHtml;

            // 참여자 기록 (중복 방지)
            if (!_hasParticipated[_pageId][msg.sender]) {
                _hasParticipated[_pageId][msg.sender] = true;
                _pageParticipants[_pageId].push(msg.sender);
            }

            emit UpdateExecuted(_pageId, 0, _newHtml);
        } 
        else {
            // Single / MultiSig
            uint256 requestId = page.updateRequestCount;
            UpdateRequest storage newReq = page.updateRequests[requestId];
            newReq.newHtml = _newHtml;
            newReq.executed = false;

            page.updateRequestCount++;

            emit UpdateRequested(_pageId, requestId, msg.sender);
        }
    }

    // -----------------------------
    // 승인 (Single/MultiSig)
    // -----------------------------
    function approveRequest(uint256 _pageId, uint256 _requestId) external override {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];
        require(
            page.ownershipType != OwnershipType.Permissionless,
            "No approval needed for permissionless"
        );
        require(_requestId < page.updateRequestCount, "Invalid requestId");

        UpdateRequest storage req = page.updateRequests[_requestId];
        require(!req.executed, "Already executed");

        if (page.ownershipType == OwnershipType.Single) {
            require(msg.sender == page.singleOwner, "Not single owner");
            _executeUpdate(page, req, _pageId, _requestId);
        } else {
            // MultiSig
            bool isOwner = false;
            for (uint256 i=0; i < page.multiSigOwners.length; i++){
                if (page.multiSigOwners[i] == msg.sender) {
                    isOwner = true;
                    break;
                }
            }
            require(isOwner, "Not a multi-sig owner");
            require(!req.voted[msg.sender], "Already voted");

            req.voted[msg.sender] = true;
            req.approvalCount++;
            emit Approved(_pageId, _requestId, msg.sender);

            if(req.approvalCount >= page.multiSigThreshold){
                _executeUpdate(page, req, _pageId, _requestId);
            }
        }
    }

    function _executeUpdate(
        Page storage _page,
        UpdateRequest storage _req,
        uint256 _pageId,
        uint256 _requestId
    ) internal {
        _page.currentHtml = _req.newHtml;
        _req.executed = true;

        emit UpdateExecuted(_pageId, _requestId, _req.newHtml);
    }

    // -----------------------------
    // 수수료 출금
    // (MultiSig -> 균등 분배)
    // -----------------------------
    function withdrawPageFees(uint256 _pageId) external override {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];
        uint256 balance = _pageBalances[_pageId];
        require(balance > 0, "No fees to withdraw");

        if (page.ownershipType == OwnershipType.Single) {
            // 전액 -> singleOwner
            require(msg.sender == page.singleOwner, "Not single owner");
            _pageBalances[_pageId] = 0;

            (bool success, ) = msg.sender.call{value: balance}("");
            require(success, "Withdraw failed");

            emit PageFeesWithdrawn(_pageId, msg.sender, balance);

        } 
        else if (page.ownershipType == OwnershipType.MultiSig) {
            // 오너 중 하나가 호출할 수 있음
            bool isOwner = false;
            for(uint256 i=0; i < page.multiSigOwners.length; i++){
                if(page.multiSigOwners[i] == msg.sender){
                    isOwner = true;
                    break;
                }
            }
            require(isOwner, "Not a multi-sig owner");

            // 균등 분배
            _pageBalances[_pageId] = 0;
            uint256 ownersCount = page.multiSigOwners.length;
            uint256 share = balance / ownersCount;
            //uint256 remainder = balance % ownersCount;

            for (uint256 i=0; i < ownersCount; i++) {
                (bool ok, ) = page.multiSigOwners[i].call{value: share}("");
                require(ok, "Transfer to multi-sig owner failed");
            }

            // remainder(나머지)가 생겼다면 어떻게 할지?
            // 여기서는 "그냥 컨트랙트에 남긴다"는 예시.
            // (원하면 revert 하거나, 호출자에게 주거나, 특정 주소로 보내는 등 정책 가능)

            emit PageFeesWithdrawn(_pageId, msg.sender, balance);

        } 
        else if (page.ownershipType == OwnershipType.Permissionless) {
            revert("Cannot withdraw from permissionless page");
        } 
        else {
            revert("Invalid ownership type");
        }
    }

    // -----------------------------
    // 소유권 변경 (Single만)
    // -----------------------------
    function changeOwnership(
        uint256 _pageId,
        OwnershipType _newOwnershipType,
        address[] calldata _newMultiSigOwners,
        uint256 _newMultiSigThreshold
    ) external override {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];
        OwnershipType oldType = page.ownershipType;

        if (oldType == OwnershipType.Single) {
            require(msg.sender == page.singleOwner, "Not single owner");
        } else {
            revert("Ownership cannot be changed for this type");
        }

        // reset
        delete page.singleOwner;
        delete page.multiSigOwners;
        page.multiSigThreshold = 0;

        page.ownershipType = _newOwnershipType;

        if (_newOwnershipType == OwnershipType.Single) {
            page.singleOwner = msg.sender;
        } 
        else if (_newOwnershipType == OwnershipType.MultiSig) {
            require(_newMultiSigOwners.length > 0, "No owners for multi-sig");
            require(
                _newMultiSigThreshold > 0 && _newMultiSigThreshold <= _newMultiSigOwners.length,
                "Invalid threshold"
            );
            for(uint256 i=0; i < _newMultiSigOwners.length; i++){
                page.multiSigOwners.push(_newMultiSigOwners[i]);
            }
            page.multiSigThreshold = _newMultiSigThreshold;
        } 
        else if (_newOwnershipType == OwnershipType.Permissionless) {
            // 이제 누구나 수정 가능
        }
        else {
            revert("Invalid new ownership type");
        }

        emit OwnershipChanged(_pageId, oldType, _newOwnershipType);
    }

    // -----------------------------
    // Permissionless treasury 분배
    // -----------------------------
    function distributePageTreasury(uint256 _pageId) external override {
        // Permissionless만 적용
        Page storage page = _pages[_pageId];
        require(page.ownershipType == OwnershipType.Permissionless, "Not permissionless");

        uint256 balance = _pageBalances[_pageId];
        require(balance > 0, "No treasury to distribute");

        // 참여자 목록
        address[] storage participants = _pageParticipants[_pageId];
        require(participants.length > 0, "No participants");

        // 간단한 pseudo-random
        // (보안적으로 안전치 않으므로 실제 메인넷 서비스엔 Chainlink VRF 등 사용 권장)
        uint256 rand = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    msg.sender,
                    balance,
                    participants.length
                )
            )
        );
        uint256 winnerIndex = rand % participants.length;
        address winner = participants[winnerIndex];

        // 전액 지급
        _pageBalances[_pageId] = 0;
        (bool success, ) = winner.call{value: balance}("");
        require(success, "Send failed");

        emit PageTreasuryDistributed(_pageId, winner, balance);
    }

    // -----------------------------
    // 조회 함수
    // -----------------------------
    function getCurrentHtml(uint256 _pageId) external view override returns (string memory) {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        return _pages[_pageId].currentHtml;
    }

    function getMultiSigOwners(uint256 _pageId)
        external
        view
        override
        returns (address[] memory)
    {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        return _pages[_pageId].multiSigOwners;
    }

    function getUpdateRequest(
        uint256 _pageId, 
        uint256 _requestId
    )
        external
        view
        override
        returns (
            string memory newHtml,
            bool executed,
            uint256 approvalCount
        )
    {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];
        require(_requestId < page.updateRequestCount, "Invalid requestId");

        UpdateRequest storage req = page.updateRequests[_requestId];
        return (req.newHtml, req.executed, req.approvalCount);
    }
}
