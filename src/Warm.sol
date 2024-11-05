// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "solady/auth/OwnableRoles.sol";

interface IERC721 {
    function balanceOf(address _owner) external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
}

interface IERC1155 {
    function balanceOf(address _owner, uint256 _id) external view returns (uint256);
    function balanceOfBatch(address[] calldata _owners, uint256[] calldata _ids)
        external
        view
        returns (uint256[] memory);
}

/**
 * Enables setting a hot wallet as a proxy for your cold wallet, so that you
 * can submit a transaction from your cold wallet once, and other contracts can
 * use this contract to map ownership of an ERC721 or ERC1155 token to your hot wallet.
 *
 * NB: There is a fixed limit to the number of cold wallets that a single hot wallet can
 * point to. This is to avoid a scenario where an attacker could add so many links to a
 * hot wallet that the original cold wallet is no longer able to update their hot wallet
 * address because doing so would run out of gas.
 *
 * Additionally, we provide affordance for locking a hot wallet address so that this
 * attack's surface area can be further reduced.
 *
 * Example:
 *
 *   - Cold wallet 0x123 owns BAYC #456
 *   - Cold wallet 0x123 calls setHotWallet(0xABC)
 *   - Another contract that wants to check for BAYC ownership calls ownerOf(BAYC_ADDRESS, 456);
 *     + This contract calls BAYC's ownerOf(456)
 *     + This contract will see that BAYC #456 is owned by 0x123, which is mapped to 0xABC, and
 *     + returns 0xABC from ownerOf(BAYC_ADDRESS, 456)
 *
 * NB: With balanceOf and balanceOfBatch, this contract will look up the balance of both the cold
 * wallets and the requested wallet, _and return their sum_.
 *
 * To remove a hot wallet, you can either:
 *   - Submit a transaction from the hot wallet you want to remove, renouncing the link, or
 *   - Submit a transaction from the cold wallet, setting its hot wallet to address(0).
 *
 * When setting a link, there is also the option to pass an expirationTimestamp. This value
 * is in seconds since the epoch. Links will only be good until this time. If an indefinite
 * link is desired, passing in type(uint256).max is recommended.
 */
