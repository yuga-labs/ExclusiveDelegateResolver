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
    bytes24 public constant RIGHTS = bytes24(keccak256("NFT_SHADOW"));
    uint40 public constant FUTURE_EXPIRATION = type(uint40).max;
    uint40 public constant PAST_EXPIRATION = 1;

    bytes32 public rightsWithFutureExpiration;
    bytes32 public rightsWithPastExpiration;

    function setUp() public {
        resolver = new ExclusiveDelegateResolver();
        mockERC721 = new MockERC721();
        mockERC1155 = new MockERC1155();
        delegateRegistry = IDelegateRegistry(0x00000000000000447e69651d841bD8D104Bed493);

        rightsWithFutureExpiration = resolver.generateRightsWithExpiration(RIGHTS, FUTURE_EXPIRATION);
        rightsWithPastExpiration = resolver.generateRightsWithExpiration(RIGHTS, PAST_EXPIRATION);

        hotWallet = makeAddr("hotWallet");
        coldWallet = makeAddr("coldWallet");
    }

    function testERC721Delegation() public {
        uint256 tokenId = 1;

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);

        (bytes24 rightsIdentifier, uint40 expiration) = resolver.decodeRightsExpiration(rightsWithFutureExpiration);
        assertEq(rightsIdentifier, RIGHTS);
        assertEq(expiration, FUTURE_EXPIRATION);

        // Delegate the token
        vm.prank(coldWallet);
        delegateRegistry.delegateERC721(
            hotWallet,
            address(mockERC721),
            tokenId,
            rightsWithFutureExpiration,
            true // enable delegation
        );

        // Verify delegation worked through ExclusiveDelegateResolver contract
        address proxiedOwner = resolver.exclusiveOwnerByRights(address(mockERC721), tokenId, bytes24(RIGHTS));
        assertEq(proxiedOwner, hotWallet);
    }

    function testContractWideDelegation() public {
        uint256 tokenId = 1;

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);

        // Delegate the entire contract
        vm.prank(coldWallet);
        delegateRegistry.delegateContract(hotWallet, address(mockERC721), rightsWithFutureExpiration, true);

        // Verify delegation works for any token in the contract
        address proxiedOwner = resolver.exclusiveOwnerByRights(address(mockERC721), tokenId, bytes24(RIGHTS));
        assertEq(proxiedOwner, hotWallet);
    }

    function testDelegationPriority() public {
        uint256 tokenId = 1;
        address specificDelegate = address(0x3);

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);

        vm.startPrank(coldWallet);

        // Set contract-wide delegation
        delegateRegistry.delegateContract(hotWallet, address(mockERC721), rightsWithFutureExpiration, true);

        // Set token-specific delegation
        delegateRegistry.delegateERC721(
            specificDelegate, address(mockERC721), tokenId, rightsWithFutureExpiration, true
        );

        vm.stopPrank();

        // Token-specific delegation should take priority
        address proxiedOwner = resolver.exclusiveOwnerByRights(address(mockERC721), tokenId, bytes24(RIGHTS));
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
            rightsWithFutureExpiration,
            1 // amount
        );

        vm.stopPrank();

        // Should return coldWallet since ERC1155 delegation is ignored
        address proxiedOwner = resolver.exclusiveOwnerByRights(address(mockERC721), tokenId, bytes24(RIGHTS));
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
            rightsWithFutureExpiration,
            100 // amount
        );

        vm.stopPrank();

        // Should return coldWallet since ERC20 delegation is ignored
        address proxiedOwner = resolver.exclusiveOwnerByRights(address(mockERC721), tokenId, bytes24(RIGHTS));
        assertEq(proxiedOwner, coldWallet);
    }

    function testIgnoresDifferentRights() public {
        uint256 tokenId = 1;
        bytes24 differentRights = bytes24(keccak256("DIFFERENT_RIGHTS"));

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);

        vm.startPrank(coldWallet);

        // Set delegation with different rights
        delegateRegistry.delegateERC721(
            hotWallet,
            address(mockERC721),
            tokenId,
            resolver.generateRightsWithExpiration(differentRights, FUTURE_EXPIRATION),
            true
        );

        vm.stopPrank();

        // Should return coldWallet since rights don't match
        address proxiedOwner = resolver.exclusiveOwnerByRights(address(mockERC721), tokenId, RIGHTS);
        assertEq(proxiedOwner, coldWallet);
    }

    function testRespectsGlobalDelegations() public {
        uint256 tokenId = 1;

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);

        bytes32 globalDelegation = resolver.generateRightsWithExpiration(bytes24(0), FUTURE_EXPIRATION);

        // Set global delegation
        vm.prank(coldWallet);
        delegateRegistry.delegateContract(hotWallet, address(mockERC721), globalDelegation, true);

        // Verify global delegation works
        address proxiedOwner = resolver.exclusiveOwnerByRights(address(mockERC721), tokenId, RIGHTS);
        assertEq(proxiedOwner, hotWallet);
    }

    function testRightsDelegationOutranksGlobalDelegation() public {
        uint256 tokenId = 1;

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);

        // Set rights delegation
        vm.prank(coldWallet);
        delegateRegistry.delegateERC721(hotWallet, address(mockERC721), tokenId, rightsWithFutureExpiration, true);

        // Set global delegation after so that it is newer
        bytes32 globalDelegation = resolver.generateRightsWithExpiration(bytes24(0), FUTURE_EXPIRATION);

        vm.prank(coldWallet);
        delegateRegistry.delegateERC721(makeAddr("GLOBAL_DELEGATE"), address(mockERC721), tokenId, globalDelegation, true);


        // Rights delegation should take priority
        address proxiedOwner = resolver.exclusiveOwnerByRights(address(mockERC721), tokenId, RIGHTS);
        assertEq(proxiedOwner, hotWallet);
    }

    function testIgnoresExpiredDelegations() public {
        uint256 tokenId = 1;

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);

        // Set delegation with expired rights
        vm.prank(coldWallet);
        delegateRegistry.delegateERC721(
            hotWallet, address(mockERC721), tokenId, rightsWithPastExpiration, true
        );

        // Should return coldWallet since delegation has expired
        address proxiedOwner = resolver.exclusiveOwnerByRights(address(mockERC721), tokenId, RIGHTS);
        assertEq(proxiedOwner, coldWallet);
    }

    function testIgnoresDelegationsWithRightsThatDontExplicitlySetExpiry() public {
        uint256 tokenId = 1;

        // Mint token to cold wallet
        mockERC721.mint(coldWallet, tokenId);

        // Set delegation with rights that don't explicitly set expiry
        vm.prank(coldWallet);
        delegateRegistry.delegateERC721(hotWallet, address(mockERC721), tokenId, keccak256("DUMMY_RIGHTS"), true);

        // Should return coldWallet since delegation doesn't match
        address proxiedOwner = resolver.exclusiveOwnerByRights(address(mockERC721), tokenId, RIGHTS);
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
        delegateRegistry.delegateERC721(firstDelegate, address(mockERC721), tokenId, rightsWithFutureExpiration, true);

        // Set second ERC721 delegation for same token
        delegateRegistry.delegateERC721(secondDelegate, address(mockERC721), tokenId, rightsWithFutureExpiration, true);

        vm.stopPrank();

        // Should return second delegate since it was most recent
        address proxiedOwner = resolver.exclusiveOwnerByRights(address(mockERC721), tokenId, bytes24(RIGHTS));
        assertEq(proxiedOwner, secondDelegate);

        // Also test with CONTRACT level delegations
        vm.startPrank(coldWallet);

        // Set first CONTRACT delegation
        delegateRegistry.delegateContract(firstDelegate, address(mockERC721), rightsWithFutureExpiration, true);

        // Set second CONTRACT delegation
        delegateRegistry.delegateContract(secondDelegate, address(mockERC721), rightsWithFutureExpiration, true);

        vm.stopPrank();

        // Should return second delegate
        proxiedOwner = resolver.exclusiveOwnerByRights(address(mockERC721), tokenId, bytes24(RIGHTS));
        assertEq(proxiedOwner, secondDelegate);
    }
}
