// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {SignatureVerifier} from "../src/SignatureVerifier.sol";
import {SignatureVerifierHarness} from "./SignatureVerifierHarness.sol";

contract SignatureVerifierTest is Test {
    SignatureVerifierHarness internal harness;

    uint256 internal signerPk;
    address internal signer;

    function setUp() public {
        vm.warp(1_700_000_000);
        harness = new SignatureVerifierHarness();
        (signer, signerPk) = makeAddrAndKey("gateway-signer");
    }

    function test_makeSignatureHash_matchesPackedPreimage() public view {
        address target = address(0xC0FFEE);
        uint64 expires = 1_700_000_000;
        bytes memory request = hex"9061b923";
        bytes memory result = abi.encode(address(0xBEEF));

        bytes32 expected = keccak256(
            abi.encodePacked(hex"1900", target, expires, keccak256(request), keccak256(result))
        );
        assertEq(harness.makeSignatureHash(target, expires, request, result), expected);
    }

    function test_makeSignatureHash_noChainid() public view {
        bytes32 a = harness.makeSignatureHash(address(this), 1, hex"01", hex"02");
        bytes32 b = keccak256(
            abi.encodePacked(
                hex"1900", address(this), uint64(1), keccak256(hex"01"), keccak256(hex"02")
            )
        );
        assertEq(a, b);
        // Packed layout is 2 + 20 + 8 + 32 + 32 = 94 bytes, not ABI-padded.
        assertEq(
            abi.encodePacked(
                hex"1900", address(this), uint64(1), keccak256(hex"01"), keccak256(hex"02")
            )
            .length,
            94
        );
    }

    function test_recoverSigner_compact64() public view {
        bytes32 hash = keccak256("payload");
        (bytes32 r, bytes32 vs) = vm.signCompact(signerPk, hash);
        address recovered = harness.recoverSigner(hash, abi.encodePacked(r, vs));
        assertEq(recovered, signer);
    }

    function test_recoverSigner_long65() public view {
        bytes32 hash = keccak256("payload");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, hash);
        address recovered = harness.recoverSigner(hash, abi.encodePacked(r, s, bytes1(v)));
        assertEq(recovered, signer);
    }

    function test_compact64_matches_manual_vs_encoding() public view {
        bytes32 hash = keccak256("payload");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, hash);
        bytes32 vs = bytes32(uint256(s) | ((uint256(v) - 27) << 255));
        (bytes32 r2, bytes32 vs2) = vm.signCompact(signerPk, hash);
        assertEq(r, r2);
        assertEq(vs, vs2);
        assertEq(harness.recoverSigner(hash, abi.encodePacked(r, vs)), signer);
    }

    function test_oz_bytes_recover_rejects_compact64() public {
        bytes32 hash = keccak256("payload");
        (bytes32 r, bytes32 vs) = vm.signCompact(signerPk, hash);
        bytes memory compact = abi.encodePacked(r, vs);
        assertEq(compact.length, 64);
        vm.expectRevert(
            abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, uint256(64))
        );
        this.ozRecoverBytes(hash, compact);
    }

    function ozRecoverBytes(
        bytes32 hash,
        bytes calldata sig
    ) external pure returns (address) {
        return ECDSA.recover(hash, sig);
    }

    function test_recoverSigner_rejects_wrong_lengths() public {
        bytes32 hash = keccak256("payload");
        vm.expectRevert(
            abi.encodeWithSelector(SignatureVerifier.InvalidSignatureLength.selector, uint256(0))
        );
        harness.recoverSigner(hash, hex"");

        vm.expectRevert(
            abi.encodeWithSelector(SignatureVerifier.InvalidSignatureLength.selector, uint256(63))
        );
        harness.recoverSigner(hash, new bytes(63));

        vm.expectRevert(
            abi.encodeWithSelector(SignatureVerifier.InvalidSignatureLength.selector, uint256(66))
        );
        harness.recoverSigner(hash, new bytes(66));
    }

    function testFuzz_recoverSigner_rejects_non_64_65(
        uint8 len
    ) public {
        vm.assume(len != 64 && len != 65);
        bytes32 hash = keccak256("payload");
        vm.expectRevert(
            abi.encodeWithSelector(SignatureVerifier.InvalidSignatureLength.selector, uint256(len))
        );
        harness.recoverSigner(hash, new bytes(len));
    }

    function test_verify_compact64_roundTrip() public view {
        (bytes memory extraData, bytes memory response, bytes memory result) =
            _signedResponse(uint64(block.timestamp + 300), true);
        (address recovered, bytes memory got) = harness.verify(extraData, response);
        assertEq(recovered, signer);
        assertEq(got, result);
    }

    function test_verify_long65_roundTrip() public view {
        (bytes memory extraData, bytes memory response, bytes memory result) =
            _signedResponse(uint64(block.timestamp + 300), false);
        (address recovered, bytes memory got) = harness.verify(extraData, response);
        assertEq(recovered, signer);
        assertEq(got, result);
    }

    function test_verify_expired() public {
        (bytes memory extraData, bytes memory response,) =
            _signedResponse(uint64(block.timestamp - 1), true);
        vm.expectRevert(SignatureVerifier.SignatureExpired.selector);
        harness.verify(extraData, response);
    }

    function test_verify_expires_equal_timestamp_ok() public view {
        (bytes memory extraData, bytes memory response, bytes memory result) =
            _signedResponse(uint64(block.timestamp), true);
        (, bytes memory got) = harness.verify(extraData, response);
        assertEq(got, result);
    }

    function test_verify_highS_rejected() public {
        address target = address(this);
        bytes memory request = hex"aabb";
        bytes memory result = hex"cc";
        uint64 expires = uint64(block.timestamp + 60);
        bytes32 hash = harness.makeSignatureHash(target, expires, request, result);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, hash);
        // Flip to a high-s value (n - s) which OZ 5.4 rejects on both paths.
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 highS = bytes32(n - uint256(s));
        uint8 flippedV = v == 27 ? 28 : 27;
        bytes memory sig = abi.encodePacked(r, highS, bytes1(flippedV));

        bytes memory extraData = abi.encode(request, target);
        bytes memory response = abi.encode(result, expires, sig);
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, highS));
        harness.verify(extraData, response);
    }

    function _signedResponse(
        uint64 expires,
        bool compact
    ) internal view returns (bytes memory extraData, bytes memory response, bytes memory result) {
        address target = address(0x1111);
        bytes memory request = abi.encodeWithSelector(bytes4(0x9061b923), hex"00", hex"01");
        result = abi.encode(address(0x2222));
        extraData = abi.encode(request, target);
        bytes32 hash = harness.makeSignatureHash(target, expires, request, result);
        bytes memory sig;
        if (compact) {
            (bytes32 r, bytes32 vs) = vm.signCompact(signerPk, hash);
            sig = abi.encodePacked(r, vs);
        } else {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, hash);
            sig = abi.encodePacked(r, s, bytes1(v));
        }
        response = abi.encode(result, expires, sig);
    }
}
