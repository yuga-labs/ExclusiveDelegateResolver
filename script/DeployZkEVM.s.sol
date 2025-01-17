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

contract DeployZkEVM is Script {
    ExclusiveDelegateResolver public resolver;

    function setUp() public {}

    function run(address delegateRegistryAddress, bytes32 salt) public {
        vm.startBroadcast();

        // deploy resolver
        resolver = new ExclusiveDelegateResolver{salt: salt}(delegateRegistryAddress);
        vm.stopBroadcast();

        console2.log("Resolver deployed at:", address(resolver));
    }
}
