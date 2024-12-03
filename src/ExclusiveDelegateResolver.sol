// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IDelegateRegistry} from "./interfaces/IDelegateRegistry.sol";

/**
 * @title ExclusiveDelegateResolver
 * @author 0xQuit
 * @notice A contract to resolve a single canonical delegated owner for a given ERC721 token
 * @dev This contract is designed to be used in conjunction with a delegate registry to resolve the most specific
 * delegation that matches the rights, with specificity being determined by delegation type in order of ERC721 >
 * CONTRACT > ALL. ERC20 and ERC1155 are not supported. If multiple delegations of the same specificity match the rights,
 * the most recent one is respected. If no delegation matches the rights, global delegations (bytes24(0) are considered,
 * but MUST have an expiration greater than 0 to avoid conflicts with pre-existing delegations.
 * If no delegation matches the rights and there are no empty delegations, the owner is returned.
 * Expirations are supported by extracting a uint40 from the final 40 bits of a given delegation's rights value.
 * If the expiration is past, the delegation is not considered to match the request.
 */
contract ExclusiveDelegateResolver {
    /// @dev The address of the Delegate Registry contract
    address public constant DELEGATE_REGISTRY = 0x00000000000000447e69651d841bD8D104Bed493;

    /// @dev The rights value for a global delegation. These are considered only if no delegation by rights matches the request.
    bytes24 public constant GLOBAL_DELEGATION = bytes24(0);

    /**
     * @notice Gets the owner of an ERC721 token, resolved through delegatexyz if possible
     * @param contractAddress The ERC721 contract address
     * @param tokenId The token ID to check
     * @return owner The owner address or delegated owner if one exists
     * @notice returns the most specific delegation that matches the rights, with specificity being determined
     * by delegation type in order of ERC721 > CONTRACT > ALL. ERC20 and ERC1155 are not supported
     * if multiple delegations of the same specificity match the rights, the most recent one is respected.
     * If no delegation matches the rights, global delegations (bytes24(0) are considered,
     * but MUST have an expiration greater than 0 to avoid conflicts with pre-existing delegations.
     * If no delegation matches the rights and there are no empty delegations, the owner is returned.
     * Expirations are supported by extracting a uint40 from the final 40 bits of a given delegation's rights value.
     * If the expiration is past, the delegation is not considered to match the request.
     */
    function exclusiveOwnerByRights(address contractAddress, uint256 tokenId, bytes24 rights)
        external
        view
        returns (address owner)
    {
        owner = _getOwner(contractAddress, tokenId);

        IDelegateRegistry.Delegation[] memory delegations =
            IDelegateRegistry(DELEGATE_REGISTRY).getOutgoingDelegations(owner);

        IDelegateRegistry.Delegation memory delegationToReturn;

        for (uint256 i = delegations.length; i > 0;) {
            unchecked {
                --i;
            }
            IDelegateRegistry.Delegation memory delegation = delegations[i];

            if (_delegationMatchesRequest(delegation, contractAddress, tokenId, rights)) {
                if (_delegationOutranksCurrent(delegationToReturn, delegation)) {
                    // re-check rights here to ensure global ERC721 type delegations do not get early returned
                    if (
                        delegation.type_ == IDelegateRegistry.DelegationType.ERC721
                            && bytes24(delegation.rights) == rights
                    ) {
                        return delegation.to;
                    }

                    delegationToReturn = delegation;
                }
            }
        }

        return delegationToReturn.to == address(0) ? owner : delegationToReturn.to;
    }

    /**
     * @notice Decodes a rights bytes32 value into its identifier and expiration
     * @param rights The rights bytes32 value
     * @return rightsIdentifier The rights identifier
     * @return expiration The expiration timestamp
     */
    function decodeRightsExpiration(bytes32 rights) public pure returns (bytes24, uint40) {
        bytes24 rightsIdentifier = bytes24(rights);
        uint40 expiration = uint40(uint256(rights));

        return (rightsIdentifier, expiration);
    }

    /**
     * @notice Convenience function to generate a rights bytes32 rights value with an expiration
     * @param rightsIdentifier The rights identifier
     * @param expiration The expiration timestamp
     * @return rights The rights bytes32 value
     */
    function generateRightsWithExpiration(bytes24 rightsIdentifier, uint40 expiration)
        external
        pure
        returns (bytes32)
    {
        uint256 rights = uint256(uint192(rightsIdentifier)) << 64;
        return bytes32(rights | uint256(expiration));
    }

    function _delegationMatchesRequest(
        IDelegateRegistry.Delegation memory delegation,
        address contractAddress,
        uint256 tokenId,
        bytes24 rights
    ) internal view returns (bool) {
        // Extract rights identifier (remaining 192 bits)
        (bytes24 rightsIdentifier, uint40 expiration) = decodeRightsExpiration(delegation.rights);

        if (block.timestamp > expiration) {
            return false;
        } else if (rightsIdentifier != rights && rightsIdentifier != GLOBAL_DELEGATION) {
            return false;
        } else if (delegation.type_ == IDelegateRegistry.DelegationType.ALL) {
            return true;
        } else if (delegation.type_ == IDelegateRegistry.DelegationType.CONTRACT) {
            return delegation.contract_ == contractAddress;
        } else if (delegation.type_ == IDelegateRegistry.DelegationType.ERC721) {
            return delegation.contract_ == contractAddress && delegation.tokenId == tokenId;
        } else {
            return false;
        }
    }

    function _delegationOutranksCurrent(
        IDelegateRegistry.Delegation memory currentDelegation,
        IDelegateRegistry.Delegation memory newDelegation
    ) internal pure returns (bool) {
        bytes24 currentRightsIdentifier = bytes24(currentDelegation.rights);
        bytes24 newRightsIdentifier = bytes24(newDelegation.rights);

        if (currentRightsIdentifier == newRightsIdentifier) {
            return newDelegation.type_ > currentDelegation.type_;
        } else if (currentRightsIdentifier == GLOBAL_DELEGATION) {
            return true;
        } else {
            return false;
        }
    }

    function _getOwner(address contractAddress, uint256 tokenId) internal view returns (address owner) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, 0x6352211e00000000000000000000000000000000000000000000000000000000)
            mstore(add(m, 0x04), tokenId)
            let success := staticcall(gas(), contractAddress, m, 0x24, m, 0x20)
            if iszero(success) {
                mstore(0x00, 0x3204506f) // CallFailed()
                revert(0x1c, 0x04)
            }
            owner := mload(m)
        }
    }
}
