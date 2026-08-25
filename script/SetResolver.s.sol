// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";

interface IENSRegistry {
    function owner(
        bytes32 node
    ) external view returns (address);
    function resolver(
        bytes32 node
    ) external view returns (address);
    function setResolver(
        bytes32 node,
        address resolver
    ) external;
}

/// @notice Second tx: point an ENS name at a deployed OffchainResolver.
/// @dev Broadcast from the **name owner**. Mainnet Registry:
///      `0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e`.
///      `qntx.eth` node: `namehash("qntx.eth")`.
contract SetResolver is Script {
    function run() external {
        IENSRegistry registry = IENSRegistry(vm.envAddress("ENS_REGISTRY"));
        bytes32 node = vm.envBytes32("ENS_NODE");
        address resolver = vm.envAddress("RESOLVER");

        console.log("registry", address(registry));
        console.log("name owner", registry.owner(node));
        console.log("current resolver", registry.resolver(node));
        console.log("new resolver", resolver);

        vm.startBroadcast();
        registry.setResolver(node, resolver);
        vm.stopBroadcast();

        console.log("resolver after", registry.resolver(node));
    }
}
