// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Warm
 * @notice A contract that enables linking hot wallets to cold wallets for NFT ownership proxying
 * @dev Allows cold wallets to designate a hot wallet that will be recognized as the owner of their NFTs
 */
contract Warm {
    /// @dev Thrown when an unauthorized address attempts an operation
    error NotAuthorized();

    /// @dev Thrown when an invalid expiration timestamp is provided
    error InvalidExpiry();

    /// @dev Thrown when a low-level call fails
    error CallFailed();

    /// @dev Struct to represent a wallet link with an expiration
    struct WalletLink {
        /// @dev The address of the linked wallet
        address walletAddress;
        /// @dev The timestamp when the link expires
        uint96 expirationTimestamp;
    }

    /// @dev The address of the Warm V1 contract
    address public constant _WARM_V1 = 0xC3AA9bc72Bd623168860a1e5c6a4530d3D80456c;

    /// @dev Mapping of cold wallets to their link rights.
    mapping(address coldWallet => WalletLink) public linkRights;

    /// @dev Mapping of cold wallets to their wallet-wide links. Only respected if other link types are not set for given token.
    mapping(address coldWallet => WalletLink) public walletLinks;

    /// @dev Mapping of cold wallets to their contract-specific links. Respected over wallet-wide links.
    mapping(address coldWallet => mapping(address targetContract => WalletLink)) public contractLinks;

    /// @dev Mapping of cold wallets to their token-specific links. Respected over all other link types.
    mapping(address coldWallet => mapping(address targetContract => mapping(uint256 tokenId => WalletLink))) public
        tokenLinks;

    /// @dev Emitted when a hot wallet is set for a cold wallet
    /// @param coldWallet The address of the cold wallet
    /// @param hotWallet The address of the hot wallet
    /// @param expirationTimestamp The timestamp when the link expires
    event HotWalletSet(address coldWallet, address hotWallet, uint256 expirationTimestamp);

    /// @dev Emitted when link rights are set
    /// @param coldWallet The address of the cold wallet
    /// @param newDelegate The address of the new delegate
    /// @param expirationTimestamp The timestamp when the link rights expire
    event LinkRightsSet(address indexed coldWallet, address indexed newDelegate, uint256 expirationTimestamp);

    /// @dev Emitted when a contract-wide link is set
    /// @param coldWallet The address of the cold wallet
    /// @param contractAddress The address of the target contract
    /// @param hotWallet The address of the hot wallet
    /// @param expirationTimestamp The timestamp when the link expires
    event ContractLinkSet(
        address indexed coldWallet,
        address indexed contractAddress,
        address indexed hotWallet,
        uint256 expirationTimestamp
    );

    /// @notice Emitted when a token-specific link is set
    /// @param coldWallet The address of the cold wallet
    /// @param contractAddress The address of the target contract
    /// @param tokenId The ID of the specific token
    /// @param hotWallet The address of the hot wallet
    /// @param expirationTimestamp The timestamp when the link expires
    event TokenLinkSet(
        address indexed coldWallet,
        address indexed contractAddress,
        uint256 indexed tokenId,
        address hotWallet,
        uint256 expirationTimestamp
    );

    /**
     * @notice Only allows the cold wallet or a delegate with link rights to call the function
     */
    modifier onlyAuthorizedToLink(address coldWallet) {
        if (msg.sender != coldWallet) {
            WalletLink memory rights = linkRights[coldWallet];
            require(
                rights.walletAddress == msg.sender && rights.expirationTimestamp >= block.timestamp, NotAuthorized()
            );
        }
        _;
    }

    /**
     * @notice Sets link rights for another wallet to manage the sender's links
     * @param delegate The address to grant link rights to. Address(0) to remove link.
     * @param expirationTimestamp The timestamp after which these link rights become invalid
     * @dev Must be called from the cold wallet
     */
    function setLinkRights(address delegate, uint256 expirationTimestamp)
        external
        onlyAuthorizedToLink(msg.sender)
    {
        if (block.timestamp > expirationTimestamp) revert InvalidExpiry();

        if (delegate == address(0)) {
            delete linkRights[msg.sender];
        } else {
            linkRights[msg.sender] = WalletLink(delegate, uint96(expirationTimestamp));
        }

        emit LinkRightsSet(msg.sender, delegate, expirationTimestamp);
    }

    /**
     * @notice Links a hot wallet to the sender's cold wallet
     * @param hotWalletAddress The address of the hot wallet to link. Address(0) to remove the link.
     * @param expirationTimestamp The timestamp after which this link becomes invalid
     * @dev Must be called from the cold wallet or delegated manager
     */
    function setHotWallet(address coldWalletAddress, address hotWalletAddress, uint256 expirationTimestamp)
        external
        onlyAuthorizedToLink(coldWalletAddress)
    {
        if (block.timestamp > expirationTimestamp) revert InvalidExpiry();

        if (hotWalletAddress == address(0)) {
            delete walletLinks[coldWalletAddress];
        } else {
            walletLinks[coldWalletAddress] = WalletLink(hotWalletAddress, uint96(expirationTimestamp));
        }

        emit HotWalletSet(coldWalletAddress, hotWalletAddress, expirationTimestamp);
    }

    /**
     * @notice Sets a hot wallet for a given contract address
     * @param contractAddress The contract address to set the hot wallet for
     * @param hotWallet The hot wallet address. Address(0) to remove the link.
     * @param expirationTimestamp The timestamp after which this link becomes invalid
     * @dev Must be called from the cold wallet or delegated manager
     */
    function setContractLink(
        address coldWallet,
        address contractAddress,
        address hotWallet,
        uint256 expirationTimestamp
    ) external onlyAuthorizedToLink(coldWallet) {
        if (block.timestamp > expirationTimestamp) revert InvalidExpiry();

        if (hotWallet == address(0)) {
            delete contractLinks[coldWallet][contractAddress];
        } else {
            contractLinks[coldWallet][contractAddress] = WalletLink(hotWallet, uint96(expirationTimestamp));
        }

        emit ContractLinkSet(coldWallet, contractAddress, hotWallet, expirationTimestamp);
    }

    /**
     * @notice Sets a hot wallet for a given token
     * @param coldWallet The cold wallet address to set the hot wallet for
     * @param contractAddress The contract address to set the hot wallet for
     * @param tokenId The token ID to set the hot wallet for
     * @param hotWallet The hot wallet address. Address(0) to remove the link.
     * @param expirationTimestamp The timestamp after which this link becomes invalid
     * @dev Must be called from the cold wallet or delegated manager
     */
    function setTokenLink(
        address coldWallet,
        address contractAddress,
        uint256 tokenId,
        address hotWallet,
        uint256 expirationTimestamp
    ) external onlyAuthorizedToLink(coldWallet) {
        if (block.timestamp > expirationTimestamp) revert InvalidExpiry();

        if (hotWallet == address(0)) {
            delete tokenLinks[coldWallet][contractAddress][tokenId];
        } else {
            tokenLinks[coldWallet][contractAddress][tokenId] = WalletLink(hotWallet, uint96(expirationTimestamp));
        }

        emit TokenLinkSet(coldWallet, contractAddress, tokenId, hotWallet, expirationTimestamp);
    }

    /**
     * @notice Gets the owner of an ERC721 token, resolving any hot wallet links
     * @param contractAddress The ERC721 contract address
     * @param tokenId The token ID to check
     * @param withV1Fallback Whether to fallback to the warm v1 owner if no link is found
     * @dev withV1Fallback is for convenience, be conscious of the gas cost implications
     * @dev withV1Fallback can only be true on Ethereum Mainnet (chainId 1), it will be silently ignored otherwise
     * @return The owner address, resolved through any active wallet links
     */
    function ownerOf(address contractAddress, uint256 tokenId, bool withV1Fallback) external view returns (address) {
        address owner;
        /// @solidity memory-safe-assembly
        assembly {
            // Set up memory for the call
            let m := mload(0x40)
            // Store ownerOf(uint256) selector
            mstore(m, 0x6352211e00000000000000000000000000000000000000000000000000000000)
            // Store tokenId argument
            mstore(add(m, 0x04), tokenId)
            // Make the staticcall
            let success := staticcall(gas(), contractAddress, m, 0x24, m, 0x20)
            // Check if call was successful
            if iszero(success) {
                mstore(0x00, 0x3204506f) // CallFailed()
                revert(0x1c, 0x04)
            }
            // Load the returned owner address directly
            owner := mload(m)
        }

        // Check token-specific link
        WalletLink memory tokenLink = tokenLinks[owner][contractAddress][tokenId];
        if (tokenLink.walletAddress != address(0) && tokenLink.expirationTimestamp >= block.timestamp) {
            return tokenLink.walletAddress;
        }

        // Check contract-specific link
        WalletLink memory contractLink = contractLinks[owner][contractAddress];
        if (contractLink.walletAddress != address(0) && contractLink.expirationTimestamp >= block.timestamp) {
            return contractLink.walletAddress;
        }

        // Check wallet-wide link
        WalletLink memory walletLink = walletLinks[owner];
        if (walletLink.walletAddress != address(0) && walletLink.expirationTimestamp >= block.timestamp) {
            return walletLink.walletAddress;
        }

        /// @solidity memory-safe-assembly
        assembly {
            // Only proceed with V1 fallback if withV1Fallback is true and chainid is 1
            if and(withV1Fallback, eq(chainid(), 1)) {
                // Set up memory for the call
                let m := mload(0x40)
                // Store ownerOf(address,uint256) selector
                mstore(m, 0x1f29d2dc00000000000000000000000000000000000000000000000000000000)
                // Store contractAddress argument
                mstore(add(m, 0x04), contractAddress)
                // Store tokenId argument
                mstore(add(m, 0x24), tokenId)
                // Make the staticcall to _WARM_V1
                let success := staticcall(gas(), _WARM_V1, m, 0x44, m, 0x20)
                // If call succeeded, return the V1 owner
                if success { return(m, 0x20) }
            }
            // Return the original owner if V1 fallback not used or failed
            mstore(0x00, owner)
            return(0x00, 0x20)
        }
    }
}
