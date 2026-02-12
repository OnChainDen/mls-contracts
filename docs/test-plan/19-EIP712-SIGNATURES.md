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

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Domain separator | 7 | P1 |
| Type hashes | 7 | P1 |
| Typed data hash | 3 | P1 |
| Cross-chain replay | 2 | P1 |
| **Total** | **19** | |
