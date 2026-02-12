# 19 — EIP-712 Signatures Test Plan

**Files Under Test:**
- `src/organization/libraries/LibOrganizationEIP712.sol`

**Test File(s):** `test/LibOrganizationEIP712.t.sol`

---

## 1. Domain Separator

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Domain separator includes name "MLSWalletOrganization" | [U] | P1 |
| 2 | Domain separator includes version "1" | [U] | P1 |
| 3 | Domain separator includes `block.chainid` | [U] | P1 |
| 4 | Domain separator includes `address(this)` (verifying contract) | [U] | P1 |
| 5 | Different chain IDs produce different domain separators | [S] | P1 |
| 6 | Different organization addresses produce different domain separators | [S] | P1 |
| 7 | Domain separator is consistent across multiple calls (deterministic) | [U] | P1 |

---

## 2. Type Hashes

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 8 | `EIP712_DOMAIN_TYPEHASH` matches keccak256 of EIP-712 domain type string | [U] | P1 |
| 9 | `ADMIN_OPERATION_TYPEHASH` matches expected type string hash | [U] | P1 |
| 10 | `INITIATE_ACCOUNT_TRANSACTION_TYPEHASH` matches expected | [U] | P1 |
| 11 | `REVIEW_ACCOUNT_TRANSACTION_TYPEHASH` matches expected | [U] | P1 |
| 12 | `INITIATE_SIGNATURE_VALIDATION_TYPEHASH` matches expected | [U] | P1 |
| 13 | `REVIEW_SIGNATURE_VALIDATION_TYPEHASH` matches expected | [U] | P1 |
| 14 | All type hashes are unique (no collisions) | [U] | P1 |

---

## 3. Typed Data Hash

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 15 | `computeTypedDataHash` produces valid EIP-712 hash (prefix + domain + struct) | [U] | P1 |
| 16 | Different struct hashes produce different typed data hashes | [U] | P1 |
| 17 | Hash matches expected format: `keccak256("\x19\x01" || domainSeparator || structHash)` | [U] | P1 |

---

## 4. Cross-Chain Replay Protection

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 18 | Same operation on different chains → different typed data hash | [S] | P1 |
| 19 | Same operation on different orgs (same chain) → different typed data hash | [S] | P1 |

---

## 5. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 20 | Fuzz: Random chain IDs always produce unique domain separators | [F] | P1 |
| 21 | Fuzz: Random verifying contract addresses produce unique domain separators | [F] | P1 |
| 22 | Fuzz: Random struct hashes always produce unique typed data hashes | [F] | P1 |
| 23 | Fuzz: Random operation data — initiator and review hashes always differ (different type hashes) | [F] | P1 |

---

## 6. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 24 | **Domain separator determinism**: Same (chainId, verifying contract address) always produces the same domain separator | P1 |
| 25 | **Type hash uniqueness**: All EIP-712 type hashes in the system are unique (no collisions) | P1 |
| 26 | **Prefix compliance**: All typed data hashes start with `\x19\x01` prefix per EIP-712 | P1 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Domain separator | 7 | P1 |
| Type hashes | 7 | P1 |
| Typed data hash | 3 | P1 |
| Cross-chain replay | 2 | P1 |
| Fuzz tests | 4 | P1 |
| Invariant tests | 3 | P1 |
| **Total** | **26** | |
