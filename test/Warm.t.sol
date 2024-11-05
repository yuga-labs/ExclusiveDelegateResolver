// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Warm} from "../src/Warm.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";

contract WarmTest is Test {
    Warm public warm;
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;

    address public coldWallet;
    address public hotWallet;
    address public delegatedManager;
    address public tokenDelegate;
    address public contractDelegate;

    function setUp() public {
        warm = new Warm();
        mockERC721 = new MockERC721();
        mockERC1155 = new MockERC1155();

        coldWallet = makeAddr("coldWallet");
        hotWallet = makeAddr("hotWallet");
        delegatedManager = makeAddr("delegatedManager");
        tokenDelegate = makeAddr("tokenDelegate");
        contractDelegate = makeAddr("contractDelegate");

        // Fund cold wallet for gas
        vm.deal(coldWallet, 100 ether);
    }

    // === Delegation Rights Tests ===

    function testSetDelegationRights() public {
        uint256 expiration = block.timestamp + 1 days;
        
        vm.prank(coldWallet);
        warm.setDelegationRights(delegatedManager, expiration);

        (address walletAddress, uint96 expirationTimestamp) = warm.delegationRights(coldWallet);
        assertEq(walletAddress, delegatedManager);
        assertEq(expirationTimestamp, expiration);
    }

    function testCannotDelegateToSelf() public {
        vm.prank(coldWallet);
        vm.expectRevert(Warm.CannotLinkToSelf.selector);
        warm.setDelegationRights(coldWallet, block.timestamp + 1 days);
    }

    // === Contract Delegation Tests ===

    function testContractDelegation() public {
        uint256 expiration = block.timestamp + 1 days;
        
        // Set up delegation rights
        vm.startPrank(coldWallet);
        warm.setDelegationRights(delegatedManager, expiration);
        vm.stopPrank();

        // Delegate contract using delegated manager
        vm.prank(delegatedManager);
        warm.setContractDelegation(
            coldWallet,
            address(mockERC721),
            contractDelegate,
            expiration
        );

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, 1);

        // Check that contract delegation works
        address proxiedOwner = warm.ownerOf(address(mockERC721), 1);
        assertEq(proxiedOwner, contractDelegate);
    }

    function testUnauthorizedContractDelegation() public {
        vm.prank(hotWallet);
        vm.expectRevert(Warm.NotAuthorized.selector);
        warm.setContractDelegation(
            coldWallet,
            address(mockERC721),
            contractDelegate,
            block.timestamp + 1 days
        );
    }

    // === Token Delegation Tests ===

    function testTokenDelegation() public {
        uint256 expiration = block.timestamp + 1 days;
        
        // Direct token delegation from cold wallet
        vm.prank(coldWallet);
        warm.setTokenDelegation(
            coldWallet,
            address(mockERC721),
            1,
            tokenDelegate,
            expiration
        );

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, 1);

        // Check that token delegation works
        address proxiedOwner = warm.ownerOf(address(mockERC721), 1);
        assertEq(proxiedOwner, tokenDelegate);
    }

    // === Delegation Priority Tests ===

    function testDelegationPriority() public {
        uint256 expiration = block.timestamp + 1 days;
        
        vm.startPrank(coldWallet);
        
        // Set wallet-wide delegation
        warm.setHotWallet(hotWallet, expiration);
        
        // Set contract-wide delegation
        warm.setContractDelegation(
            coldWallet,
            address(mockERC721),
            contractDelegate,
            expiration
        );
        
        // Set token-specific delegation
        warm.setTokenDelegation(
            coldWallet,
            address(mockERC721),
            1,
            tokenDelegate,
            expiration
        );
        
        vm.stopPrank();

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, 1);
        mockERC721.mint(coldWallet, 2);

        // Token #1 should be delegated to tokenDelegate
        assertEq(warm.ownerOf(address(mockERC721), 1), tokenDelegate);
        
        // Token #2 should be delegated to contractDelegate
        assertEq(warm.ownerOf(address(mockERC721), 2), contractDelegate);
        
        // Different contract should use wallet-wide delegation
        MockERC721 differentMock = new MockERC721();
        differentMock.mint(coldWallet, 3);
        assertEq(warm.ownerOf(address(differentMock), 3), hotWallet);
    }

    function testExpiredDelegations() public {
        uint256 expiration = block.timestamp + 1 days;
        
        vm.startPrank(coldWallet);
        
        // Set all delegation levels
        warm.setHotWallet(hotWallet, expiration);
        warm.setContractDelegation(
            coldWallet,
            address(mockERC721),
            contractDelegate,
            expiration
        );
        warm.setTokenDelegation(
            coldWallet,
            address(mockERC721),
            1,
            tokenDelegate,
            expiration
        );
        
        vm.stopPrank();

        mockERC721.mint(coldWallet, 1);

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 days);

        // Should return original owner when all delegations are expired
        assertEq(warm.ownerOf(address(mockERC721), 1), coldWallet);
    }
}
