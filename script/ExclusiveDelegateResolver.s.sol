// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console, console2} from "forge-std/Script.sol";
import {ExclusiveDelegateResolver} from "../src/ExclusiveDelegateResolver.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address deploymentAddress);
    function findCreate2Address(bytes32 salt, bytes calldata initCode)
        external
        view
        returns (address deploymentAddress);
    function findCreate2AddressViaHash(bytes32 salt, bytes32 initCodeHash)
        external
        view
        returns (address deploymentAddress);
}

contract DeployScript is Script {
    ExclusiveDelegateResolver public resolver;

    bytes32 salt = 0x0000000000000000000000000000000000000000eba2385ed09a4d00eb5ed4e5;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // deploy resolver
        bytes memory resolverInitCode = abi.encodePacked(
            type(ExclusiveDelegateResolver).creationCode
        );
        resolver = ExclusiveDelegateResolver(ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497).safeCreate2(salt, resolverInitCode));
        vm.stopBroadcast();

        console2.logBytes32(keccak256(resolverInitCode));
    }
}
