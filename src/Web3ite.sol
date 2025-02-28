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
    string[] VALID_IMAGE_PREFIXES = [
        "data:image/jpeg;base64,",
        "data:image/jpg;base64,",
        "data:image/png;base64,",
        "data:image/gif;base64,",
        "data:image/webp;base64,",
        "data:image/svg+xml;base64,"
    ];

    /**
     * @notice Internal structure for update requests
     * @dev Stores proposed changes and approval status
     */
    struct UpdateRequest {
        string newName; // Proposed new page name
        string newThumbnail; // Proposed new thumbnail
        string newHtml; // Proposed new HTML content
        bool executed; // Whether this request has been executed
        uint256 approvalCount; // Number of approvals received
        mapping(address => bool) voted; // Tracks which owners have voted
    }

    /**
     * @notice Internal structure for page data
     */
    struct Page {
        address[] multiSigOwners;
        string name;
        string thumbnail;
        string currentHtml;
        OwnershipType ownershipType;
        bool imt;
        uint120 totalLikes;
        uint120 totalDislikes;
        uint256 multiSigThreshold;
        uint256 updateRequestCount;
        uint256 updateFee;
        mapping(uint256 => UpdateRequest) updateRequests;
        mapping(address => bool) hasLiked;
        mapping(address => bool) hasDisliked;
    }

    // State variables
    uint256 private _pageCount;
    mapping(uint256 => Page) private _pages;
    mapping(uint256 => uint256) private _pageBalances;
    mapping(uint256 => address[]) private _pageParticipants;
    mapping(uint256 => mapping(address => bool)) private _hasParticipated;

    /**
     * @dev Checks if string starts with any valid image prefix
     */
    function _isValidBase64Image(string memory _str) internal view returns (bool) {
        bytes memory strBytes = bytes(_str);

        for (uint256 i = 0; i < VALID_IMAGE_PREFIXES.length; i++) {
            bytes memory prefix = bytes(VALID_IMAGE_PREFIXES[i]);
            if (strBytes.length < prefix.length) continue;

            bool isMatch = true;
            for (uint256 j = 0; j < prefix.length; j++) {
                if (strBytes[j] != prefix[j]) {
                    isMatch = false;
                    break;
                }
            }
            if (isMatch) return true;
        }

        return false;
    }

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
        require(_isValidBase64Image(_thumbnail), "Invalid base64 image format");

        bytes memory htmlBytes = bytes(_initialHtml);
        require(htmlBytes.length >= DOCTYPE.length + HTML_END.length, "HTML too short");

        // DOCTYPE check
        for (uint256 i = 0; i < DOCTYPE.length; i++) {
            require(htmlBytes[i] == DOCTYPE[i], "HTML must start with DOCTYPE");
        }

        // HTML_END check
        for (uint256 i = 0; i < HTML_END.length; i++) {
            require(htmlBytes[htmlBytes.length - HTML_END.length + i] == HTML_END[i], "HTML must end with </html>");
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
        } else if (_ownerConfig.ownershipType == OwnershipType.MultiSig) {
            require(_ownerConfig.multiSigOwners.length > 0, "No owners for multi-sig");
            require(
                _ownerConfig.multiSigThreshold > 0
                    && _ownerConfig.multiSigThreshold <= _ownerConfig.multiSigOwners.length,
                "Invalid multiSigThreshold"
            );
            for (uint256 i = 0; i < _ownerConfig.multiSigOwners.length; i++) {
                newPage.multiSigOwners.push(_ownerConfig.multiSigOwners[i]);
            }
            newPage.multiSigThreshold = _ownerConfig.multiSigThreshold;
        } else if (_ownerConfig.ownershipType == OwnershipType.Permissionless) {
            require(_ownerConfig.multiSigOwners.length == 0, "Permissionless doesn't need owners");
            require(_ownerConfig.multiSigThreshold == 0, "Permissionless doesn't need threshold");
        } else {
            revert("Invalid ownership type");
        }

        emit PageCreated(
            pageId,
            msg.sender,
            _name,
            _thumbnail,
            _ownerConfig.ownershipType,
            _ownerConfig.multiSigOwners,
            _ownerConfig.multiSigThreshold,
            _updateFee,
            _imt
        );
    }

    /**
     * @notice Allows users to vote on a page
     */
    function vote(uint256 _pageId, bool _isLike) external {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];

        if (_isLike) {
            require(!page.hasLiked[msg.sender], "Already liked");
            require(page.totalLikes < type(uint120).max, "Max likes reached");
            if (page.hasDisliked[msg.sender]) {
                page.hasDisliked[msg.sender] = false;
                page.totalDislikes--;
            }
            page.hasLiked[msg.sender] = true;
            page.totalLikes++;
        } else {
            require(!page.hasDisliked[msg.sender], "Already disliked");
            require(page.totalDislikes < type(uint120).max, "Max dislikes reached");
            if (page.hasLiked[msg.sender]) {
                page.hasLiked[msg.sender] = false;
                page.totalLikes--;
            }
            page.hasDisliked[msg.sender] = true;
            page.totalDislikes++;
        }

        emit VoteChanged(_pageId, page.totalLikes, page.totalDislikes);
    }

    /**
     * @notice Submits an update request or executes immediate update for Permissionless pages
     */
    function requestUpdate(
        uint256 _pageId,
        string calldata _newName,
        string calldata _newThumbnail,
        string calldata _newHtml
    ) external payable override {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];

        require(!page.imt, "Page is immutable");
        require(msg.value >= page.updateFee, "Insufficient fee");

        bool hasNewName = bytes(_newName).length > 0;
        bool hasNewThumbnail = bytes(_newThumbnail).length > 0;
        bool hasNewHtml = bytes(_newHtml).length > 0;
        require(hasNewName || hasNewThumbnail || hasNewHtml, "No updates provided");

        if (hasNewThumbnail) {
            require(_isValidBase64Image(_newThumbnail), "Invalid base64 image format");
        }

        if (hasNewHtml) {
            bytes memory htmlBytes = bytes(_newHtml);
            require(htmlBytes.length >= DOCTYPE.length + HTML_END.length, "HTML too short");

            for (uint256 i = 0; i < DOCTYPE.length; i++) {
                require(htmlBytes[i] == DOCTYPE[i], "HTML must start with DOCTYPE");
            }

            for (uint256 i = 0; i < HTML_END.length; i++) {
                require(htmlBytes[htmlBytes.length - HTML_END.length + i] == HTML_END[i], "HTML must end with </html>");
            }
        }

        if (page.ownershipType == OwnershipType.Permissionless) {
            if (hasNewName) page.name = _newName;
            if (hasNewThumbnail) page.thumbnail = _newThumbnail;
            if (hasNewHtml) page.currentHtml = _newHtml;
            _pageBalances[_pageId] += msg.value;

            if (!_hasParticipated[_pageId][msg.sender]) {
                _pageParticipants[_pageId].push(msg.sender);
                _hasParticipated[_pageId][msg.sender] = true;
            }

            emit UpdateExecutedPermissionless(_pageId, _newName, _newThumbnail, _newHtml);
        } else {
            uint256 requestId = page.updateRequestCount++;
            UpdateRequest storage request = page.updateRequests[requestId];

            if (hasNewName) request.newName = _newName;
            if (hasNewThumbnail) request.newThumbnail = _newThumbnail;
            if (hasNewHtml) request.newHtml = _newHtml;
            _pageBalances[_pageId] += msg.value;

            emit UpdateRequested(_pageId, requestId, msg.sender, hasNewName, hasNewThumbnail, hasNewHtml);
        }
    }

    /**
     * @notice Approves an update request for Single/MultiSig pages
     */
    function approveRequest(uint256 _pageId, uint256 _requestId) external override {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];
        require(page.ownershipType != OwnershipType.Permissionless, "No approval needed for permissionless");
        require(_requestId < page.updateRequestCount, "Invalid requestId");

        UpdateRequest storage req = page.updateRequests[_requestId];
        require(!req.executed, "Already executed");

        bool isOwner = false;
        for (uint256 i = 0; i < page.multiSigOwners.length; i++) {
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

        if (req.approvalCount >= page.multiSigThreshold) {
            _executeUpdate(_pageId, _requestId);
        }
    }

    /**
     * @notice Internal function to execute an approved update request
     * @param _pageId ID of the page
     * @param _requestId ID of the request to execute
     * @dev Updates page content with non-empty values from the request
     */
    function _executeUpdate(uint256 _pageId, uint256 _requestId) internal {
        Page storage page = _pages[_pageId];
        UpdateRequest storage request = page.updateRequests[_requestId];

        if (bytes(request.newName).length > 0) {
            page.name = request.newName;
        }
        if (bytes(request.newThumbnail).length > 0) {
            page.thumbnail = request.newThumbnail;
        }
        if (bytes(request.newHtml).length > 0) {
            page.currentHtml = request.newHtml;
        }

        request.executed = true;

        emit UpdateExecuted(_pageId, _requestId, request.newName, request.newThumbnail, request.newHtml);
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

            (bool success,) = msg.sender.call{value: balance}("");
            require(success, "Transfer failed");

            emit PageFeesWithdrawn(_pageId, msg.sender, balance);
        } else if (page.ownershipType == OwnershipType.MultiSig) {
            bool isOwner = false;
            for (uint256 i = 0; i < page.multiSigOwners.length; i++) {
                if (page.multiSigOwners[i] == msg.sender) {
                    isOwner = true;
                    break;
                }
            }
            require(isOwner, "Not an owner");

            _pageBalances[_pageId] = 0;
            uint256 share = balance / page.multiSigOwners.length;

            for (uint256 i = 0; i < page.multiSigOwners.length; i++) {
                (bool success,) = page.multiSigOwners[i].call{value: share}("");
                require(success, "Transfer failed");
            }

            emit PageFeesWithdrawn(_pageId, msg.sender, balance);
        } else {
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
        } else if (_newOwnershipType == OwnershipType.MultiSig) {
            require(_newMultiSigOwners.length > 0, "No owners for multi-sig");
            require(
                _newMultiSigThreshold > 0 && _newMultiSigThreshold <= _newMultiSigOwners.length, "Invalid threshold"
            );
            for (uint256 i = 0; i < _newMultiSigOwners.length; i++) {
                page.multiSigOwners.push(_newMultiSigOwners[i]);
            }
            page.multiSigThreshold = _newMultiSigThreshold;
        } else if (_newOwnershipType == OwnershipType.Permissionless) {
            require(_newMultiSigOwners.length == 0, "Permissionless doesn't need owners");
            require(_newMultiSigThreshold == 0, "Permissionless doesn't need threshold");
        } else {
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
                abi.encodePacked(blockhash(block.number - 1), block.timestamp, msg.sender, balance, participants.length)
            )
        );
        uint256 winnerIndex = rand % participants.length;
        address winner = participants[winnerIndex];

        _pageBalances[_pageId] = 0;
        (bool success,) = winner.call{value: balance}("");
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
            balance: _pageBalances[_pageId],
            totalLikes: page.totalLikes,
            totalDislikes: page.totalDislikes
        });
    }

    /**
     * @notice View functions
     */
    function getCurrentHtml(uint256 _pageId) external view override returns (string memory) {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        return _pages[_pageId].currentHtml;
    }

    /**
     * @notice Returns the owners of a specific page
     */
    function getPageOwners(uint256 _pageId) external view override returns (address[] memory) {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        return _pages[_pageId].multiSigOwners;
    }

    /**
     * @notice Returns information about an update request
     */
    function getUpdateRequest(uint256 _pageId, uint256 _requestId)
        external
        view
        override
        returns (
            string memory newName,
            string memory newThumbnail,
            string memory newHtml,
            bool executed,
            uint256 approvalCount
        )
    {
        require(_pageId > 0 && _pageId <= _pageCount, "Invalid pageId");
        Page storage page = _pages[_pageId];
        require(_requestId < page.updateRequestCount, "Invalid requestId");

        UpdateRequest storage req = page.updateRequests[_requestId];
        return (req.newName, req.newThumbnail, req.newHtml, req.executed, req.approvalCount);
    }

    /**
     * @notice Returns the total number of pages
     */
    function pageCount() external view override returns (uint256) {
        return _pageCount;
    }

    /**
     * @notice Returns the balance of a specific page
     */
    function pageBalances(uint256 _pageId) external view override returns (uint256) {
        return _pageBalances[_pageId];
    }
}
