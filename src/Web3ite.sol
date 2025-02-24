// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IWeb3ite.sol";

/**
 * @title Web3ite
 * @notice Implementation of IWeb3ite interface
 * @dev Provides functionality for creating and managing HTML pages on-chain
 */
contract Web3ite is IWeb3ite {
    // Constants for HTML validation
    bytes constant DOCTYPE = "<!DOCTYPE html>";
    bytes constant HTML_END = "</html>";

    /**
     * @notice Internal structure for update requests
     */
    struct UpdateRequest {
        string newHtml;
        bool executed;
        uint256 approvalCount;          
        mapping(address => bool) voted; // MultiSig approval status
    }

    /**
     * @notice Internal structure for page data
     */
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

    // State variables
    uint256 private _pageCount;
    mapping(uint256 => Page) private _pages;
    mapping(uint256 => uint256) private _pageBalances;
    mapping(uint256 => address[]) private _pageParticipants;
    mapping(uint256 => mapping(address => bool)) private _hasParticipated;

    /**
     * @notice Creates a new page with specified parameters
     */
    function createPage(
        string calldata _name,
        string calldata _thumbnail,
        string calldata _initialHtml,
        OwnershipConfig calldata _ownerConfig,
        uint256 _updateFee,
        bool _imt
    ) external override returns (uint256 pageId) {
        bytes memory htmlBytes = bytes(_initialHtml);
        require(htmlBytes.length >= DOCTYPE.length + HTML_END.length, "HTML too short");
        
        // DOCTYPE check
        for(uint i = 0; i < DOCTYPE.length; i++) {
            require(htmlBytes[i] == DOCTYPE[i], "HTML must start with DOCTYPE");
        }
        
        // HTML_END check
        for(uint i = 0; i < HTML_END.length; i++) {
            require(
                htmlBytes[htmlBytes.length - HTML_END.length + i] == HTML_END[i],
                "HTML must end with </html>"
            );
        }

        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_thumbnail).length > 0, "Thumbnail cannot be empty");

        pageId = ++_pageCount;
        Page storage newPage = _pages[pageId];
        
        newPage.name = _name;
        newPage.thumbnail = _thumbnail;
        newPage.currentHtml = _initialHtml;
        newPage.ownershipType = _ownerConfig.ownershipType;
        newPage.updateFee = _updateFee;
        newPage.imt = _imt;

        if (_ownerConfig.ownershipType == OwnershipType.Single) {
            require(_ownerConfig.multiSigOwners.length == 1, "Single ownership needs exactly one owner");
            require(_ownerConfig.multiSigThreshold == 1, "Single ownership threshold must be 1");
            newPage.multiSigOwners.push(_ownerConfig.multiSigOwners[0]);
            newPage.multiSigThreshold = 1;
        }
        else if (_ownerConfig.ownershipType == OwnershipType.MultiSig) {
            require(_ownerConfig.multiSigOwners.length > 0, "No owners for multi-sig");
            require(
                _ownerConfig.multiSigThreshold > 0 && 
                _ownerConfig.multiSigThreshold <= _ownerConfig.multiSigOwners.length,
                "Invalid multiSigThreshold"
            );
            for(uint256 i=0; i < _ownerConfig.multiSigOwners.length; i++){
                newPage.multiSigOwners.push(_ownerConfig.multiSigOwners[i]);
            }
            newPage.multiSigThreshold = _ownerConfig.multiSigThreshold;
        }
        else if (_ownerConfig.ownershipType == OwnershipType.Permissionless) {
            require(_ownerConfig.multiSigOwners.length == 0, "Permissionless doesn't need owners");
            require(_ownerConfig.multiSigThreshold == 0, "Permissionless doesn't need threshold");
        }
        else {
            revert("Invalid ownership type");
        }

        emit PageCreated(pageId, msg.sender, _name, _thumbnail, _ownerConfig.ownershipType, _updateFee, _imt);
    }

    /**
     * @notice Submits an update request or executes immediate update for Permissionless pages
     */
    function requestUpdate(uint256 _pageId, string calldata _newHtml)
        external
        payable
        override
    {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];

        require(!page.imt, "Page is immutable");
        require(msg.value >= page.updateFee, "Insufficient fee");
        
        _pageBalances[_pageId] += msg.value;

        if (page.ownershipType == OwnershipType.Permissionless) {
            // Immediate update
            page.currentHtml = _newHtml;

            // Record participant (no duplicates)
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

    /**
     * @notice Approves an update request for Single/MultiSig pages
     */
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

    /**
     * @notice Internal function to execute an update
     */
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

    /**
     * @notice Withdraws accumulated fees for a page
     */
    function withdrawPageFees(uint256 _pageId) external override {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];
        uint256 balance = _pageBalances[_pageId];
        require(balance > 0, "No fees to withdraw");

        if (page.ownershipType == OwnershipType.Single) {
            require(msg.sender == page.multiSigOwners[0], "Not owner");
            _pageBalances[_pageId] = 0;

            (bool success, ) = msg.sender.call{value: balance}("");
            require(success, "Transfer failed");

            emit PageFeesWithdrawn(_pageId, msg.sender, balance);
        } 
        else if (page.ownershipType == OwnershipType.MultiSig) {
            bool isOwner = false;
            for(uint256 i=0; i < page.multiSigOwners.length; i++){
                if(page.multiSigOwners[i] == msg.sender){
                    isOwner = true;
                    break;
                }
            }
            require(isOwner, "Not an owner");

            _pageBalances[_pageId] = 0;
            uint256 share = balance / page.multiSigOwners.length;

            for (uint256 i=0; i < page.multiSigOwners.length; i++) {
                (bool success, ) = page.multiSigOwners[i].call{value: share}("");
                require(success, "Transfer failed");
            }

            emit PageFeesWithdrawn(_pageId, msg.sender, balance);
        } 
        else {
            revert("Cannot withdraw from permissionless page");
        }
    }

    /**
     * @notice Changes ownership configuration of a Single ownership page
     */
    function changeOwnership(
        uint256 _pageId,
        OwnershipType _newOwnershipType,
        address[] calldata _newMultiSigOwners,
        uint256 _newMultiSigThreshold
    ) external override {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];
        OwnershipType oldType = page.ownershipType;

        require(oldType == OwnershipType.Single, "Only Single ownership can be changed");
        require(msg.sender == page.multiSigOwners[0], "Not owner");

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

    /**
     * @notice Distributes treasury to a random participant (Permissionless only)
     */
    function distributePageTreasury(uint256 _pageId) external override {
        Page storage page = _pages[_pageId];
        require(page.ownershipType == OwnershipType.Permissionless, "Not permissionless");

        uint256 balance = _pageBalances[_pageId];
        require(balance > 0, "No treasury to distribute");

        address[] storage participants = _pageParticipants[_pageId];
        require(participants.length > 0, "No participants");

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

        _pageBalances[_pageId] = 0;
        (bool success, ) = winner.call{value: balance}("");
        require(success, "Transfer failed");

        emit PageTreasuryDistributed(_pageId, winner, balance);
    }

    /**
     * @notice Retrieves complete information about a page
     */
    function getPageInfo(uint256 _pageId) external view override returns (PageInfo memory info) {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];
        
        return PageInfo({
            name: page.name,
            thumbnail: page.thumbnail,
            currentHtml: page.currentHtml,
            ownershipType: page.ownershipType,
            imt: page.imt,
            multiSigOwners: page.multiSigOwners,
            multiSigThreshold: page.multiSigThreshold,
            updateFee: page.updateFee,
            balance: _pageBalances[_pageId]
        });
    }

    /**
     * @notice View functions
     */
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

    function pageCount() external view override returns (uint256) {
        return _pageCount;
    }

    function pageBalances(uint256 _pageId) external view override returns (uint256) {
        return _pageBalances[_pageId];
    }
}