// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title ENS Labs-compatible CCIP-Read signature verifier
/// @notice Hash is EIP-191 version `0x00` over the resolver, expiry, request, and result.
/// @dev Byte-identical to ensdomains/offchain-resolver `SignatureVerifier.makeSignatureHash`.
///      OpenZeppelin 5.x `recover(bytes32,bytes)` rejects 64-byte ERC-2098 compact signatures
///      (accepted by OZ 4.4 in the Labs lockfile). Recover must branch:
///      65 → {ECDSA-recover}(hash, sig); 64 → {ECDSA-recover}(hash, r, vs).
library SignatureVerifier {
    error SignatureExpired();
    error InvalidSignatureLength(uint256 length);

    /// @notice Digest signed by the gateway (`signDigest` / raw hash; not `personal_sign`).
    /// @dev `keccak256(abi.encodePacked(hex"1900", target, expires, keccak256(request), keccak256(result)))`.
    ///      No `chainid`. `target` is the 20-byte resolver address, not ABI-padded.
    function makeSignatureHash(
        address target,
        uint64 expires,
        bytes memory request,
        bytes memory result
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(hex"1900", target, expires, keccak256(request), keccak256(result))
        );
    }

    /// @notice Recovers the signer of an `IResolverService` response.
    /// @param extraData `abi.encode(callData, target)` from `OffchainLookup.extraData`.
    ///         `target` is the hash target, **not** implicitly `address(this)`.
    /// @param response `abi.encode(bytes result, uint64 expires, bytes sig)`.
    /// @return signer Recovered address (not yet authorised; caller checks the signer set).
    /// @return result Inner ABI-encoded record.
    function verify(
        bytes calldata extraData,
        bytes calldata response
    ) internal view returns (address signer, bytes memory result) {
        (bytes memory request, address target) = abi.decode(extraData, (bytes, address));
        return verify(request, target, response);
    }

    /// @notice Same as {verify} after `extraData` has been decoded (single ABI decode at the caller).
    /// @dev Expiry is checked before `ecrecover`.
    function verify(
        bytes memory request,
        address target,
        bytes calldata response
    ) internal view returns (address signer, bytes memory result) {
        uint64 expires;
        bytes memory sig;
        (result, expires, sig) = abi.decode(response, (bytes, uint64, bytes));
        if (expires < block.timestamp) revert SignatureExpired();
        signer = recoverSigner(makeSignatureHash(target, expires, request, result), sig);
    }

    /// @notice Recovers `hash` from a 64-byte compact (`r ‖ vs`) or 65-byte (`r ‖ s ‖ v`) signature.
    function recoverSigner(
        bytes32 hash,
        bytes memory sig
    ) internal pure returns (address) {
        uint256 length = sig.length;
        if (length == 65) {
            return ECDSA.recover(hash, sig);
        }
        if (length == 64) {
            bytes32 r;
            bytes32 vs;
            assembly ("memory-safe") {
                r := mload(add(sig, 0x20))
                vs := mload(add(sig, 0x40))
            }
            return ECDSA.recover(hash, r, vs);
        }
        revert InvalidSignatureLength(length);
    }
}
