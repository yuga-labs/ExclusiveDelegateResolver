// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721} from "forge/interfaces/IERC721.sol";
import {IWarmV1} from "./interfaces/IWarmV1.sol";

/**
 * @title Warm
 * @notice A contract that enables linking hot wallets to cold wallets for NFT ownership proxying
 * @dev Allows cold wallets to designate a hot wallet that will be recognized as the owner of their NFTs
 */
contract Warm {
    error AlreadyLinked();
    error NoLinkExists();
    error LengthMismatch();
    error InvalidVaultLink();
    error NotAuthorized();
    error FallbackNotAllowed();

    struct WalletLink {
        address walletAddress;
        uint96 expirationTimestamp;
    }

    IWarmV1 public constant _WARM_V1 = IWarmV1(0xC3AA9bc72Bd623168860a1e5c6a4530d3D80456c);

    mapping(address coldWallet => WalletLink) public delegationRights;
    mapping(address coldWallet => WalletLink) public walletDelegations;
    mapping(address coldWallet => mapping(address targetContract => WalletLink)) public contractDelegations;
    mapping(address coldWallet => mapping(address targetContract => mapping(uint256 tokenId => WalletLink))) public
        tokenDelegations;

    event HotWalletSet(address coldWallet, address hotWallet, uint256 expirationTimestamp);
    event DelegationRightsSet(address indexed coldWallet, address indexed newDelegate, uint256 expirationTimestamp);
    event ContractDelegationSet(
        address indexed coldWallet,
        address indexed contractAddress,
        address indexed hotWallet,
        uint256 expirationTimestamp
    );
    event TokenDelegationSet(
        address indexed coldWallet,
        address indexed contractAddress,
        uint256 indexed tokenId,
        address hotWallet,
        uint256 expirationTimestamp
    );

    /**
     * @notice Only allows the cold wallet or a delegate with delegation rights to call the function
     */
    modifier onlyAuthorizedToDelegate(address coldWallet) {
        if (msg.sender != coldWallet) {
            WalletLink memory rights = delegationRights[coldWallet];
            require(
                rights.walletAddress == msg.sender && rights.expirationTimestamp >= block.timestamp, NotAuthorized()
            );
        }
        _;
    }

    /**
     * @dev withV1Fallback can only be true where Warm V1 exists, on Ethereum Mainnet (chainId 1)
     */
    modifier validateV1Fallback(bool withV1Fallback) {
        if (withV1Fallback) {
            require(block.chainid == 1, FallbackNotAllowed());
        }
        _;
    }

    /**
     * @notice Links a hot wallet to the sender's cold wallet
     * @param hotWalletAddress The address of the hot wallet to link. Address(0) to remove the link.
     * @param expirationTimestamp The timestamp after which this link becomes invalid
     * @dev Must be called from the cold wallet or delegated manager
     */
    function setHotWallet(address coldWalletAddress, address hotWalletAddress, uint256 expirationTimestamp)
        external
        onlyAuthorizedToDelegate(coldWalletAddress)
    {
        if (hotWalletAddress == address(0)) {
            delete walletDelegations[coldWalletAddress];
        } else {
            walletDelegations[coldWalletAddress] = WalletLink(hotWalletAddress, uint96(expirationTimestamp));
        }

        emit HotWalletSet(coldWalletAddress, hotWalletAddress, expirationTimestamp);
    }

    /**
     * @notice Sets delegation rights for another wallet to manage the sender's delegations
     * @param delegate The address to grant delegation rights to. Address(0) to remove delegation.
     * @param expirationTimestamp The timestamp after which these delegation rights become invalid
     * @dev Must be called from the cold wallet
     */
    function setDelegationRights(address delegate, uint256 expirationTimestamp)
        external
        onlyAuthorizedToDelegate(msg.sender)
    {
        if (delegate == address(0)) {
            delete delegationRights[msg.sender];
        } else {
            delegationRights[msg.sender] = WalletLink(delegate, uint96(expirationTimestamp));
        }

        emit DelegationRightsSet(msg.sender, delegate, expirationTimestamp);
    }

    /**
     * @notice Sets a hot wallet for a given contract address
     * @param contractAddress The contract address to set the hot wallet for
     * @param hotWallet The hot wallet address. Address(0) to remove the delegation.
     * @param expirationTimestamp The timestamp after which this delegation becomes invalid
     * @dev Must be called from the cold wallet or delegated manager
     */
    function setContractDelegation(
        address coldWallet,
        address contractAddress,
        address hotWallet,
        uint256 expirationTimestamp
    ) external onlyAuthorizedToDelegate(coldWallet) {
        if (hotWallet == address(0)) {
            delete contractDelegations[coldWallet][contractAddress];
        } else {
            contractDelegations[coldWallet][contractAddress] = WalletLink(hotWallet, uint96(expirationTimestamp));
        }

        emit ContractDelegationSet(coldWallet, contractAddress, hotWallet, expirationTimestamp);
    }

    /**
     * @notice Sets a hot wallet for a given token
     * @param coldWallet The cold wallet address to set the hot wallet for
     * @param contractAddress The contract address to set the hot wallet for
     * @param tokenId The token ID to set the hot wallet for
     * @param hotWallet The hot wallet address. Address(0) to remove the delegation.
     * @param expirationTimestamp The timestamp after which this delegation becomes invalid
     * @dev Must be called from the cold wallet or delegated manager
     */
    function setTokenDelegation(
        address coldWallet,
        address contractAddress,
        uint256 tokenId,
        address hotWallet,
        uint256 expirationTimestamp
    ) external onlyAuthorizedToDelegate(coldWallet) {
        if (hotWallet == address(0)) {
            delete tokenDelegations[coldWallet][contractAddress][tokenId];
        } else {
            tokenDelegations[coldWallet][contractAddress][tokenId] = WalletLink(hotWallet, uint96(expirationTimestamp));
        }

        emit TokenDelegationSet(coldWallet, contractAddress, tokenId, hotWallet, expirationTimestamp);
    }

    /**
     * @notice Gets the owner of an ERC721 token, resolving any hot wallet links
     * @param contractAddress The ERC721 contract address
     * @param tokenId The token ID to check
     * @param withV1Fallback Whether to fallback to the warm v1 owner if no delegation is found
     * @dev withV1Fallback is for convenience, be conscious of the gas cost implications
     * @dev withV1Fallback can only be true on Ethereum Mainnet (chainId 1)
     * @return The owner address, resolved through any active wallet links
     */
    function ownerOf(address contractAddress, uint256 tokenId, bool withV1Fallback)
        external
        view
        validateV1Fallback(withV1Fallback)
        returns (address)
    {
        IERC721 erc721Contract = IERC721(contractAddress);
        address owner = erc721Contract.ownerOf(tokenId);

        WalletLink memory tokenLink = tokenDelegations[owner][contractAddress][tokenId];
        if (tokenLink.walletAddress != address(0) && tokenLink.expirationTimestamp >= block.timestamp) {
            return tokenLink.walletAddress;
        }

        // Check contract-specific delegation
        WalletLink memory contractLink = contractDelegations[owner][contractAddress];
        if (contractLink.walletAddress != address(0) && contractLink.expirationTimestamp >= block.timestamp) {
            return contractLink.walletAddress;
        }

        // Check wallet-wide delegation
        WalletLink memory walletLink = walletDelegations[owner];
        if (walletLink.walletAddress != address(0) && walletLink.expirationTimestamp >= block.timestamp) {
            return walletLink.walletAddress;
        }

        return withV1Fallback ? _WARM_V1.ownerOf(contractAddress, tokenId) : owner;
    }
}
