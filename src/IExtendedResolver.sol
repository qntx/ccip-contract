// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title ENSIP-10 wildcard resolver interface
/// @dev Interface id is `bytes4(keccak256("resolve(bytes,bytes)"))` = `0x9061b923`.
interface IExtendedResolver {
    /// @notice Resolves `data` for DNS-encoded `name`.
    /// @param name UTS-46 normalised, DNS wire-encoded name (NUL-terminated).
    /// @param data ABI-encoded inner resolver call (`addr(bytes32)`, `text(bytes32,string)`, …).
    /// @return The ABI-encoded return of the inner function.
    function resolve(
        bytes memory name,
        bytes memory data
    ) external view returns (bytes memory);
}
