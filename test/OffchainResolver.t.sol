// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IExtendedResolver} from "../src/IExtendedResolver.sol";
import {OffchainResolver} from "../src/OffchainResolver.sol";
import {SignatureVerifier} from "../src/SignatureVerifier.sol";

contract OffchainResolverTest is Test {
    bytes4 internal constant IEXTENDED_RESOLVER_ID = 0x9061b923;
    bytes4 internal constant IERC165_ID = 0x01ffc9a7;
    bytes4 internal constant IADDR_RESOLVER_ID = 0x3b3b57de;
    bytes4 internal constant IERC7996_ID = 0x582de3e7;
    bytes4 internal constant IMULTICALL_SELECTOR = 0xac9650d8;
    bytes4 internal constant IADDRESS_RESOLVER_ID = 0xf1cb7e06;
    bytes4 internal constant ITEXT_RESOLVER_ID = 0x59d1d43c;
    bytes4 internal constant OFFCHAIN_LOOKUP_ID = 0x556f1830;
    bytes4 internal constant RESOLVE_WITH_PROOF_ID = 0xf4d4d2f8;

    string internal constant GATEWAY_URL = "https://ccip.qntx.org/v1";

    OffchainResolver internal resolver;
    address internal owner;
    address internal hot;
    uint256 internal hotPk;
    address internal spare;
    uint256 internal sparePk;

    function setUp() public {
        vm.warp(1_700_000_000);
        owner = makeAddr("owner");
        (hot, hotPk) = makeAddrAndKey("hot");
        (spare, sparePk) = makeAddrAndKey("spare");
        address[] memory signers_ = new address[](2);
        signers_[0] = hot;
        signers_[1] = spare;
        resolver = new OffchainResolver(GATEWAY_URL, signers_, owner);
    }

    function test_constructor_owner_is_argument_not_msg_sender() public {
        address deployer = makeAddr("deployer");
        address owner_ = makeAddr("constructor-owner");
        address[] memory signers_ = new address[](1);
        signers_[0] = hot;
        vm.prank(deployer);
        OffchainResolver r = new OffchainResolver(GATEWAY_URL, signers_, owner_);
        assertEq(r.owner(), owner_);
        assertTrue(r.owner() != deployer);
        assertEq(r.url(), GATEWAY_URL);
        assertTrue(r.signers(hot));
        assertEq(r.getSigners().length, 1);
        assertEq(r.getSigners()[0], hot);
    }

    function test_constructor_rejects_zero_owner() public {
        address[] memory signers_ = new address[](1);
        signers_[0] = hot;
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new OffchainResolver(GATEWAY_URL, signers_, address(0));
    }

    function test_constructor_rejects_empty_url() public {
        address[] memory signers_ = new address[](1);
        signers_[0] = hot;
        vm.expectRevert(OffchainResolver.EmptyURL.selector);
        new OffchainResolver("", signers_, owner);
    }

    function test_constructor_rejects_empty_signers() public {
        vm.expectRevert(OffchainResolver.EmptySigners.selector);
        new OffchainResolver(GATEWAY_URL, new address[](0), owner);
    }

    function test_constructor_rejects_zero_signer() public {
        address[] memory signers_ = new address[](1);
        signers_[0] = address(0);
        vm.expectRevert(OffchainResolver.ZeroAddress.selector);
        new OffchainResolver(GATEWAY_URL, signers_, owner);
    }

    function test_constructor_rejects_duplicate_signers() public {
        address[] memory signers_ = new address[](2);
        signers_[0] = hot;
        signers_[1] = hot;
        vm.expectRevert(OffchainResolver.DuplicateSigner.selector);
        new OffchainResolver(GATEWAY_URL, signers_, owner);
    }

    function test_interface_ids() public pure {
        assertEq(type(IExtendedResolver).interfaceId, IEXTENDED_RESOLVER_ID);
        assertEq(type(IERC165).interfaceId, IERC165_ID);
        assertEq(bytes4(keccak256("resolveWithProof(bytes,bytes)")), RESOLVE_WITH_PROOF_ID);
        assertEq(
            bytes4(keccak256("OffchainLookup(address,string[],bytes,bytes4,bytes)")),
            OFFCHAIN_LOOKUP_ID
        );
        assertEq(IResolverServiceSel.resolve.selector, IEXTENDED_RESOLVER_ID);
    }

    function test_supportsInterface() public view {
        assertTrue(resolver.supportsInterface(IEXTENDED_RESOLVER_ID));
        assertTrue(resolver.supportsInterface(IERC165_ID));
        assertFalse(resolver.supportsInterface(IADDR_RESOLVER_ID));
        assertFalse(resolver.supportsInterface(IERC7996_ID));
        assertFalse(resolver.supportsInterface(IMULTICALL_SELECTOR));
        assertFalse(resolver.supportsInterface(IADDRESS_RESOLVER_ID));
        assertFalse(resolver.supportsInterface(ITEXT_RESOLVER_ID));
        assertFalse(resolver.supportsInterface(bytes4(0xffffffff)));
    }

    function test_resolve_reverts_offchainLookup_fields() public view {
        bytes memory name = _dnsEncode("alice.qntx.eth");
        bytes memory inner = abi.encodeWithSelector(IADDR_RESOLVER_ID, keccak256("node"));

        (
            address sender,
            string[] memory urls,
            bytes memory callData,
            bytes4 callbackFunction,
            bytes memory extraData
        ) = _lookup(name, inner);

        assertEq(sender, address(resolver));
        assertEq(urls.length, 1);
        assertEq(urls[0], GATEWAY_URL);
        assertEq(callbackFunction, resolver.resolveWithProof.selector);
        assertEq(callbackFunction, RESOLVE_WITH_PROOF_ID);
        assertEq(_selector(callData), IEXTENDED_RESOLVER_ID);
        assertEq(callData, abi.encodeWithSelector(IEXTENDED_RESOLVER_ID, name, inner));
        (bytes memory decodedCall, address decodedTarget) = abi.decode(extraData, (bytes, address));
        assertEq(decodedCall, callData);
        assertEq(decodedTarget, address(resolver));
    }

    function test_resolveWithProof_compact64() public view {
        bytes memory result = abi.encode(address(0xA11CE));
        bytes memory out =
            _prove(hotPk, result, uint64(block.timestamp + 300), true, address(resolver));
        assertEq(out, result);
    }

    function test_resolveWithProof_long65() public view {
        bytes memory result = abi.encode(address(0xA11CE));
        bytes memory out =
            _prove(hotPk, result, uint64(block.timestamp + 300), false, address(resolver));
        assertEq(out, result);
    }

    function test_resolveWithProof_spare_signer() public view {
        bytes memory result = abi.encode("ok");
        bytes memory out =
            _prove(sparePk, result, uint64(block.timestamp + 60), true, address(resolver));
        assertEq(out, result);
    }

    function test_resolveWithProof_invalidSigner() public {
        (, uint256 strangerPk) = makeAddrAndKey("stranger");
        bytes memory result = abi.encode(uint256(1));
        (bytes memory response, bytes memory extraData) =
            _pack(strangerPk, result, uint64(block.timestamp + 60), true, address(resolver));
        vm.expectRevert(OffchainResolver.InvalidSigner.selector);
        resolver.resolveWithProof(response, extraData);
    }

    function test_resolveWithProof_expired() public {
        bytes memory result = abi.encode(uint256(1));
        (bytes memory response, bytes memory extraData) =
            _pack(hotPk, result, uint64(block.timestamp - 1), true, address(resolver));
        vm.expectRevert(SignatureVerifier.SignatureExpired.selector);
        resolver.resolveWithProof(response, extraData);
    }

    function test_resolveWithProof_binds_request() public {
        bytes memory result = abi.encode(uint256(1));
        (bytes memory response,) =
            _pack(hotPk, result, uint64(block.timestamp + 60), true, address(resolver));
        bytes memory otherCall =
            abi.encodeWithSelector(IEXTENDED_RESOLVER_ID, _dnsEncode("bob.qntx.eth"), hex"00");
        bytes memory extraData = abi.encode(otherCall, address(resolver));
        vm.expectRevert(OffchainResolver.InvalidSigner.selector);
        resolver.resolveWithProof(response, extraData);
    }

    function test_resolveWithProof_invalidTarget() public {
        address other = makeAddr("other-resolver");
        bytes memory result = abi.encode(uint256(1));
        (bytes memory response, bytes memory extraData) =
            _pack(hotPk, result, uint64(block.timestamp + 60), true, other);
        vm.expectRevert(OffchainResolver.InvalidTarget.selector);
        resolver.resolveWithProof(response, extraData);
    }

    function test_setSigners_revokes_immediately() public {
        bytes memory result = abi.encode(address(0x1));
        uint64 expires = uint64(block.timestamp + 10_000);
        bytes memory stillValid = _prove(hotPk, result, expires, true, address(resolver));
        assertEq(stillValid, result);

        address[] memory next = new address[](1);
        next[0] = spare;
        vm.prank(owner);
        resolver.setSigners(next);

        assertFalse(resolver.signers(hot));
        assertTrue(resolver.signers(spare));
        assertEq(resolver.getSigners().length, 1);
        assertEq(resolver.getSigners()[0], spare);

        (bytes memory response, bytes memory extraData) =
            _pack(hotPk, result, expires, true, address(resolver));
        vm.expectRevert(OffchainResolver.InvalidSigner.selector);
        resolver.resolveWithProof(response, extraData);
    }

    function test_setURL_onlyOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this))
        );
        resolver.setURL("https://example.com");

        vm.prank(owner);
        resolver.setURL("https://example.com/v2");
        assertEq(resolver.url(), "https://example.com/v2");
    }

    function test_setURL_rejects_empty() public {
        vm.prank(owner);
        vm.expectRevert(OffchainResolver.EmptyURL.selector);
        resolver.setURL("");
    }

    function test_setURL_rejects_too_long() public {
        string memory tooLong = string(new bytes(resolver.MAX_URL_LENGTH() + 1));
        vm.prank(owner);
        vm.expectRevert(OffchainResolver.URLTooLong.selector);
        resolver.setURL(tooLong);
    }

    function test_setURL_accepts_max_length() public {
        string memory maxLen = string(new bytes(resolver.MAX_URL_LENGTH()));
        vm.prank(owner);
        resolver.setURL(maxLen);
        assertEq(bytes(resolver.url()).length, resolver.MAX_URL_LENGTH());
    }

    function test_renounceOwnership_disabled() public {
        vm.prank(owner);
        vm.expectRevert(OffchainResolver.RenounceDisabled.selector);
        resolver.renounceOwnership();
        assertEq(resolver.owner(), owner);
    }

    function test_setSigners_onlyOwner() public {
        address[] memory next = new address[](1);
        next[0] = hot;
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this))
        );
        resolver.setSigners(next);
    }

    function test_setSigners_rejects_empty_zero_duplicate() public {
        vm.startPrank(owner);
        vm.expectRevert(OffchainResolver.EmptySigners.selector);
        resolver.setSigners(new address[](0));

        address[] memory z = new address[](1);
        z[0] = address(0);
        vm.expectRevert(OffchainResolver.ZeroAddress.selector);
        resolver.setSigners(z);

        address[] memory d = new address[](2);
        d[0] = spare;
        d[1] = spare;
        vm.expectRevert(OffchainResolver.DuplicateSigner.selector);
        resolver.setSigners(d);
        vm.stopPrank();
    }

    function test_ownable2step_does_not_change_owner_until_accept() public {
        address next = makeAddr("next-owner");
        vm.prank(owner);
        resolver.transferOwnership(next);
        assertEq(resolver.owner(), owner);
        assertEq(resolver.pendingOwner(), next);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this))
        );
        resolver.acceptOwnership();

        vm.prank(next);
        resolver.acceptOwnership();
        assertEq(resolver.owner(), next);
        assertEq(resolver.pendingOwner(), address(0));
    }

    function test_nonOwner_cannot_setSigners_after_transfer_started() public {
        address next = makeAddr("next-owner");
        vm.prank(owner);
        resolver.transferOwnership(next);

        address[] memory n = new address[](1);
        n[0] = spare;
        vm.prank(next);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, next));
        resolver.setSigners(n);
    }

    function _lookup(
        bytes memory name,
        bytes memory data
    )
        internal
        view
        returns (
            address sender,
            string[] memory urls,
            bytes memory callData,
            bytes4 callbackFunction,
            bytes memory extraData
        )
    {
        (bool ok, bytes memory ret) =
            address(resolver).staticcall(abi.encodeCall(OffchainResolver.resolve, (name, data)));
        assertFalse(ok);
        assertGe(ret.length, 4);
        assertEq(_selector(ret), OffchainResolver.OffchainLookup.selector);
        assertEq(_selector(ret), OFFCHAIN_LOOKUP_ID);
        (sender, urls, callData, callbackFunction, extraData) =
            abi.decode(_skipSelector(ret), (address, string[], bytes, bytes4, bytes));
    }

    function _prove(
        uint256 pk,
        bytes memory result,
        uint64 expires,
        bool compact,
        address extraTarget
    ) internal view returns (bytes memory) {
        (bytes memory response, bytes memory extraData) =
            _pack(pk, result, expires, compact, extraTarget);
        return resolver.resolveWithProof(response, extraData);
    }

    function _pack(
        uint256 pk,
        bytes memory result,
        uint64 expires,
        bool compact,
        address extraTarget
    ) internal pure returns (bytes memory response, bytes memory extraData) {
        bytes memory callData = abi.encodeWithSelector(
            IEXTENDED_RESOLVER_ID,
            _dnsEncode("alice.qntx.eth"),
            abi.encodeWithSelector(IADDR_RESOLVER_ID, bytes32(uint256(1)))
        );
        extraData = abi.encode(callData, extraTarget);
        bytes32 hash = keccak256(
            abi.encodePacked(
                hex"1900", extraTarget, expires, keccak256(callData), keccak256(result)
            )
        );
        response = abi.encode(result, expires, _sign(pk, hash, compact));
    }

    function _sign(
        uint256 pk,
        bytes32 hash,
        bool compact
    ) internal pure returns (bytes memory) {
        if (compact) {
            (bytes32 rC, bytes32 vs) = vm.signCompact(pk, hash);
            return abi.encodePacked(rC, vs);
        }
        (uint8 v, bytes32 rL, bytes32 s) = vm.sign(pk, hash);
        return abi.encodePacked(rL, s, bytes1(v));
    }

    function _selector(
        bytes memory data
    ) internal pure returns (bytes4 sel) {
        require(data.length >= 4);
        assembly ("memory-safe") {
            sel := mload(add(data, 32))
        }
    }

    function _skipSelector(
        bytes memory data
    ) internal pure returns (bytes memory out) {
        uint256 n = data.length - 4;
        out = new bytes(n);
        for (uint256 i; i < n; ++i) {
            out[i] = data[i + 4];
        }
    }

    function _dnsEncode(
        string memory name
    ) internal pure returns (bytes memory) {
        bytes memory src = bytes(name);
        bytes memory out = new bytes(src.length + 2);
        uint256 outI = 0;
        uint256 labelStart = 0;
        for (uint256 i; i <= src.length; ++i) {
            if (i == src.length || src[i] == ".") {
                uint256 labelLen = i - labelStart;
                require(labelLen < 64);
                assembly ("memory-safe") {
                    mstore8(add(add(out, 32), outI), labelLen)
                }
                outI++;
                for (uint256 j; j < labelLen; ++j) {
                    out[outI++] = src[labelStart + j];
                }
                labelStart = i + 1;
            }
        }
        out[outI] = 0x00;
        return out;
    }
}

/// @dev Local copy of the gateway selector (same as IResolverService.resolve).
interface IResolverServiceSel {
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view returns (bytes memory, uint64, bytes memory);
}
