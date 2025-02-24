// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IWeb3ite.sol";

contract Web3ite is IWeb3ite {
    bytes constant DOCTYPE = "<!DOCTYPE html>";
    bytes constant HTML_END = "</html>";
    // Update request structure
    struct UpdateRequest {
        string newHtml;
        bool executed;
        uint256 approvalCount;          
        mapping(address => bool) voted; // MultiSig approval status
    }

    struct Page {
        string name;
        string thumbnail;
        string currentHtml;
        OwnershipType ownershipType;
        bool imt;
     
        address[] multiSigOwners;   
        uint256 multiSigThreshold;

        uint256 updateRequestCount;
        mapping(uint256 => UpdateRequest) updateRequests;

        uint256 updateFee;
    }

    // Page identification
    uint256 private _pageCount;
    mapping(uint256 => Page) private _pages;
    // Accumulated fees per page
    mapping(uint256 => uint256) private _pageBalances;

    // -----------------------------
    // Permissionless participant records
    // -----------------------------
    // pageId => array (no duplicates)
    mapping(uint256 => address[]) private _pageParticipants;
    // pageId => (address => bool) : check if already participated
    mapping(uint256 => mapping(address => bool)) private _hasParticipated;

    // -----------------------------
    // View functions
    // -----------------------------
    function pageCount() external view override returns (uint256) {
        return _pageCount;
    }
    function pageBalances(uint256 _pageId) external view override returns (uint256) {
        return _pageBalances[_pageId];
    }

    // -----------------------------
    // Page creation
    // -----------------------------
    function createPage(
        string calldata _name,
        string calldata _thumbnail,
        string calldata _initialHtml,
        OwnershipType _ownershipType,
        address[] calldata _multiSigOwners,
        uint256 _multiSigThreshold,
        uint256 _updateFee,
        bool _imt
    )
        external
        override
        returns (uint256 pageId)
    {
        bytes memory htmlBytes = bytes(_initialHtml);
        require(htmlBytes.length >= DOCTYPE.length + HTML_END.length, "HTML too short");
        
        // Check DOCTYPE
        bytes memory doctype = new bytes(DOCTYPE.length);
        for(uint i = 0; i < DOCTYPE.length; i++) {
            doctype[i] = htmlBytes[i];
        }
        require(keccak256(doctype) == keccak256(DOCTYPE), "HTML must start with DOCTYPE");
        
        // Check HTML_END
        bytes memory htmlEnd = new bytes(HTML_END.length);
        for(uint i = 0; i < HTML_END.length; i++) {
            htmlEnd[i] = htmlBytes[htmlBytes.length - HTML_END.length + i];
        }
        require(keccak256(htmlEnd) == keccak256(HTML_END), "HTML must end with </html>");

        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_thumbnail).length > 0, "Thumbnail cannot be empty");

        pageId = ++_pageCount;

        Page storage newPage = _pages[pageId];
        newPage.name = _name;
        newPage.thumbnail = _thumbnail;
        newPage.currentHtml = _initialHtml;
        newPage.ownershipType = _ownershipType;
        newPage.updateFee = _updateFee;
        newPage.imt = _imt;

        if (_ownershipType == OwnershipType.Single) {
            require(_multiSigOwners.length == 1, "Single ownership needs exactly one owner");
            require(_multiSigThreshold == 1, "Single ownership threshold must be 1");
            newPage.multiSigOwners.push(_multiSigOwners[0]);
            newPage.multiSigThreshold = 1;
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
            require(_multiSigOwners.length == 0, "Permissionless doesn't need owners");
            require(_multiSigThreshold == 0, "Permissionless doesn't need threshold");
        }
        else {
            revert("Invalid ownership type");
        }

        emit PageCreated(pageId, msg.sender, _name, _thumbnail, _ownershipType, _updateFee, _imt);
    }

    // -----------------------------
    // Update request
    // -----------------------------
    function requestUpdate(uint256 _pageId, string calldata _newHtml)
        external
        payable
        override
    {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];

        require(!page.imt, "Page is immutable");

        // Check fee
        require(msg.value >= page.updateFee, "Insufficient fee");
        _pageBalances[_pageId] += msg.value;

        if (page.ownershipType == OwnershipType.Permissionless) {
            // Immediate update
            page.currentHtml = _newHtml;

            // Record participant (prevent duplicates)
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
    // Approval (Single/MultiSig)
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

        bool isOwner = false;
        for (uint256 i=0; i < page.multiSigOwners.length; i++){
            if (page.multiSigOwners[i] == msg.sender) {
                isOwner = true;
                break;
            }
        }
        require(isOwner, "Not an owner");
        require(!req.voted[msg.sender], "Already voted");

        req.voted[msg.sender] = true;
        req.approvalCount++;
        emit Approved(_pageId, _requestId, msg.sender);

        if(req.approvalCount >= page.multiSigThreshold){
            _executeUpdate(page, req, _pageId, _requestId);
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
    // Fee withdrawal
    // (MultiSig -> Equal distribution)
    // -----------------------------
    function withdrawPageFees(uint256 _pageId) external override {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];
        uint256 balance = _pageBalances[_pageId];
        require(balance > 0, "No fees to withdraw");

        if (page.ownershipType == OwnershipType.Single) {
            // Full amount -> owner
            require(msg.sender == page.multiSigOwners[0], "Not owner");
            _pageBalances[_pageId] = 0;

            (bool success, ) = msg.sender.call{value: balance}("");
            require(success, "Withdraw failed");

            emit PageFeesWithdrawn(_pageId, msg.sender, balance);
        } 
        else if (page.ownershipType == OwnershipType.MultiSig) {
            // Any owner can trigger
            bool isOwner = false;
            for(uint256 i=0; i < page.multiSigOwners.length; i++){
                if(page.multiSigOwners[i] == msg.sender){
                    isOwner = true;
                    break;
                }
            }
            require(isOwner, "Not a multi-sig owner");

            // Equal distribution
            _pageBalances[_pageId] = 0;
            uint256 ownersCount = page.multiSigOwners.length;
            uint256 share = balance / ownersCount;

            for (uint256 i=0; i < ownersCount; i++) {
                (bool ok, ) = page.multiSigOwners[i].call{value: share}("");
                require(ok, "Transfer to multi-sig owner failed");
            }

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
    // Change ownership (Single only)
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

        require(oldType == OwnershipType.Single, "Only single ownership can be changed");
        require(msg.sender == page.multiSigOwners[0], "Not owner");

        // Reset ownership settings
        delete page.multiSigOwners;
        page.multiSigThreshold = 0;

        page.ownershipType = _newOwnershipType;

        if (_newOwnershipType == OwnershipType.Single) {
            require(_newMultiSigOwners.length == 1, "Single ownership needs exactly one owner");
            page.multiSigOwners.push(_newMultiSigOwners[0]);
            page.multiSigThreshold = 1;
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
            require(_newMultiSigOwners.length == 0, "Permissionless doesn't need owners");
            require(_newMultiSigThreshold == 0, "Permissionless doesn't need threshold");
        }
        else {
            revert("Invalid new ownership type");
        }

        emit OwnershipChanged(_pageId, oldType, _newOwnershipType);
    }

    // -----------------------------
    // Permissionless treasury distribution
    // -----------------------------
    function distributePageTreasury(uint256 _pageId) external override {
        // Only applies to Permissionless
        Page storage page = _pages[_pageId];
        require(page.ownershipType == OwnershipType.Permissionless, "Not permissionless");

        uint256 balance = _pageBalances[_pageId];
        require(balance > 0, "No treasury to distribute");

        // Participant list
        address[] storage participants = _pageParticipants[_pageId];
        require(participants.length > 0, "No participants");

        // Simple pseudo-random selection
        // (For mainnet service, recommend using Chainlink VRF or similar for security)
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

        // Send full amount
        _pageBalances[_pageId] = 0;
        (bool success, ) = winner.call{value: balance}("");
        require(success, "Send failed");

        emit PageTreasuryDistributed(_pageId, winner, balance);
    }

    // -----------------------------
    // View functions
    // -----------------------------
    function getCurrentHtml(uint256 _pageId) external view override returns (string memory) {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        return _pages[_pageId].currentHtml;
    }

    function getPageOwners(uint256 _pageId)
        external
        view
        override
        returns (address[] memory)
    {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];

        if (page.ownershipType == OwnershipType.Permissionless) {
            return new address[](0);
        } else {
            return page.multiSigOwners;
        }
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