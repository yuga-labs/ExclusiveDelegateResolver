// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDelegateRegistry} from "./interfaces/IDelegateRegistry.sol";

interface IExclusiveDelegateResolver {
    function DELEGATE_REGISTRY() external view returns (address);

    function GLOBAL_DELEGATION() external view returns (bytes24);

    function exclusiveWalletByRights(address vault, bytes24 rights) external view returns (address wallet);

    function delegatedWalletsByRights(address wallet, bytes24 rights)
        external
        view
        returns (address[] memory wallets);

    function exclusiveOwnerByRights(address contractAddress, uint256 tokenId, bytes24 rights)
        external
        view
        returns (address owner);

    function decodeRightsExpiration(bytes32 rights)
        external
        pure
        returns (bytes24 rightsIdentifier, uint40 expiration);

    function generateRightsWithExpiration(bytes24 rightsIdentifier, uint40 expiration)
        external
        pure
        returns (bytes32);
}
