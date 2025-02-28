// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Web3ite} from "../src/Web3ite.sol";
import {IWeb3ite} from "../src/IWeb3ite.sol";

contract Web3iteTest is Test {
    Web3ite public web3ite;
    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        web3ite = new Web3ite();
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    function test_CreateSinglePage() public {
        address[] memory owners = new address[](1);
        owners[0] = owner;

        IWeb3ite.OwnershipConfig memory config = IWeb3ite.OwnershipConfig({
            ownershipType: IWeb3ite.OwnershipType.Single,
            multiSigOwners: owners,
            multiSigThreshold: 1
        });

        uint256 pageId = web3ite.createPage(
            "Test Page", "data:image/jpeg;base64,test123", "<!DOCTYPE html><html>Test</html>", config, 0.001 ether, false
        );

        assertEq(pageId, 1);

        IWeb3ite.PageInfo memory info = web3ite.getPageInfo(pageId);
        assertEq(info.name, "Test Page");
        assertEq(info.thumbnail, "data:image/jpeg;base64,test123");
        assertEq(info.currentHtml, "<!DOCTYPE html><html>Test</html>");
        assertEq(uint256(info.ownershipType), uint256(IWeb3ite.OwnershipType.Single));
        assertEq(info.updateFee, 0.001 ether);
        assertEq(info.imt, false);
    }

    function test_CreateMultiSigPage() public {
        address[] memory owners = new address[](2);
        owners[0] = owner;
        owners[1] = user1;

        IWeb3ite.OwnershipConfig memory config = IWeb3ite.OwnershipConfig({
            ownershipType: IWeb3ite.OwnershipType.MultiSig,
            multiSigOwners: owners,
            multiSigThreshold: 2
        });

        uint256 pageId = web3ite.createPage(
            "MultiSig Page", "data:image/jpeg;base64,test123", "<!DOCTYPE html><html>Test</html>", config, 0.001 ether, false
        );

        IWeb3ite.PageInfo memory info = web3ite.getPageInfo(pageId);
        assertEq(info.multiSigOwners.length, 2);
        assertEq(info.multiSigThreshold, 2);
    }

    function test_UpdatePermissionlessPage() public {
        address[] memory owners = new address[](0);

        IWeb3ite.OwnershipConfig memory config = IWeb3ite.OwnershipConfig({
            ownershipType: IWeb3ite.OwnershipType.Permissionless,
            multiSigOwners: owners,
            multiSigThreshold: 0
        });

        uint256 pageId = web3ite.createPage(
            "Permissionless Page", "data:image/jpeg;base64,test123", "<!DOCTYPE html><html>Test</html>", config, 0.001 ether, false
        );

        vm.prank(user1);
        web3ite.requestUpdate{value: 0.001 ether}(
            pageId, "New Name", "data:image/jpeg;base64,test123", "<!DOCTYPE html><html>Updated</html>"
        );

        IWeb3ite.PageInfo memory info = web3ite.getPageInfo(pageId);
        assertEq(info.name, "New Name");
        assertEq(info.thumbnail, "data:image/jpeg;base64,test123");
        assertEq(info.currentHtml, "<!DOCTYPE html><html>Updated</html>");
    }

    function test_UpdateSinglePage() public {
        address[] memory owners = new address[](1);
        owners[0] = owner;

        IWeb3ite.OwnershipConfig memory config = IWeb3ite.OwnershipConfig({
            ownershipType: IWeb3ite.OwnershipType.Single,
            multiSigOwners: owners,
            multiSigThreshold: 1
        });

        uint256 pageId = web3ite.createPage(
            "Single Page", "data:image/jpeg;base64,test123", "<!DOCTYPE html><html>Test</html>", config, 0.001 ether, false
        );

        vm.prank(user1);
        web3ite.requestUpdate{value: 0.001 ether}(pageId, "New Name", "", "");

        web3ite.approveRequest(pageId, 0);

        IWeb3ite.PageInfo memory info = web3ite.getPageInfo(pageId);
        assertEq(info.name, "New Name");
    }

    function test_VoteSystem() public {
        // Create a page
        address[] memory owners = new address[](1);
        owners[0] = owner;

        IWeb3ite.OwnershipConfig memory config = IWeb3ite.OwnershipConfig({
            ownershipType: IWeb3ite.OwnershipType.Single,
            multiSigOwners: owners,
            multiSigThreshold: 1
        });

        uint256 pageId = web3ite.createPage(
            "Test Page", "data:image/jpeg;base64,test123", "<!DOCTYPE html><html>Test</html>", config, 0.001 ether, false
        );

        // Test voting
        vm.prank(user1);
        web3ite.vote(pageId, true); // Like

        vm.prank(user2);
        web3ite.vote(pageId, false); // Dislike

        IWeb3ite.PageInfo memory info = web3ite.getPageInfo(pageId);
        assertEq(uint256(info.totalLikes), 1);
        assertEq(uint256(info.totalDislikes), 1);

        // Test vote change
        vm.prank(user1);
        web3ite.vote(pageId, false); // Change like to dislike

        info = web3ite.getPageInfo(pageId);
        assertEq(uint256(info.totalLikes), 0);
        assertEq(uint256(info.totalDislikes), 2);
    }

    function test_RevertWhen_DuplicateVote() public {
        // Create a page
        address[] memory owners = new address[](1);
        owners[0] = owner;

        IWeb3ite.OwnershipConfig memory config = IWeb3ite.OwnershipConfig({
            ownershipType: IWeb3ite.OwnershipType.Single,
            multiSigOwners: owners,
            multiSigThreshold: 1
        });

        uint256 pageId = web3ite.createPage(
            "Test Page", "data:image/jpeg;base64,test123", "<!DOCTYPE html><html>Test</html>", config, 0.001 ether, false
        );

        vm.prank(user1);
        web3ite.vote(pageId, true);

        vm.prank(user1);
        vm.expectRevert("Already liked");
        web3ite.vote(pageId, true);
    }
}
