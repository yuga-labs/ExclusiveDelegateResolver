// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDelegateRegistry} from "./interfaces/IDelegateRegistry.sol";

/**
 * @title ExclusiveDelegateResolver
 * @author 0xQuit
 * @notice A contract to resolve a single canonical delegated owner for a given ERC721 token
 * @dev This contract is designed to be used in conjunction with a delegate registry to resolve the most specific
 * delegation that matches the rights, with specificity being determined by delegation type in order of ERC721 >
 * CONTRACT > ALL. ERC20 and ERC1155 are not supported. If multiple delegations of the same specificity match the rights,
 * the most recent one is respected
 */
contract ExclusiveDelegateResolver {
    /// @dev The address of the Delegate Registry contract
    address public constant DELEGATE_REGISTRY = 0x00000000000000447e69651d841bD8D104Bed493;

    /**
     * @notice Gets the owner of an ERC721 token, resolving any hot wallet links
     * @param contractAddress The ERC721 contract address
     * @param tokenId The token ID to check
     * @return owner The owner address, resolved through any active wallet links
     * @notice returns the most specific delegation that matches the rights, with specificity being determined
     * by delegation type in order of ERC721 > CONTRACT > ALL. ERC20 and ERC1155 are not supported
     * if multiple delegations of the same specificity match the rights, the most recent one is respected
     */
    function exclusiveOwnerByRights(address contractAddress, uint256 tokenId, bytes32 rights)
        external
        view
        returns (address owner)
    {
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

        // check delegate registry for outgoing delegations
        IDelegateRegistry.Delegation[] memory delegations =
            IDelegateRegistry(DELEGATE_REGISTRY).getOutgoingDelegations(owner);

        IDelegateRegistry.Delegation memory delegationToReturn;

        for (uint256 i = delegations.length; i > 0;) {
            unchecked {
                --i;
            }
            IDelegateRegistry.Delegation memory delegation = delegations[i];

            if (_delegationMatchesRequest(delegation, contractAddress, tokenId, rights)) {
                if (delegation.type_ > delegationToReturn.type_) {
                    if (
                        delegation.type_ == IDelegateRegistry.DelegationType.ERC721
                            || delegation.type_ == IDelegateRegistry.DelegationType.ERC1155
                            || delegation.type_ == IDelegateRegistry.DelegationType.ERC20
                    ) {
                        return delegation.to;
                    }

                    delegationToReturn = delegation;
                }
            }
        }

        return delegationToReturn.to == address(0) ? owner : delegationToReturn.to;
    }

    function _delegationMatchesRequest(
        IDelegateRegistry.Delegation memory delegation,
        address contractAddress,
        uint256 tokenId,
        bytes32 rights
    ) internal pure returns (bool) {
        if (delegation.rights != rights) {
            return false;
        }

        if (delegation.type_ == IDelegateRegistry.DelegationType.ALL) {
            return true;
        }

        if (delegation.type_ == IDelegateRegistry.DelegationType.CONTRACT) {
            return delegation.contract_ == contractAddress;
        }

        if (delegation.type_ == IDelegateRegistry.DelegationType.ERC721) {
            return delegation.contract_ == contractAddress && delegation.tokenId == tokenId;
        }

        return false;
    }
}
