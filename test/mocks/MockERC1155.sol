// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockERC1155 {
    mapping(address => mapping(uint256 => uint256)) private _balances;

    function mint(address to, uint256 id, uint256 amount) external {
        _balances[to][id] += amount;
    }

    function balanceOf(address owner, uint256 id) external view returns (uint256) {
        return _balances[owner][id];
    }

    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory)
    {
        require(owners.length == ids.length, "Length mismatch");

        uint256[] memory balances = new uint256[](owners.length);
        for (uint256 i = 0; i < owners.length; i++) {
            balances[i] = _balances[owners[i]][ids[i]];
        }

        return balances;
    }
} 