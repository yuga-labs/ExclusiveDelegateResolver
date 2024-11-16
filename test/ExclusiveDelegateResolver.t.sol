// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ExclusiveDelegateResolver} from "../src/ExclusiveDelegateResolver.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {IDelegateRegistry} from "../src/interfaces/IDelegateRegistry.sol";

contract ExclusiveDelegateResolverTest is Test {
    ExclusiveDelegateResolver public resolver;
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;
    IDelegateRegistry public delegateRegistry;

    address public coldWallet;
    address public hotWallet;
    bytes32 public constant RIGHTS = keccak256("NFT_SHADOW");

    function setUp() public {
        resolver = new ExclusiveDelegateResolver();
        mockERC721 = new MockERC721();
        mockERC1155 = new MockERC1155();
        delegateRegistry = IDelegateRegistry(0x00000000000000447e69651d841bD8D104Bed493);
        
        hotWallet = makeAddr("hotWallet");
        coldWallet = makeAddr("coldWallet");
    }

    function testERC721Delegation() public {
        uint256 tokenId = 1;
        
        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);
        
        // Delegate the token
        vm.prank(coldWallet);
        delegateRegistry.delegateERC721(
            hotWallet,
            address(mockERC721),
            tokenId,
            RIGHTS,
            true // enable delegation
        );

        // Verify delegation worked through ExclusiveDelegateResolver contract
        address proxiedOwner = resolver.exclusiveOwnerByRights(
            address(mockERC721),
            tokenId,
            RIGHTS
        );
        assertEq(proxiedOwner, hotWallet);
    }

    function testContractWideDelegation() public {
        uint256 tokenId = 1;
        
        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);
        
        // Delegate the entire contract
        vm.prank(coldWallet);
        delegateRegistry.delegateContract(
            hotWallet,
            address(mockERC721),
            RIGHTS,
            true
        );

        // Verify delegation works for any token in the contract
        address proxiedOwner = resolver.exclusiveOwnerByRights(
            address(mockERC721),
            tokenId,
            RIGHTS
        );
        assertEq(proxiedOwner, hotWallet);
    }

    function testDelegationPriority() public {
        uint256 tokenId = 1;
        address specificDelegate = address(0x3);
        
        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);
        
        vm.startPrank(coldWallet);
        
        // Set contract-wide delegation
        delegateRegistry.delegateContract(
            hotWallet,
            address(mockERC721),
            RIGHTS,
            true
        );
        
        // Set token-specific delegation
        delegateRegistry.delegateERC721(
            specificDelegate,
            address(mockERC721),
            tokenId,
            RIGHTS,
            true
        );
        
        vm.stopPrank();

        // Token-specific delegation should take priority
        address proxiedOwner = resolver.exclusiveOwnerByRights(
            address(mockERC721),
            tokenId,
            RIGHTS
        );
        assertEq(proxiedOwner, specificDelegate);
    }

    function testIgnoresERC1155Delegations() public {
        uint256 tokenId = 1;
        address erc1155Delegate = address(0x3);
        
        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);
        
        vm.startPrank(coldWallet);
        
        // Set ERC1155 delegation which should be ignored
        delegateRegistry.delegateERC1155(
            erc1155Delegate,
            address(mockERC721),
            tokenId,
            RIGHTS,
            1 // amount
        );
        
        vm.stopPrank();

        // Should return coldWallet since ERC1155 delegation is ignored
        address proxiedOwner = resolver.exclusiveOwnerByRights(
            address(mockERC721),
            tokenId,
            RIGHTS
        );
        assertEq(proxiedOwner, coldWallet);
    }

    function testIgnoresERC20Delegations() public {
        uint256 tokenId = 1;
        address erc20Delegate = address(0x3);
        
        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);
        
        vm.startPrank(coldWallet);
        
        // Set ERC20 delegation which should be ignored
        delegateRegistry.delegateERC20(
            erc20Delegate,
            address(mockERC721),
            RIGHTS,
            100 // amount
        );
        
        vm.stopPrank();

        // Should return coldWallet since ERC20 delegation is ignored
        address proxiedOwner = resolver.exclusiveOwnerByRights(
            address(mockERC721),
            tokenId,
            RIGHTS
        );
        assertEq(proxiedOwner, coldWallet);
    }

    function testIgnoresDifferentRights() public {
        uint256 tokenId = 1;
        bytes32 differentRights = keccak256("DIFFERENT_RIGHTS");
        
        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);
        
        vm.startPrank(coldWallet);
        
        // Set delegation with different rights
        delegateRegistry.delegateERC721(
            hotWallet,
            address(mockERC721),
            tokenId,
            differentRights,
            true
        );
        
        vm.stopPrank();

        // Should return coldWallet since rights don't match
        address proxiedOwner = resolver.exclusiveOwnerByRights(
            address(mockERC721),
            tokenId,
            RIGHTS
        );
        assertEq(proxiedOwner, coldWallet);
    }

    function testMostRecentDelegationWins() public {
        uint256 tokenId = 1;
        address firstDelegate = makeAddr("firstDelegate");
        address secondDelegate = makeAddr("secondDelegate"); 

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);
        
        vm.startPrank(coldWallet);
        
        // Set first ERC721 delegation
        delegateRegistry.delegateERC721(
            firstDelegate,
            address(mockERC721),
            tokenId,
            RIGHTS,
            true
        );

        // Set second ERC721 delegation for same token
        delegateRegistry.delegateERC721(
            secondDelegate, 
            address(mockERC721),
            tokenId,
            RIGHTS,
            true
        );
        
        vm.stopPrank();

        // Should return second delegate since it was most recent
        address proxiedOwner = resolver.exclusiveOwnerByRights(
            address(mockERC721),
            tokenId,
            RIGHTS
        );
        assertEq(proxiedOwner, secondDelegate);

        // Also test with CONTRACT level delegations
        vm.startPrank(coldWallet);

        // Set first CONTRACT delegation
        delegateRegistry.delegateContract(
            firstDelegate,
            address(mockERC721),
            RIGHTS,
            true
        );

        // Set second CONTRACT delegation
        delegateRegistry.delegateContract(
            secondDelegate,
            address(mockERC721), 
            RIGHTS,
            true
        );

        vm.stopPrank();

        // Should return second delegate
        proxiedOwner = resolver.exclusiveOwnerByRights(
            address(mockERC721),
            tokenId,
            RIGHTS
        );
        assertEq(proxiedOwner, secondDelegate);
    }
}
