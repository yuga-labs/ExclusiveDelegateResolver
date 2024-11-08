// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC721 {
    function ownerOf(uint256 _tokenId) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function balanceOf(address owner, uint256 id) external view returns (uint256);
    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);
}

interface IERC1155 {
    function balanceOf(address owner, uint256 id) external view returns (uint256);
    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);
}

interface IWarmV1 {
    function ownerOf(address contractAddress, uint256 tokenId) external view returns (address);
    function balanceOf(address contractAddress, address owner) external view returns (uint256);
    function balanceOf(address contractAddress, address owner, uint256 id) external view returns (uint256);
    function balanceOfBatch(address contractAddress, address[] calldata owners, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);
}

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
     * @return The owner address, resolved through any active wallet links
     */
    function ownerOf(address contractAddress, uint256 tokenId) external view returns (address) {
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

        return _WARM_V1.ownerOf(contractAddress, tokenId);
    }

    /**
     * @notice Gets the combined ERC721 balance of an address and optionally its linked vault
     * @param contractAddress The ERC721 contract address
     * @param owner The address to check the balance of
     * @param vaultWallet The cold wallet address to include in balance, or address(0) to skip
     * @return The combined balance
     * @dev Reverts if vaultWallet is specified but not linked to owner
     */
    function balanceOf(address contractAddress, address owner, address vaultWallet) external view returns (uint256) {
        if (vaultWallet == address(0)) {
            return _WARM_V1.balanceOf(contractAddress, owner);
        } else {
            IERC721 erc721Contract = IERC721(contractAddress);
            require(walletDelegations[vaultWallet].walletAddress == owner, InvalidVaultLink());

            return erc721Contract.balanceOf(owner) + erc721Contract.balanceOf(vaultWallet);
        }
    }

    function balanceOf(address contractAddress, address owner, uint256 id, address vaultWallet)
        external
        view
        returns (uint256)
    {
        if (vaultWallet == address(0)) {
            return _WARM_V1.balanceOf(contractAddress, owner, id);
        } else {
            IERC1155 erc1155Contract = IERC1155(contractAddress);
            require(walletDelegations[vaultWallet].walletAddress == owner, InvalidVaultLink());

            return erc1155Contract.balanceOf(owner, id) + erc1155Contract.balanceOf(vaultWallet, id);
        }
    }

    function balanceOfBatch(
        address contractAddress,
        address[] calldata owners,
        uint256[] calldata ids,
        address[] calldata vaultWallets
    ) external view returns (uint256[] memory) {
        require(owners.length == ids.length && owners.length == vaultWallets.length, LengthMismatch());

        IERC1155 erc1155Contract = IERC1155(contractAddress);
        uint256[] memory balances = new uint256[](owners.length);

        for (uint256 i = 0; i < owners.length; i++) {
            address vaultWallet = vaultWallets[i];
            address owner = owners[i];
            uint256 id = ids[i];

            if (vaultWallet == address(0)) {
                balances[i] = _WARM_V1.balanceOf(contractAddress, owner, id);
            } else {
                require(walletDelegations[vaultWallet].walletAddress == owner, InvalidVaultLink());

                balances[i] = erc1155Contract.balanceOf(owner, id) + erc1155Contract.balanceOf(vaultWallet, id);
            }
        }

        return balances;
    }
}
