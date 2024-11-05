// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "solady/auth/OwnableRoles.sol";

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

/**
 * @title Warm
 * @notice A contract that enables linking hot wallets to cold wallets for NFT ownership proxying
 * @dev Allows cold wallets to designate a hot wallet that will be recognized as the owner of their NFTs
 */
contract Warm is OwnableRoles {
    error CannotLinkToSelf();
    error AlreadyLinked();
    error NoLinkExists();
    error LengthMismatch();
    error InvalidVaultLink();
    error NotAuthorized();

    struct WalletLink {
        address walletAddress;
        uint96 expirationTimestamp;
    }

    mapping(address coldWallet => WalletLink) internal coldWalletToHotWallet;
    mapping(address coldWallet => WalletLink) public delegationRights;
    mapping(address coldWallet => mapping(address targetContract => WalletLink)) internal contractDelegations;
    mapping(address coldWallet => mapping(address targetContract => mapping(uint256 tokenId => WalletLink))) internal
        tokenDelegations;

    event HotWalletChanged(address coldWallet, address from, address to, uint256 expirationTimestamp);
    event DelegationRightsChanged(
        address indexed coldWallet,
        address indexed previousDelegate,
        address indexed newDelegate,
        uint256 expirationTimestamp
    );
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
     * @notice Links a hot wallet to the sender's cold wallet
     * @param hotWalletAddress The address of the hot wallet to link
     * @param expirationTimestamp The timestamp after which this link becomes invalid
     * @dev Must be called from the cold wallet. Cannot link to self or re-link existing relationship
     */
    function setHotWallet(address hotWalletAddress, uint256 expirationTimestamp) external {
        address coldWalletAddress = msg.sender;

        require(coldWalletAddress != hotWalletAddress, CannotLinkToSelf());
        require(coldWalletToHotWallet[coldWalletAddress].walletAddress != hotWalletAddress, AlreadyLinked());

        address currentHotWalletAddress = coldWalletToHotWallet[coldWalletAddress].walletAddress;
        coldWalletToHotWallet[coldWalletAddress] = WalletLink(hotWalletAddress, uint96(expirationTimestamp));

        emit HotWalletChanged(coldWalletAddress, currentHotWalletAddress, hotWalletAddress, expirationTimestamp);
    }

    /**
     * @notice Removes the link between a cold wallet and its hot wallet
     * @param coldWallet The cold wallet address to unlink
     * @dev Must be called by the currently linked hot wallet
     */
    function removeColdWallet(address coldWallet) external {
        require(coldWalletToHotWallet[coldWallet].walletAddress == msg.sender, NoLinkExists());

        coldWalletToHotWallet[coldWallet] = WalletLink(address(0), 0);
        emit HotWalletChanged(coldWallet, msg.sender, address(0), 0);
    }

    /**
     * @notice Updates the expiration timestamp for an existing wallet link
     * @param expirationTimestamp The new expiration timestamp
     * @dev Must be called from the cold wallet
     */
    function setExpirationTimestamp(uint256 expirationTimestamp) external {
        address coldWalletAddress = msg.sender;
        address hotWalletAddress = coldWalletToHotWallet[coldWalletAddress].walletAddress;

        if (hotWalletAddress != address(0)) {
            coldWalletToHotWallet[coldWalletAddress].expirationTimestamp = uint96(expirationTimestamp);
            emit HotWalletChanged(coldWalletAddress, hotWalletAddress, hotWalletAddress, expirationTimestamp);
        }
    }

    /**
     * @notice Gets the current active hot wallet for a given address, if any
     * @param walletAddress The address to check
     * @return The hot wallet address if there's an active link, otherwise returns the input address
     */
    function getProxiedAddress(address walletAddress) public view returns (address) {
        return getProxiedAddress(walletAddress, address(0), 0);
    }

    /**
     * @notice Gets the currently linked hot wallet for a cold wallet
     * @param coldWallet The cold wallet address to check
     * @return The linked hot wallet address, or address(0) if none
     */
    function getHotWallet(address coldWallet) external view returns (address) {
        return coldWalletToHotWallet[coldWallet].walletAddress;
    }

    /**
     * @notice Gets the full wallet link details for a cold wallet
     * @param coldWallet The cold wallet address to check
     * @return The WalletLink struct containing the hot wallet address and expiration
     */
    function getHotWalletLink(address coldWallet) external view returns (WalletLink memory) {
        return coldWalletToHotWallet[coldWallet];
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
        return getProxiedAddress(owner, contractAddress, tokenId);
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
        IERC721 erc721Contract = IERC721(contractAddress);
        if (vaultWallet == address(0)) return erc721Contract.balanceOf(owner);

        require(coldWalletToHotWallet[vaultWallet].walletAddress == owner, InvalidVaultLink());

        return erc721Contract.balanceOf(owner) + erc721Contract.balanceOf(vaultWallet);
    }

    function balanceOf(address contractAddress, address owner, uint256 id, address vaultWallet)
        external
        view
        returns (uint256)
    {
        IERC1155 erc1155Contract = IERC1155(contractAddress);
        if (vaultWallet == address(0)) return erc1155Contract.balanceOf(owner, id);

        require(coldWalletToHotWallet[vaultWallet].walletAddress == owner, InvalidVaultLink());

        return erc1155Contract.balanceOf(owner, id) + erc1155Contract.balanceOf(vaultWallet, id);
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
                balances[i] = erc1155Contract.balanceOf(owner, id);
            } else {
                require(coldWalletToHotWallet[vaultWallet].walletAddress == owner, InvalidVaultLink());

                balances[i] = erc1155Contract.balanceOf(owner, id) + erc1155Contract.balanceOf(vaultWallet, id);
            }
        }

        return balances;
    }

    function setDelegationRights(address delegate, uint256 expirationTimestamp) external {
        require(msg.sender != delegate, CannotLinkToSelf());

        address previousDelegate = delegationRights[msg.sender].walletAddress;
        delegationRights[msg.sender] = WalletLink(delegate, uint96(expirationTimestamp));

        emit DelegationRightsChanged(msg.sender, previousDelegate, delegate, expirationTimestamp);
    }

    function _isAuthorizedToDelegate(address coldWallet) internal view returns (bool) {
        if (msg.sender == coldWallet) return true;

        WalletLink memory rights = delegationRights[coldWallet];
        return rights.walletAddress == msg.sender && rights.expirationTimestamp >= block.timestamp;
    }

    function setContractDelegation(
        address coldWallet,
        address contractAddress,
        address hotWallet,
        uint256 expirationTimestamp
    ) external {
        require(_isAuthorizedToDelegate(coldWallet), NotAuthorized());
        require(coldWallet != hotWallet, CannotLinkToSelf());

        contractDelegations[coldWallet][contractAddress] = WalletLink(hotWallet, uint96(expirationTimestamp));

        emit ContractDelegationSet(coldWallet, contractAddress, hotWallet, expirationTimestamp);
    }

    function setTokenDelegation(
        address coldWallet,
        address contractAddress,
        uint256 tokenId,
        address hotWallet,
        uint256 expirationTimestamp
    ) external {
        require(_isAuthorizedToDelegate(coldWallet), NotAuthorized());
        require(coldWallet != hotWallet, CannotLinkToSelf());

        tokenDelegations[coldWallet][contractAddress][tokenId] = WalletLink(hotWallet, uint96(expirationTimestamp));

        emit TokenDelegationSet(coldWallet, contractAddress, tokenId, hotWallet, expirationTimestamp);
    }

    function getProxiedAddress(address walletAddress, address contractAddress, uint256 tokenId)
        public
        view
        returns (address)
    {
        // Check token-specific delegation
        WalletLink memory tokenLink = tokenDelegations[walletAddress][contractAddress][tokenId];
        if (tokenLink.walletAddress != address(0) && tokenLink.expirationTimestamp >= block.timestamp) {
            return tokenLink.walletAddress;
        }

        // Check contract-specific delegation
        WalletLink memory contractLink = contractDelegations[walletAddress][contractAddress];
        if (contractLink.walletAddress != address(0) && contractLink.expirationTimestamp >= block.timestamp) {
            return contractLink.walletAddress;
        }

        // Check wallet-wide delegation
        WalletLink memory walletLink = coldWalletToHotWallet[walletAddress];
        if (walletLink.walletAddress != address(0) && walletLink.expirationTimestamp >= block.timestamp) {
            return walletLink.walletAddress;
        }

        return walletAddress;
    }
}
