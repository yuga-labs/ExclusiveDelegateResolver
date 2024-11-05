// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/Warm.sol";

contract MockERC721 {
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;

    function mint(address to, uint256 tokenId) public {
        _owners[tokenId] = to;
        _balances[to]++;
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        return _owners[tokenId];
    }

    function balanceOf(address owner) public view returns (uint256) {
        return _balances[owner];
    }
}

contract MockERC1155 {
    mapping(address => mapping(uint256 => uint256)) private _balances;

    function mint(address to, uint256 id, uint256 amount) public {
        _balances[to][id] = amount;
    }

    function balanceOf(address owner, uint256 id) public view returns (uint256) {
        return _balances[owner][id];
    }

    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids) 
        public 
        view 
        returns (uint256[] memory balances) 
    {
        balances = new uint256[](owners.length);
        for (uint256 i = 0; i < owners.length; i++) {
            balances[i] = _balances[owners[i]][ids[i]];
        }
    }
}

contract WarmTest is Test {
    Warm public warm;
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;
    
    address public coldWallet = address(0x1);
    address public hotWallet = address(0x2);
    address public coldWallet2 = address(0x3);
    
    function setUp() public {
        warm = new Warm();
        mockERC721 = new MockERC721();
        mockERC1155 = new MockERC1155();
    }

    function test_SetHotWallet() public {
        vm.prank(coldWallet);
        warm.setHotWallet(hotWallet, type(uint256).max, false);
        
        assertEq(warm.getHotWallet(coldWallet), hotWallet);
    }

    function test_SetHotWalletWithExpiration() public {
        uint256 expirationTime = block.timestamp + 1 days;
        
        vm.prank(coldWallet);
        warm.setHotWallet(hotWallet, expirationTime, false);
        
        assertEq(warm.getHotWallet(coldWallet), hotWallet);
        
        // Warp past expiration
        vm.warp(expirationTime + 1);
        assertEq(warm.getProxiedAddress(coldWallet), coldWallet);
    }

    function test_LockHotWallet() public {
        // Set hot wallet with lock
        vm.prank(coldWallet);
        warm.setHotWallet(hotWallet, type(uint256).max, true);
        
        // Verify it's locked
        assertTrue(warm.isLocked(hotWallet));
        
        // Try to set same hot wallet from different cold wallet (should fail)
        vm.prank(coldWallet2);
        vm.expectRevert(Warm.HotWalletLocked.selector);
        warm.setHotWallet(hotWallet, type(uint256).max, false);
    }

    function test_RemoveColdWallet() public {
        // Set up initial link
        vm.prank(coldWallet);
        warm.setHotWallet(hotWallet, type(uint256).max, false);
        
        // Remove link from hot wallet
        vm.prank(hotWallet);
        warm.removeColdWallet(coldWallet);
        
        assertEq(warm.getHotWallet(coldWallet), address(0));
    }

    function test_RenounceHotWallet() public {
        // Set up multiple links
        vm.prank(coldWallet);
        warm.setHotWallet(hotWallet, type(uint256).max, false);
        
        vm.prank(coldWallet2);
        warm.setHotWallet(hotWallet, type(uint256).max, false);
        
        // Renounce all links
        vm.prank(hotWallet);
        warm.renounceHotWallet();
        
        assertEq(warm.getHotWallet(coldWallet), address(0));
        assertEq(warm.getHotWallet(coldWallet2), address(0));
    }

    function test_ERC721Ownership() public {
        // Mint token to cold wallet
        mockERC721.mint(coldWallet, 1);
        
        // Set hot wallet
        vm.prank(coldWallet);
        warm.setHotWallet(hotWallet, type(uint256).max, false);
        
        // Check ownership through Warm contract
        assertEq(warm.ownerOf(address(mockERC721), 1), hotWallet);
    }

    function test_ERC721Balance() public {
        // Mint tokens to cold wallet
        mockERC721.mint(coldWallet, 1);
        mockERC721.mint(coldWallet, 2);
        
        // Set hot wallet
        vm.prank(coldWallet);
        warm.setHotWallet(hotWallet, type(uint256).max, false);
        
        // Check balance through Warm contract
        assertEq(warm.balanceOf(address(mockERC721), hotWallet), 2);
    }

    function test_ERC1155Balance() public {
        // Mint tokens to cold wallet
        mockERC1155.mint(coldWallet, 1, 100);
        
        // Set hot wallet
        vm.prank(coldWallet);
        warm.setHotWallet(hotWallet, type(uint256).max, false);
        
        // Check balance through Warm contract
        assertEq(warm.balanceOf(address(mockERC1155), hotWallet, 1), 100);
    }

    function test_ERC1155BatchBalance() public {
        // Mint tokens to cold wallet and hot wallet
        mockERC1155.mint(coldWallet, 1, 100);
        mockERC1155.mint(hotWallet, 2, 50);
        
        // Set hot wallet
        vm.prank(coldWallet);
        warm.setHotWallet(hotWallet, type(uint256).max, false);
        
        // Prepare batch query
        address[] memory owners = new address[](2);
        owners[0] = hotWallet;
        owners[1] = hotWallet;
        
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;
        
        // Check batch balances
        uint256[] memory balances = warm.balanceOfBatch(address(mockERC1155), owners, ids);
        assertEq(balances[0], 100); // From cold wallet
        assertEq(balances[1], 50);  // From hot wallet
    }

    function test_MaxHotWalletCount() public {
        // Try to exceed MAX_HOT_WALLET_COUNT
        for (uint256 i = 0; i < warm.MAX_HOT_WALLET_COUNT(); i++) {
            address coldWalletN = address(uint160(0x1000 + i));
            vm.prank(coldWalletN);
            warm.setHotWallet(hotWallet, type(uint256).max, false);
        }
        
        // This should fail
        address oneMoreWallet = address(uint160(0x2000));
        vm.prank(oneMoreWallet);
        vm.expectRevert(Warm.TooManyLinkedWallets.selector);
        warm.setHotWallet(hotWallet, type(uint256).max, false);
    }

    function test_CannotLinkToSelf() public {
        vm.prank(coldWallet);
        vm.expectRevert(Warm.CannotLinkToSelf.selector);
        warm.setHotWallet(coldWallet, type(uint256).max, false);
    }

    function test_AlreadyLinked() public {
        // Set initial link
        vm.prank(coldWallet);
        warm.setHotWallet(hotWallet, type(uint256).max, false);
        
        // Try to set same link again
        vm.prank(coldWallet);
        vm.expectRevert(Warm.AlreadyLinked.selector);
        warm.setHotWallet(hotWallet, type(uint256).max, false);
    }

    function test_NoLinkExists() public {
        vm.prank(hotWallet);
        vm.expectRevert(Warm.NoLinkExists.selector);
        warm.removeColdWallet(coldWallet);
    }

    function test_MismatchedOwnersAndIds() public {
        address[] memory owners = new address[](2);
        uint256[] memory ids = new uint256[](1);
        
        vm.expectRevert(Warm.MismatchedOwnersAndIds.selector);
        warm.balanceOfBatch(address(mockERC1155), owners, ids);
    }

    function test_RemoveExpiredWalletLinks() public {
        // Set up multiple links with different expiration times
        uint256 expiration1 = block.timestamp + 1 days;
        uint256 expiration2 = block.timestamp + 2 days;
        
        vm.prank(coldWallet);
        warm.setHotWallet(hotWallet, expiration1, false);
        
        vm.prank(coldWallet2);
        warm.setHotWallet(hotWallet, expiration2, false);
        
        // Warp past first expiration
        vm.warp(block.timestamp + 1 days + 1);
        
        // Remove expired links
        warm.removeExpiredWalletLinks(hotWallet);
        
        // Check results
        assertEq(warm.getHotWallet(coldWallet), address(0));
        assertEq(warm.getHotWallet(coldWallet2), hotWallet);
    }

    function test_SetExpirationTimestamp() public {
        // Set initial link
        vm.prank(coldWallet);
        warm.setHotWallet(hotWallet, type(uint256).max, false);
        
        // Update expiration
        uint256 newExpiration = block.timestamp + 1 days;
        vm.prank(coldWallet);
        warm.setExpirationTimestamp(newExpiration);
        
        // Verify new expiration
        Warm.WalletLink memory link = warm.getHotWalletLink(coldWallet);
        assertEq(link.expirationTimestamp, newExpiration);
    }

    function testFuzz_SetHotWallet(address fuzzedHotWallet, uint256 expirationTimestamp) public {
        vm.assume(fuzzedHotWallet != address(0));
        vm.assume(fuzzedHotWallet != coldWallet);
        vm.assume(expirationTimestamp > block.timestamp);
        
        vm.prank(coldWallet);
        warm.setHotWallet(fuzzedHotWallet, expirationTimestamp, false);
        
        assertEq(warm.getHotWallet(coldWallet), fuzzedHotWallet);
    }
}
