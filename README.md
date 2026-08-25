<!-- markdownlint-disable MD033 MD041 MD001 -->

<div align="center">

# CCIP Contract

### ENS Offchain Resolver Contracts (CCIP-Read)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.36-363636?logo=solidity)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C)](https://book.getfoundry.sh/)

An ENS resolver that serves records from off-chain storage using [EIP-3668: CCIP Read](https://eips.ethereum.org/EIPS/eip-3668) and [ENSIP-10: Wildcard Resolution](https://docs.ens.domains/ensip/10).

</div>

## Overview

This is a **uni.eth-style** namespace resolver for `qntx.eth`: one `OffchainResolver` instance, gasless subnames (`alice.qntx.eth`) stored offchain, users never deploy a contract.

`resolve()` always reverts `OffchainLookup`. A CCIP-Read client fetches a signed answer from the QuantX gateway. `resolveWithProof` recovers the signer (64-byte ERC-2098 compact **or** 65-byte `r,s,v`) and returns the inner ABI result iff the signer is in the live set and `expires >= block.timestamp`.

**Deploying the stub does not point `qntx.eth` at it.** That takes a second transaction from the ENS name owner (`Registry.setResolver`).

Gateway, claim API, and database are **out of this repo**. The contract only verifies signatures.

## Build

```bash
forge fmt --check
forge build --sizes
forge test -vvv
```

Solidity **0.8.36**, `evm_version = "osaka"` (Fusaka / current mainnet default), OpenZeppelin **5.7.0**.

## Contracts

| File | Role |
| --- | --- |
| `src/IExtendedResolver.sol` | ENSIP-10 `resolve(bytes,bytes)` (`0x9061b923`) |
| `src/SignatureVerifier.sol` | Labs hash `keccak256(0x1900 ‖ target ‖ expires ‖ keccak256(request) ‖ keccak256(result))` + OZ 5.4 64/65 recover |
| `src/OffchainResolver.sol` | Stub + Ownable2Step `setURL` / replacing `setSigners`. Defines `IResolverService` (gateway ABI only) |

`supportsInterface` is true only for `IExtendedResolver` and IERC165. It is **false** for `IAddrResolver` (`0x3b3b57de`) and IERC7996 (`0x582de3e7`).

`setURL` rejects empty and URLs longer than `MAX_URL_LENGTH` (2048). `renounceOwnership` is disabled so URL/signers can always be rotated. Ownable2Step still applies.

Signature hash is **not** `personal_sign`. Gateway must `signDigest` that digest. Compact 64-byte sigs (`r ‖ vs`) are required because ENS Labs gateways emit them; OZ 5.4 `recover(bytes32,bytes)` rejects length 64.

## Two transactions (mainnet)

Live `qntx.eth` (2026-08-24): unwrapped, owner EOA `0xE350Ef4E8557a3e2a24D11327d9F25B382Ac93Cb`, resolver `0xF29100983E058B709F3D539b0c765937B804AC15` (rollback target; **not** PublicResolver `0x231b0Ee1…`). Parent `addr` is that EOA — copy it into the gateway DB **before** `setResolver` or sending to `qntx.eth` breaks.

1. Deploy:

```bash
# .env: GATEWAY_URL, OWNER, SIGNER_HOT, SIGNER_SPARE
forge script script/DeployOffchainResolver.s.sol:DeployOffchainResolver --rpc-url $RPC --broadcast --verify
```

Constructor: `url = https://ccip.qntx.org/v1` (POST, no `{data}`), `signers = [hot, spare]`, `owner_ = 0xE350Ef4E…`. After this tx, Registry still points at `0xF291…`.

1. Attach, from the **name owner** EOA:

```bash
# .env: ENS_REGISTRY, ENS_NODE (namehash qntx.eth), RESOLVER
forge script script/SetResolver.s.sol:SetResolver --rpc-url $RPC --broadcast
```

`ENS_REGISTRY=0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e`  
`ENS_NODE=0x785a215db8277f90460b53ddc36754177b441dec1e7cc82ae7809d578ec5e2cf`

Rollback: `setResolver` back to `0xF29100983E058B709F3D539b0c765937B804AC15`.

Later URL/signer rotation is `setURL` / `setSigners` from stub `owner()` (Ownable2Step). `setSigners` **replaces** the set; old keys fail immediately even if `expires` is in the future.

Do **not** create Registry/NameWrapper nodes for user subnames. ENSIP-10 stops at the first non-zero **resolver**, not at an owner-only record.

## Gateway ABI

`IResolverService.resolve(bytes name, bytes data) → (bytes result, uint64 expires, bytes sig)`

HTTP: POST JSON `{"sender","data"}` when the stored URL has no `{data}`. 200 body `{"data":"0x" + abi.encode(result,expires,sig)}`. Gateway **must** nameprep and check `namehash(name) == node`. v1 records: ETH `addr` (coin 60) and `text` `avatar`/`url`/`description`. Other coins and `contenthash` empty. Inner `multicall` → HTTP 4xx.

Claim policy is **app-gated** and offchain (`[a-z0-9]{3,20}`, per-address cap, non-transferable). Not Solidity.

Reverse / primary names are out of v1.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

A **[QuantX](https://qntx.org)** open-source project.

<a href="https://qntx.org"><img alt="QuantX" width="369" src="https://raw.githubusercontent.com/qntx/.github/main/profile/qntx.svg" /></a>

Code is law. We write both.

</div>
