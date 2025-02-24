// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IWeb3ite
 * @notice Interface for DApp contract that provides page creation and modification functionality
 */
interface IWeb3ite {
    /**
     * @notice Types of page ownership
     * @dev Determines how page modifications are handled
     */
    enum OwnershipType {
        Single,         // Single owner
        MultiSig,       // Multiple owners with threshold
        Permissionless  // Anyone can modify
    }

    /**
     * @notice Configuration for page ownership
     * @dev Used when creating or changing page ownership
     */
    struct OwnershipConfig {
        OwnershipType ownershipType;    // Type of ownership
        address[] multiSigOwners;        // List of owners (for Single/MultiSig)
        uint256 multiSigThreshold;       // Required approvals for MultiSig
    }

    /**
     * @notice Complete page information returned by getPageInfo
     */
    struct PageInfo {
        string name;                    // Page name
        string thumbnail;               // Base64 encoded thumbnail
        string currentHtml;             // Current HTML content
        OwnershipType ownershipType;    // Type of ownership
        bool imt;                       // Immutable flag
        address[] multiSigOwners;       // List of owners
        uint256 multiSigThreshold;      // Required approvals
        uint256 updateFee;              // Fee required for updates
        uint256 balance;                // Accumulated fees
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
    event PageTreasuryDistributed(
        uint256 indexed pageId,
        address indexed winner,
        uint256 amount
    );

    /**
     * @notice Creates a new page
     * @param _name Page name
     * @param _thumbnail Base64 encoded thumbnail
     * @param _initialHtml Initial HTML content (must start with DOCTYPE and end with </html>)
     * @param _ownerConfig Ownership configuration
     * @param _updateFee Fee required for update requests
     * @param _imt Immutable flag
     * @return pageId Unique identifier for the created page
     */
    function createPage(
        string calldata _name,
        string calldata _thumbnail,
        string calldata _initialHtml,
        OwnershipConfig calldata _ownerConfig,
        uint256 _updateFee,
        bool _imt
    ) external returns (uint256 pageId);

    /**
     * @notice Submits an update request
     * @param _pageId ID of the page to update
     * @param _newHtml New HTML content
     */
    function requestUpdate(uint256 _pageId, string calldata _newHtml) external payable;

    /**
     * @notice Approves an update request for Single/MultiSig pages
     * @param _pageId Page ID
     * @param _requestId Update request ID
     */
    function approveRequest(uint256 _pageId, uint256 _requestId) external;

    /**
     * @notice Withdraws accumulated fees for a page
     * @param _pageId Page ID
     */
    function withdrawPageFees(uint256 _pageId) external;

    /**
     * @notice Changes ownership configuration of a Single ownership page
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
     * @notice Distributes treasury to a random participant (Permissionless only)
     * @param _pageId Page ID
     */
    function distributePageTreasury(uint256 _pageId) external;

    /**
     * @notice Retrieves complete information about a page
     * @param _pageId Page identifier
     * @return Complete page information
     */
    function getPageInfo(uint256 _pageId) external view returns (PageInfo memory);

    /**
     * @notice Gets current HTML content of a page
     * @param _pageId Page ID
     * @return Current HTML content
     */
    function getCurrentHtml(uint256 _pageId) external view returns (string memory);

    /**
     * @notice Gets owners of a page
     * @param _pageId Page ID
     * @return Array of owner addresses
     */
    function getPageOwners(uint256 _pageId) external view returns (address[] memory);

    /**
     * @notice Gets information about an update request
     * @param _pageId Page ID
     * @param _requestId Request ID
     * @return newHtml Proposed HTML content
     * @return executed Whether the request has been executed
     * @return approvalCount Number of approvals received
     */
    function getUpdateRequest(
        uint256 _pageId, 
        uint256 _requestId
    ) external view returns (string memory newHtml, bool executed, uint256 approvalCount);

    /**
     * @notice Gets accumulated fees for a page
     * @param _pageId Page ID
     * @return Amount of accumulated fees
     */
    function pageBalances(uint256 _pageId) external view returns (uint256);

    /**
     * @notice Gets total number of pages
     * @return Total page count
     */
    function pageCount() external view returns (uint256);
}