// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {IExtendedResolver} from "./IExtendedResolver.sol";
import {SignatureVerifier} from "./SignatureVerifier.sol";

/// @dev Gateway ABI imposed by this contract. Not deployed. Selector equals
///      `IExtendedResolver.resolve` (`0x9061b923`) because Solidity selectors ignore returns.
interface IResolverService {
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view returns (bytes memory result, uint64 expires, bytes memory sig);
}

/// @title Offchain ENS resolver (EIP-3668 + ENSIP-10)
/// @notice Single-instance wildcard stub for a namespace such as `qntx.eth`.
/// @dev Always reverts `OffchainLookup` from {resolve}. {resolveWithProof} verifies an
///      authorised gateway signature and returns the inner ABI result. Inner calldata is opaque.
contract OffchainResolver is IExtendedResolver, ERC165, Ownable2Step {
    /// @notice Upper bound on gateway URL storage (EIP-3668 GET URLs are ~2 KiB; v1 is POST).
    uint256 public constant MAX_URL_LENGTH = 2048;

    /// @notice CCIP-Read gateway URL. POST if the template has no `{data}` (EIP-3668).
    string public url;

    /// @notice Whether `account` may sign gateway responses for this resolver.
    mapping(address account => bool authorized) public signers;

    address[] private _signerList;

    event URLUpdated(string url);
    event SignersUpdated(address[] signers);

    /// @notice EIP-3668 offchain lookup. Selector `0x556f1830`.
    error OffchainLookup(
        address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData
    );
    error InvalidSigner();
    error EmptySigners();
    error EmptyURL();
    error URLTooLong();
    error DuplicateSigner();
    error ZeroAddress();
    error InvalidTarget();
    error RenounceDisabled();

    /// @param url_ Gateway URL (not a compile-time constant).
    /// @param signers_ Authorised secp256k1 addresses; at least one, no zeros, no duplicates.
    /// @param owner_ Ownable2Step owner (constructor argument, not implicitly `msg.sender`).
    constructor(
        string memory url_,
        address[] memory signers_,
        address owner_
    ) Ownable(owner_) {
        _setUrl(url_);
        _setSigners(signers_);
    }

    /// @notice Labs-compatible digest helper for offchain signers and tests.
    function makeSignatureHash(
        address target,
        uint64 expires,
        bytes memory request,
        bytes memory result
    ) external pure returns (bytes32) {
        return SignatureVerifier.makeSignatureHash(target, expires, request, result);
    }

    /// @inheritdoc IExtendedResolver
    /// @dev Always reverts `OffchainLookup`. `callData` is `IResolverService.resolve(name, data)`.
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view override returns (bytes memory) {
        bytes memory callData =
            abi.encodeWithSelector(IResolverService.resolve.selector, name, data);
        string[] memory urls = new string[](1);
        urls[0] = url;
        revert OffchainLookup(
            address(this),
            urls,
            callData,
            OffchainResolver.resolveWithProof.selector,
            abi.encode(callData, address(this))
        );
    }

    /// @notice EIP-3668 callback. Verifies gateway `response` against `extraData`.
    /// @param response `abi.encode(bytes result, uint64 expires, bytes sig)`.
    /// @param extraData Unmodified `OffchainLookup.extraData` = `abi.encode(callData, address(this))`.
    /// @return The inner `result` iff the recovered signer is currently authorised.
    function resolveWithProof(
        bytes calldata response,
        bytes calldata extraData
    ) external view returns (bytes memory) {
        (bytes memory request, address target) = abi.decode(extraData, (bytes, address));
        if (target != address(this)) revert InvalidTarget();
        (address signer, bytes memory result) = SignatureVerifier.verify(request, target, response);
        if (!signers[signer]) revert InvalidSigner();
        return result;
    }

    /// @notice Replace the gateway URL. Empty string reverts.
    /// @dev Name is `setURL` (not `setUrl`) to match ccip-tools / SetUrlDialog ABI.
    function setURL(
        string calldata url_
    ) external onlyOwner {
        _setUrl(url_);
    }

    /// @notice Replace the entire signer set. Previous keys are revoked immediately.
    function setSigners(
        address[] calldata signers_
    ) external onlyOwner {
        _setSigners(signers_);
    }

    /// @notice Authorised signer addresses in insertion order of the current set.
    function getSigners() external view returns (address[] memory) {
        return _signerList;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IExtendedResolver).interfaceId
                || super.supportsInterface(interfaceId);
    }

    /// @dev A namespace resolver must always be able to rotate URL and signers.
    function renounceOwnership() public view override onlyOwner {
        revert RenounceDisabled();
    }

    function _setUrl(
        string memory url_
    ) internal {
        uint256 len = bytes(url_).length;
        if (len == 0) revert EmptyURL();
        if (len > MAX_URL_LENGTH) revert URLTooLong();
        url = url_;
        emit URLUpdated(url_);
    }

    function _setSigners(
        address[] memory signers_
    ) internal {
        uint256 n = signers_.length;
        if (n == 0) revert EmptySigners();

        address[] memory old = _signerList;
        uint256 oldLen = old.length;
        for (uint256 i; i < oldLen; ++i) {
            signers[old[i]] = false;
        }
        delete _signerList;

        for (uint256 i; i < n; ++i) {
            address s = signers_[i];
            if (s == address(0)) revert ZeroAddress();
            if (signers[s]) revert DuplicateSigner();
            signers[s] = true;
            _signerList.push(s);
        }
        emit SignersUpdated(signers_);
    }
}
