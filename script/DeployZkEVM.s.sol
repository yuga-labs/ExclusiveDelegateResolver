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

    address delegateRegistryAddress = 0x0000000059A24EB229eED07Ac44229DB56C5d797;
    bytes32 salt = 0x000000000000000000000000000000000000000052a2c3b1b2e2b6d8b7c40016; // 0x0000000078CC4Cc1C14E27c0fa35ED6E5E58825D

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // deploy resolver
        resolver = new ExclusiveDelegateResolver{salt: salt}(delegateRegistryAddress);
        vm.stopBroadcast();

        console2.log("Resolver deployed at:", address(resolver));
    }
}