contract Warm is OwnableRoles {
    uint256 public constant MAX_HOT_WALLET_COUNT = 128;
    uint256 public constant NOT_FOUND = type(uint256).max;

    struct WalletLink {
        address walletAddress;
        uint96 expirationTimestamp;
    }

    mapping(address => WalletLink) internal coldWalletToHotWallet;
    mapping(address => WalletLink[]) internal hotWalletToColdWallets;
    mapping(address => bool) internal lockedHotWallets;

    /**
     * expirationTimestamp is kept in seconds since the epoch.
     * In the case where there's no expiration, the expirationTimestamp will be MAX_UINT96.
     */
    event HotWalletChanged(address coldWallet, address from, address to, uint256 expirationTimestamp);

    constructor() {}

    /**
     * Submit a transaction from your cold wallet, thus verifying ownership of the cold wallet.
     *
     * If the hot wallet address is already locked, then the only address that can link to it
     * is the cold wallet that's currently linked to it (e.g. to unlink the hot wallet).
     */
    function setHotWallet(address hotWalletAddress, uint256 expirationTimestamp, bool lockHotWalletAddress) external {
        address coldWalletAddress = msg.sender;

        require(coldWalletAddress != hotWalletAddress, "Can't link to self");
        require(coldWalletToHotWallet[coldWalletAddress].walletAddress != hotWalletAddress, "Already linked");

        if (lockedHotWallets[hotWalletAddress]) {
            require(coldWalletToHotWallet[coldWalletAddress].walletAddress == hotWalletAddress, "Hot wallet locked");
        }

        /**
         * Set the hot wallet address for this cold wallet, and notify.
         */
        address currentHotWalletAddress = coldWalletToHotWallet[coldWalletAddress].walletAddress;
        _setColdWalletToHotWallet(coldWalletAddress, hotWalletAddress, expirationTimestamp);

        /**
         * Update the list of cold wallets this hot wallet points to.
         * If the new hot wallet address is address(0), remove the cold wallet
         * from the hot wallet's list of wallets.
         */
        _removeColdWalletFromHotWallet(coldWalletAddress, currentHotWalletAddress);
        if (hotWalletAddress != address(0)) {
            require(hotWalletToColdWallets[hotWalletAddress].length < MAX_HOT_WALLET_COUNT, "Too many linked wallets");

            _addColdWalletToHotWallet(coldWalletAddress, hotWalletAddress, expirationTimestamp);

            if (lockedHotWallets[hotWalletAddress] != lockHotWalletAddress) {
                lockedHotWallets[hotWalletAddress] = lockHotWalletAddress;
            }
        }
    }

    function removeColdWallet(address coldWallet) external {
        address hotWalletAddress = msg.sender;
        require(_findColdWalletIndex(coldWallet, hotWalletAddress) != NOT_FOUND, "No link exists");

        _removeColdWalletFromHotWallet(coldWallet, hotWalletAddress);
        _setColdWalletToHotWallet(coldWallet, address(0), 0);
    }

    function renounceHotWallet() external {
        address hotWalletAddress = msg.sender;

        address[] memory coldWallets = _getColdWalletAddresses(hotWalletAddress);

        uint256 length = coldWallets.length;
        for (uint256 i = 0; i < length;) {
            address coldWallet = coldWallets[i];

            _setColdWalletToHotWallet(coldWallet, address(0), 0);

            unchecked {
                ++i;
            }
        }

        delete hotWalletToColdWallets[hotWalletAddress];
    }

    function removeExpiredWalletLinks(address hotWalletAddress) external {
        _removeExpiredWalletLinks(hotWalletAddress);
    }

    function getHotWallet(address coldWallet) external view returns (address) {
        return coldWalletToHotWallet[coldWallet].walletAddress;
    }

    function getHotWalletLink(address coldWallet) external view returns (WalletLink memory) {
        return coldWalletToHotWallet[coldWallet];
    }

    function getColdWallets(address hotWallet) external view returns (address[] memory) {
        return _getColdWalletAddresses(hotWallet);
    }

    function getColdWalletLinks(address hotWallet) external view returns (WalletLink[] memory) {
        return hotWalletToColdWallets[hotWallet];
    }

    function isLocked(address hotWallet) external view returns (bool) {
        return lockedHotWallets[hotWallet];
    }

    function setLocked(bool locked) external {
        lockedHotWallets[msg.sender] = locked;
    }

    /**
     * This must be called from the cold wallet, so a once-granted hot wallet can't arbitrarily
     * extend its link forever.
     */
    function setExpirationTimestamp(uint256 expirationTimestamp) external {
        address coldWalletAddress = msg.sender;
        address hotWalletAddress = coldWalletToHotWallet[coldWalletAddress].walletAddress;

        if (hotWalletAddress != address(0)) {
            coldWalletToHotWallet[coldWalletAddress].expirationTimestamp = uint96(expirationTimestamp);

            WalletLink[] memory coldWalletLinks = hotWalletToColdWallets[hotWalletAddress];
            uint256 length = coldWalletLinks.length;

            for (uint256 i = 0; i < length;) {
                if (coldWalletLinks[i].walletAddress == coldWalletAddress) {
                    hotWalletToColdWallets[hotWalletAddress][i].expirationTimestamp = uint96(expirationTimestamp);
                    emit HotWalletChanged(coldWalletAddress, hotWalletAddress, hotWalletAddress, uint96(expirationTimestamp));
                }

                unchecked {
                    ++i;
                }
            }
        }
    }

    /**
     * Return the hot wallet address, if this is a cold wallet.
     *
     * Only returns the hot wallet address if the link hasn't expired.
     */
    function getProxiedAddress(address walletAddress) public view returns (address) {
        WalletLink memory hotWalletLink = coldWalletToHotWallet[walletAddress];

        if (hotWalletLink.walletAddress != address(0) && hotWalletLink.expirationTimestamp >= block.timestamp) {
            return hotWalletLink.walletAddress;
        }

        return walletAddress;
    }

    /**
     * ERC721 Methods
     */
    function balanceOf(address contractAddress, address owner) external view returns (uint256) {
        IERC721 erc721Contract = IERC721(contractAddress);

        address[] memory coldWallets = _getColdWalletAddresses(owner);

        uint256 total = 0;
        uint256 length = coldWallets.length;
        for (uint256 i = 0; i < length;) {
            address coldWallet = coldWallets[i];

            total += erc721Contract.balanceOf(coldWallet);

            unchecked {
                ++i;
            }
        }

        return total + erc721Contract.balanceOf(owner);
    }

    function ownerOf(address contractAddress, uint256 tokenId) external view returns (address) {
        IERC721 erc721Contract = IERC721(contractAddress);

        address owner = erc721Contract.ownerOf(tokenId);

        return getProxiedAddress(owner);
    }

    /**
     * ERC1155 Methods
     */
    function balanceOfBatch(address contractAddress, address[] calldata owners, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory)
    {
        require(owners.length == ids.length, "Mismatched owners and ids");

        IERC1155 erc1155Contract = IERC1155(contractAddress);

        uint256 ownersLength = owners.length;

        uint256[] memory totals = new uint256[](ownersLength);

        for (uint256 i = 0; i < ownersLength;) {
            address owner = owners[i];
            uint256 id = ids[i];

            /**
             * Sum the balance of the owner's wallet with the balance of all of the
             * cold wallets linking to it.
             */
            address[] memory coldWallets = _getColdWalletAddresses(owner);
            uint256 coldWalletsLength = coldWallets.length;

            uint256 allWalletsLength = coldWallets.length;

            /**
             * The ordering of addresses in allWallets is:
             * [
             *   ...coldWallets,
             *   owner
             * ]
             */
            address[] memory allWallets = new address[](allWalletsLength + 1);
            uint256[] memory batchIds = new uint256[](allWalletsLength + 1);

            allWallets[allWalletsLength] = owner;
            batchIds[allWalletsLength] = id;

            for (uint256 j = 0; j < coldWalletsLength;) {
                address coldWallet = coldWallets[j];

                allWallets[j] = coldWallet;
                batchIds[j] = id;

                unchecked {
                    ++j;
                }
            }

            uint256[] memory balances = erc1155Contract.balanceOfBatch(allWallets, batchIds);

            uint256 total = 0;
            uint256 balancesLength = balances.length;
            for (uint256 j = 0; j < balancesLength;) {
                total += balances[j];

                unchecked {
                    ++j;
                }
            }

            totals[i] = total;

            unchecked {
                ++i;
            }
        }

        return totals;
    }

    function balanceOf(address contractAddress, address owner, uint256 tokenId) external view returns (uint256) {
        IERC1155 erc1155Contract = IERC1155(contractAddress);

        address[] memory coldWallets = _getColdWalletAddresses(owner);

        uint256 total = 0;
        uint256 length = coldWallets.length;
        for (uint256 i = 0; i < length;) {
            address coldWallet = coldWallets[i];

            total += erc1155Contract.balanceOf(coldWallet, tokenId);

            unchecked {
                ++i;
            }
        }

        return total + erc1155Contract.balanceOf(owner, tokenId);
    }


    /**
     * Remove expired wallet links, which will reduce the gas cost of future lookups.
     */
    function _removeExpiredWalletLinks(address hotWalletAddress) internal {
        WalletLink[] storage coldWalletLinks = hotWalletToColdWallets[hotWalletAddress];
        uint256 length = coldWalletLinks.length;
        uint256 timestamp = block.timestamp;

        if (length > 0) {
            for (uint256 i = length; i > 0;) {
                uint256 index = i - 1;
                if (coldWalletLinks[index].expirationTimestamp < timestamp) {
                    _setColdWalletToHotWallet(coldWalletLinks[index].walletAddress, address(0), 0);
                    /**
                     * Swap with the last element in the array so we can pop the expired item off.
                     * Index (length - 1) is already the last item, and doesn't need to swap.
                     */
                    if (index < length - 1) {
                        coldWalletLinks[index] = coldWalletLinks[length - 1];
                    }
                    coldWalletLinks.pop();
                    unchecked {
                        --length;
                    }
                }

                unchecked {
                    --i;
                }
            }
        }
    }

    function _removeColdWalletFromHotWallet(address coldWalletAddress, address hotWalletAddress) internal {
        uint256 coldWalletIndex = _findColdWalletIndex(coldWalletAddress, hotWalletAddress);

        if (coldWalletIndex != NOT_FOUND) {
            delete hotWalletToColdWallets[hotWalletAddress][coldWalletIndex];
        }

        _removeExpiredWalletLinks(hotWalletAddress);
    }

    function _addColdWalletToHotWallet(address coldWalletAddress, address hotWalletAddress, uint256 expirationTimestamp)
        internal
    {
        uint256 coldWalletIndex = _findColdWalletIndex(coldWalletAddress, hotWalletAddress);

        if (coldWalletIndex == NOT_FOUND) {
            hotWalletToColdWallets[hotWalletAddress].push(WalletLink(coldWalletAddress, uint96(expirationTimestamp)));
        }
    }

    function _setColdWalletToHotWallet(address coldWalletAddress, address hotWalletAddress, uint256 expirationTimestamp)
        internal
    {
        address currentHotWalletAddress = coldWalletToHotWallet[coldWalletAddress].walletAddress;
        coldWalletToHotWallet[coldWalletAddress] = WalletLink(hotWalletAddress, uint96(expirationTimestamp));

        emit HotWalletChanged(coldWalletAddress, currentHotWalletAddress, hotWalletAddress, expirationTimestamp);
    }

    /**
     * Returns the index of the cold wallet in the list of cold wallets that
     * point to this hot wallet.
     *
     * Returns NOT_FOUND if not found (we don't support storing this many wallet
     * connections, so this should never be an actual cold wallet's index).
     */

    function _findColdWalletIndex(address coldWalletAddress, address hotWalletAddress)
        internal
        view
        returns (uint256)
    {
        WalletLink[] memory coldWalletLinks = hotWalletToColdWallets[hotWalletAddress];
        uint256 length = coldWalletLinks.length;
        for (uint256 i = 0; i < length;) {
            if (coldWalletLinks[i].walletAddress == coldWalletAddress) {
                return i;
            }

            unchecked {
                ++i;
            }
        }

        return NOT_FOUND;
    }

    function _getColdWalletAddresses(address hotWalletAddress)
        internal
        view
        returns (address[] memory coldWalletAddresses)
    {
        WalletLink[] memory walletLinks = hotWalletToColdWallets[hotWalletAddress];

        uint256 length = walletLinks.length;
        uint96 timestamp = uint96(block.timestamp);

        address[] memory addresses = new address[](length);

        bool needsResize = false;
        uint256 index = 0;
        for (uint256 i = 0; i < length;) {
            WalletLink memory walletLink = walletLinks[i];
            if (walletLink.expirationTimestamp >= timestamp) {
                addresses[index] = walletLink.walletAddress;

                unchecked {
                    ++index;
                }
            } else {
                needsResize = true;
            }

            unchecked {
                ++i;
            }
        }

        /**
         * Resize array down to the correct size, if needed
         */
        if (needsResize) {
            address[] memory resizedAddresses = new address[](index);

            for (uint256 i = 0; i < index;) {
                resizedAddresses[i] = addresses[i];

                unchecked {
                    ++i;
                }
            }

            return resizedAddresses;
        }

        return addresses;
    }
}
