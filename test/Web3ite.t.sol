// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/Web3ite.sol";

contract Web3iteTest is Test {
    Web3ite web3ite;

    function setUp() public {
        // 컨트랙트 배포
        web3ite = new Web3ite();
    }

    function testCreatePage() public {
        uint256 pageId = web3ite.createPage(
            "Hello",
            IWeb3ite.OwnershipType.Single,
            new address[](0), 
            0, 
            1e15
        );
        assertEq(pageId, 1);
    }
}
