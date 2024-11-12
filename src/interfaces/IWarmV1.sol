// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IWarmV1 {
    function ownerOf(address contractAddress, uint256 tokenId) external view returns (address);
    function balanceOf(address contractAddress, address owner) external view returns (uint256);
    function balanceOf(address contractAddress, address owner, uint256 id) external view returns (uint256);
    function balanceOfBatch(address contractAddress, address[] calldata owners, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);
}
