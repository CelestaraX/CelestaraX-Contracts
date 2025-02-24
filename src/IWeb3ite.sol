// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IWeb3ite
 * @notice Interface for DApp contract that provides page creation and modification functionality
 */
interface IWeb3ite {
    // Ownership types
    enum OwnershipType {
        Single,         // 0 - Single owner
        MultiSig,       // 1 - Multiple owners with threshold
        Permissionless  // 2 - Anyone can modify
    }

    // Events
    event PageCreated(
        uint256 indexed pageId,
        address indexed creator,
        string name,
        string thumbnail,
        OwnershipType ownershipType,
        uint256 updateFee,
        bool imt
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
    // New: Event for page treasury distribution
    event PageTreasuryDistributed(
        uint256 indexed pageId,
        address indexed winner,
        uint256 amount
    );

    /**
     * @notice Creates a new page with specified parameters
     * @param _name Page name
     * @param _thumbnail Base64 encoded thumbnail image
     * @param _initialHtml Initial HTML content
     * @param _ownershipType Type of ownership (Single/MultiSig/Permissionless)
     * @param _multiSigOwners Array of owner addresses for MultiSig type
     * @param _multiSigThreshold Required number of approvals for MultiSig
     * @param _updateFee Fee required for update requests
     * @param _imt IMT token flag
     * @return pageId Unique identifier for the created page
     */
    function createPage(
        string calldata _name,
        string calldata _thumbnail,
        string calldata _initialHtml,
        OwnershipType _ownershipType,
        address[] calldata _multiSigOwners,
        uint256 _multiSigThreshold,
        uint256 _updateFee,
        bool _imt
    ) external returns (uint256 pageId);

    /**
     * @notice Submits an update request (or immediate update for Permissionless)
     * @param _pageId ID of the page to update
     * @param _newHtml Proposed new HTML content
     */
    function requestUpdate(uint256 _pageId, string calldata _newHtml) external payable;

    /**
     * @notice Approves an update request for Single/MultiSig pages
     *         Executes the update when threshold is reached
     * @param _pageId Page ID
     * @param _requestId Update request ID
     */
    function approveRequest(uint256 _pageId, uint256 _requestId) external;

    /**
     * @notice Withdraws accumulated fees for a page
     *         Single owner => Only owner can withdraw
     *         MultiSig => Any owner can trigger equal distribution to all owners
     *         Permissionless => Not available
     * @param _pageId Page ID
     */
    function withdrawPageFees(uint256 _pageId) external;

    /**
     * @notice Changes the ownership type of a page (only available for Single type)
     * @param _pageId Page ID
     * @param _newOwnershipType New ownership type
     * @param _newMultiSigOwners New owner addresses for MultiSig
     * @param _newMultiSigThreshold New threshold for MultiSig
     */
    function changeOwnership(
        uint256 _pageId,
        OwnershipType _newOwnershipType,
        address[] calldata _newMultiSigOwners,
        uint256 _newMultiSigThreshold
    ) external;

    /**
     * @notice Distributes the treasury of a Permissionless page to one of the participants
     * @param _pageId Page ID
     */
    function distributePageTreasury(uint256 _pageId) external;

    // View functions
    function getCurrentHtml(uint256 _pageId) external view returns (string memory);
    function getPageOwners(uint256 _pageId) external view returns (address[] memory);
    function getUpdateRequest(
        uint256 _pageId, 
        uint256 _requestId
    ) external view returns (string memory newHtml, bool executed, uint256 approvalCount);

    // Accumulated fees per page
    function pageBalances(uint256 _pageId) external view returns (uint256);
    function pageCount() external view returns (uint256);
}