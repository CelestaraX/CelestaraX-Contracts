// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract MillionDollar {
    uint256 public constant NUM_SLOTS = 9;  // 3x3 grid
    uint256 public constant SECONDS_PER_WEEK = 604800;  // 1 week in seconds
    uint256 public constant COST_PER_WEEK = 0.1 ether;

    address public immutable owner;

    struct AdSlot {
        address adOwner;
        string base64Image;  // format: "data:image/png;base64,..."
        string link;        // URL to redirect when clicked
        uint256 expiryTime; // expires after this timestamp
    }

    // slotId => AdSlot
    mapping(uint256 => AdSlot) public adSlots;

    event AdPurchased(uint256 indexed slotId, address indexed buyer);
    event AdUpdated(uint256 indexed slotId, address indexed owner);
    event PaymentWithdrawn(address indexed owner, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function purchaseAd(
        uint256 slotId,
        string calldata base64Image,
        string calldata link
    ) external payable {
        require(slotId < NUM_SLOTS, "Invalid slotId");
        require(msg.value == COST_PER_WEEK, "Invalid payment amount");
        require(bytes(base64Image).length > 0, "Empty image");
        require(bytes(link).length > 0, "Empty link");

        // Check if current ad is expired
        if (adSlots[slotId].adOwner != address(0)) {
            require(block.timestamp > adSlots[slotId].expiryTime, "Slot not expired");
        }

        // Store new ad information
        adSlots[slotId] = AdSlot({
            adOwner: msg.sender,
            base64Image: base64Image,
            link: link,
            expiryTime: block.timestamp + SECONDS_PER_WEEK
        });

        emit AdPurchased(slotId, msg.sender);
    }

    function updateAd(
        uint256 slotId,
        string calldata newBase64Image,
        string calldata newLink
    ) external {
        require(slotId < NUM_SLOTS, "Invalid slotId");
        require(msg.sender == adSlots[slotId].adOwner, "Not the ad owner");
        require(block.timestamp <= adSlots[slotId].expiryTime, "Ad expired");
        require(bytes(newBase64Image).length > 0, "Empty image");
        require(bytes(newLink).length > 0, "Empty link");

        adSlots[slotId].base64Image = newBase64Image;
        adSlots[slotId].link = newLink;

        emit AdUpdated(slotId, msg.sender);
    }

    function getAdJson(uint256 slotId) external view returns (string memory) {
        require(slotId < NUM_SLOTS, "Invalid slotId");
        
        AdSlot memory slot = adSlots[slotId];
        
        // Return empty string if slot is empty or expired
        if (slot.adOwner == address(0) || block.timestamp > slot.expiryTime) {
            return "";
        }

        // Return in JSON format
        return string(
            abi.encodePacked(
                '{',
                '"owner":', uint256(uint160(slot.adOwner)), ',',
                '"image":"', slot.base64Image, '",',
                '"link":"', slot.link, '",',
                '"expiry":', slot.expiryTime,
                '}'
            )
        );
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        
        (bool success, ) = owner.call{value: balance}("");
        require(success, "Withdrawal failed");
        
        emit PaymentWithdrawn(owner, balance);
    }
}