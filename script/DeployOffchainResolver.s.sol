// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";

import {OffchainResolver} from "../src/OffchainResolver.sol";

/// @notice Deploys the stub. Does **not** call ENS `setResolver`.
contract DeployOffchainResolver is Script {
    function run() external {
        string memory url = vm.envString("GATEWAY_URL");
        address owner_ = vm.envAddress("OWNER");
        address hot = vm.envAddress("SIGNER_HOT");
        address spare = vm.envAddress("SIGNER_SPARE");

        address[] memory signers_ = new address[](2);
        signers_[0] = hot;
        signers_[1] = spare;

        vm.startBroadcast();
        OffchainResolver resolver = new OffchainResolver(url, signers_, owner_);
        vm.stopBroadcast();

        console.log("OffchainResolver", address(resolver));
        console.log("url", resolver.url());
        console.log("owner", resolver.owner());
        console.log("signer0", resolver.getSigners()[0]);
        console.log("signer1", resolver.getSigners()[1]);
    }
}
