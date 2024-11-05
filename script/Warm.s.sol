// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Warm} from "../src/Warm.sol";

contract WarmScript is Script {
    Warm public warm;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        warm = new Warm();

        vm.stopBroadcast();
    }
}
