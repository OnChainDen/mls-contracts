# Test Plan Index

## Overview

This document suite defines the comprehensive test plan for the onchain custody contracts. It covers unit tests, integration tests, fuzz tests, invariant tests, and security-focused tests for all custom code (excluding imported libraries like OpenZeppelin).

## Current Test Coverage

Existing tests cover **7 files** with **~222 test functions**:
- `BytesUtils.t.sol` (47 tests) — utility library
- `ERC7201StorageSlots.t.sol` (14 tests) — storage slot validation
- `LibOrganizationGuardianRecovery.t.sol` (48 tests) — guardian recovery
- `LibOrganizationTxRecovery.t.sol` (35 tests) — transaction recovery
- `PolicyRateLimits.t.sol` (24 tests) — policy rate limiting
- `BatchedTransaction.t.sol` (22 tests) — batched transactions
- `SafeExecutorModule.t.sol` (32 tests) — Safe module

## What Needs Testing

The remaining **~80+ source files** with **11 untested interfaces** and **4 partially-tested interfaces** need coverage.

## Document Structure

| Document | Scope | Priority |
|----------|-------|----------|
| [01-UTILITY-LIBRARIES.md](./01-UTILITY-LIBRARIES.md) | SignatureUtils, MerkleUtils, TokenTransferUtils, ContractInteractionUtils, TimelockUtils | High |
| [02-STORAGE-LIBRARIES.md](./02-STORAGE-LIBRARIES.md) | All 13 ERC-7201 storage libraries | Medium |
| [03-ORGANIZATION-ADMIN.md](./03-ORGANIZATION-ADMIN.md) | Admin management, voting threshold, admin auth signatures | Critical |
| [04-ORGANIZATION-MEMBERS.md](./04-ORGANIZATION-MEMBERS.md) | Member CRUD operations | Critical |
| [05-ORGANIZATION-GROUPS.md](./05-ORGANIZATION-GROUPS.md) | Group management, group membership | Critical |
| [06-ORGANIZATION-POLICY.md](./06-ORGANIZATION-POLICY.md) | Policy CRUD, Merkle verification | Critical |
| [07-POLICY-VALIDATION.md](./07-POLICY-VALIDATION.md) | All 7 policy validation libraries (approval, initiator, destination, token, contract interaction, parameters, rate limits) | Critical |
| [08-ACCOUNT-TRANSACTION.md](./08-ACCOUNT-TRANSACTION.md) | Transaction execution, rejection, signature binding | Critical |
| [09-ACCOUNT-SIGNATURE.md](./09-ACCOUNT-SIGNATURE.md) | ERC-1271 signature validation, recovery signatures, policy-based signatures | Critical |
| [10-ACCOUNT-FACTORY.md](./10-ACCOUNT-FACTORY.md) | Account deployment, CREATE2, beacon proxy | High |
| [11-GUARDIAN.md](./11-GUARDIAN.md) | Guardian update flow (initiate/finalize/cancel/accept) | High |
| [12-GUARDIAN-RECOVERY.md](./12-GUARDIAN-RECOVERY.md) | Guardian recovery (existing tests + gaps) | High |
| [13-TX-RECOVERY.md](./13-TX-RECOVERY.md) | Transaction recovery (existing tests + gaps) | High |
| [14-INITIALIZATION.md](./14-INITIALIZATION.md) | Organization initialization, factory deployment | High |
| [15-UPGRADES.md](./15-UPGRADES.md) | UUPS upgrades, whitelist, authorization flow | High |
| [16-IMPLEMENTATION-WHITELIST.md](./16-IMPLEMENTATION-WHITELIST.md) | Whitelist management | Medium |
| [17-SAFE-MODULE.md](./17-SAFE-MODULE.md) | Safe module (existing tests + gaps) | Medium |
| [18-NONCE-MANAGEMENT.md](./18-NONCE-MANAGEMENT.md) | Nonce computation, consumption, replay protection | High |
| [19-EIP712-SIGNATURES.md](./19-EIP712-SIGNATURES.md) | EIP-712 domain separation, type hashes | High |
| [20-INTEGRATION-TESTS.md](./20-INTEGRATION-TESTS.md) | Full end-to-end flows across modules | Critical |
| [21-INVARIANT-TESTS.md](./21-INVARIANT-TESTS.md) | System-wide invariants that must always hold | Critical |
| [22-FUZZ-TESTS.md](./22-FUZZ-TESTS.md) | Fuzz testing strategy for all modules | High |
| [23-ADMIN-OPERATION-TIMELOCK.md](./23-ADMIN-OPERATION-TIMELOCK.md) | Timelock duration management | Medium |
| [24-SECURITY-AUDIT-GAPS.md](./24-SECURITY-AUDIT-GAPS.md) | Security audit gap analysis: overflow, replay, race conditions, cross-org attacks | Critical |

## Test Types Legend

| Type | Symbol | Description |
|------|--------|-------------|
| Unit | `[U]` | Tests a single function in isolation |
| Integration | `[I]` | Tests interaction between multiple contracts/modules |
| Fuzz | `[F]` | Property-based testing with random inputs |
| Invariant | `[INV]` | Properties that must always hold across all states |
| Security | `[S]` | Tests specifically targeting vulnerability vectors |
| Edge Case | `[E]` | Boundary conditions and corner cases |
| Negative | `[N]` | Tests that expected reverts/failures occur |
| Event | `[EV]` | Tests that correct events are emitted |

## Priority Legend

| Priority | Description |
|----------|-------------|
| **P0 - Critical** | Core security and authorization logic |
| **P1 - High** | Important functionality, upgrade paths |
| **P2 - Medium** | Supporting functionality |
| **P3 - Low** | View functions, getters |

## Test Count by Document

| Document | New Tests |
|----------|-----------|
| 01 — Utility Libraries | 173 |
| 02 — Storage Libraries | 24 |
| 03 — Organization Admin | 97 |
| 04 — Organization Members | 34 |
| 05 — Organization Groups | 68 |
| 06 — Organization Policy | 48 |
| 07 — Policy Validation | 154 |
| 08 — Account Transaction | 82 |
| 09 — Account Signature (ERC-1271) | 53 |
| 10 — Account Factory | 35 |
| 11 — Guardian | 46 |
| 12 — Guardian Recovery (gaps) | 39 |
| 13 — TX Recovery (gaps) | 51 |
| 14 — Initialization | 53 |
| 15 — Upgrades | 26 |
| 16 — Implementation Whitelist | 38 |
| 17 — Safe Module (gaps) | 12 |
| 18 — Nonce Management | 19 |
| 19 — EIP-712 Signatures | 26 |
| 20 — Integration Tests | 64 |
| 21 — Invariant Tests | 42 |
| 22 — Fuzz Tests (cross-cutting) | 62 |
| 23 — Admin Operation Timelock | 18 |
| 24 — Security Audit Gaps | 60 |
| **Total New Tests** | **~1,324** |
| **Existing Tests** | **222** |
| **Grand Total** | **~1,546** |

## Test Count by Type (Approximate)

| Type | Count |
|------|-------|
| Unit [U] | ~510 |
| Negative [N] | ~220 |
| Fuzz [F] | ~148 |
| Security [S] | ~135 |
| Edge Case [E] | ~115 |
| Integration [I] | ~91 |
| Invariant [INV] | ~75 |
| Event [EV] | ~45 |
