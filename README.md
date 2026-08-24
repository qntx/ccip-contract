<!-- markdownlint-disable MD033 MD041 MD001 -->

<div align="center">

# CCIP Contract

### ENS Offchain Resolver Contracts (CCIP-Read)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.28+-363636?logo=solidity)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C?logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cGF0aCBkPSJNMTIgMkw0IDdMMTIgMTJMMjAgN0wxMiAyWiIgZmlsbD0iIzMzMyIvPjwvc3ZnPg==)](https://book.getfoundry.sh/)

An ENS resolver that serves records from off-chain storage using [EIP-3668: CCIP Read](https://eips.ethereum.org/EIPS/eip-3668) and [ENSIP-10: Wildcard Resolution](https://docs.ens.domains/ensip/10).

</div>

## Overview

Storing an ENS record on L1 costs gas for every name. An offchain resolver moves that data to a gateway: the resolver reverts with `OffchainLookup`, the client fetches the answer from an HTTPS gateway, and the resolver verifies a signature from a trusted signer before returning the record on-chain.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

A **[QuantX](https://qntx.org)** open-source project.

<a href="https://qntx.org"><img alt="QuantX" width="369" src="https://raw.githubusercontent.com/qntx/.github/main/profile/qntx.svg" /></a>

Code is law. We write both.

</div>
