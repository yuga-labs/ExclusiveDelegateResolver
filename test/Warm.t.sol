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

    // === Link Rights Tests ===

    function testSetLinkRights() public {
        uint256 expiration = block.timestamp + 1 days;
        
        vm.prank(coldWallet);
        warm.setLinkRights(delegatedManager, expiration);

        (address walletAddress, uint96 expirationTimestamp) = warm.linkRights(coldWallet);
        assertEq(walletAddress, delegatedManager);
        assertEq(expirationTimestamp, expiration);

        // Test that delegated manager can set contract link
        vm.prank(delegatedManager);
        warm.setContractLink(
            coldWallet,
            address(mockERC721),
            contractDelegate,
            expiration
        );

        // Verify contract link was set
        (address proxiedAddress, ) = warm.contractLinks(coldWallet, address(mockERC721));
        assertEq(proxiedAddress, contractDelegate);

        // Test that delegated manager can set token link
        vm.prank(delegatedManager);
        warm.setTokenLink(
            coldWallet,
            address(mockERC721),
            1,
            tokenDelegate,
            expiration
        );

        // Verify token link was set
        (proxiedAddress, ) = warm.tokenLinks(coldWallet, address(mockERC721), 1);
        assertEq(proxiedAddress, tokenDelegate);

        // Test that delegated manager can revoke links by passing in zero address
        vm.prank(delegatedManager);
        warm.setContractLink(
            coldWallet,
            address(mockERC721),
            address(0),
            type(uint96).max
        );

        // Verify contract link was revoked
        (proxiedAddress, ) = warm.walletLinks(coldWallet);
        assertEq(proxiedAddress, address(0));

        // Test that delegated manager cannot set link rights for the cold wallet
        vm.prank(delegatedManager);
        warm.setLinkRights(hotWallet, expiration);

        // Verify link rights were not changed
        (walletAddress, ) = warm.linkRights(coldWallet);
        assertEq(walletAddress, delegatedManager);
    }

    function testWarmV1Fallback() public view {
        address _hotWallet = 0x128BcA72459f8610Eb6AE25E3af071fC81039163;
        address bayc = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
        uint256 tokenId = 8903;

        // Check that the proxied owner matches the hot wallet from V1
        address proxiedOwner = warm.ownerOf(bayc, tokenId, true);
        assertEq(proxiedOwner, _hotWallet);
    }

    // === Contract Link Tests ===

    function testContractLink() public {
        uint256 expiration = block.timestamp + 1 days;
        
        // Set up link rights
        vm.startPrank(coldWallet);
        warm.setLinkRights(delegatedManager, expiration);
        vm.stopPrank();

        // Delegate contract using delegated manager
        vm.prank(delegatedManager);
        warm.setContractLink(
            coldWallet,
            address(mockERC721),
            contractDelegate,
            expiration
        );

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, 1);

        // Check that contract link works
        address proxiedOwner = warm.ownerOf(address(mockERC721), 1, false);
        assertEq(proxiedOwner, contractDelegate);
    }

    // === Token Link Tests ===

    function testTokenLink() public {
        uint256 expiration = block.timestamp + 1 days;
        
        // Direct token link from cold wallet
        vm.prank(coldWallet);
        warm.setTokenLink(
            coldWallet,
            address(mockERC721),
            1,
            tokenDelegate,
            expiration
        );

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, 1);

        // Check that token link works
        address proxiedOwner = warm.ownerOf(address(mockERC721), 1, false);
        assertEq(proxiedOwner, tokenDelegate);
    }

    // === Link Priority Tests ===

    function testLinkPriority() public {
        uint256 expiration = block.timestamp + 1 days;
        
        vm.startPrank(coldWallet);
        
        // Update setHotWallet call to include coldWallet parameter
        warm.setHotWallet(coldWallet, hotWallet, expiration);
        
        // Rest of the function remains the same
        warm.setContractLink(
            coldWallet,
            address(mockERC721),
            contractDelegate,
            expiration
        );
        
        warm.setTokenLink(
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
        assertEq(warm.ownerOf(address(mockERC721), 1, false), tokenDelegate);
        
        // Token #2 should be delegated to contractDelegate
        assertEq(warm.ownerOf(address(mockERC721), 2, false), contractDelegate);
        
        // Different contract should use wallet-wide link
        MockERC721 differentMock = new MockERC721();
        differentMock.mint(coldWallet, 3);
        assertEq(warm.ownerOf(address(differentMock), 3, false), hotWallet);
    }

    function testExpiredLinks() public {
        uint256 expiration = block.timestamp + 1 days;
        
        vm.startPrank(coldWallet);
        
        // Update setHotWallet call to include coldWallet parameter
        warm.setHotWallet(coldWallet, hotWallet, expiration);
        
        // Rest of the function remains the same
        warm.setContractLink(
            coldWallet,
            address(mockERC721),
            contractDelegate,
            expiration
        );
        
        vm.stopPrank();

        mockERC721.mint(coldWallet, 1);

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 days);

        // Should return original owner when all links are expired
        assertEq(warm.ownerOf(address(mockERC721), 1, false), coldWallet);
    }

    // === Revert Tests ===
    function testRevert_UnauthorizedContractLink() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(Warm.NotAuthorized.selector);
        warm.setContractLink(
            coldWallet,
            address(mockERC721),
            contractDelegate,
            block.timestamp + 1 days
        );
    }

    function testRevert_UnauthorizedTokenLink() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(Warm.NotAuthorized.selector);
        warm.setTokenLink(
            coldWallet,
            address(mockERC721),
            1,
            tokenDelegate,
            block.timestamp + 1 days
        );
    }

    function testRevert_UnauthorizedWalletLink() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(Warm.NotAuthorized.selector);
        warm.setHotWallet(coldWallet, hotWallet, block.timestamp + 1 days);
    }
}
