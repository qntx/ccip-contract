// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {SignatureVerifier} from "../src/SignatureVerifier.sol";

/// @dev Exposes internal library methods for unit tests.
contract SignatureVerifierHarness {
    function makeSignatureHash(
        address target,
        uint64 expires,
        bytes memory request,
        bytes memory result
    ) external pure returns (bytes32) {
        return SignatureVerifier.makeSignatureHash(target, expires, request, result);
    }

    function verify(
        bytes calldata extraData,
        bytes calldata response
    ) external view returns (address signer, bytes memory result) {
        return SignatureVerifier.verify(extraData, response);
    }

    function recoverSigner(
        bytes32 hash,
        bytes calldata sig
    ) external pure returns (address) {
        return SignatureVerifier.recoverSigner(hash, sig);
    }
}
