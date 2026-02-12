# 18 — Nonce Management Test Plan

**Files Under Test:**
- `src/organization/libraries/LibOrganizationSignatures.sol`
- `src/organization/base/OrganizationSignaturesBase.sol`
- `src/organization/libraries/storage/LibOrganizationSignaturesStorage.sol`
- `src/interfaces/organization/IOrganizationSignatures.sol`

**Test File(s):** `test/LibOrganizationSignatures.t.sol`

---

## 1. Nonce Computation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Same inputs produce same nonce (deterministic) | [U] | P1 |
| 2 | Different operation types produce different nonces | [U] | P1 |
| 3 | Different operation data produces different nonces | [U] | P1 |
| 4 | Different salts produce different nonces | [U] | P1 |
| 5 | Nonce includes `address(this)` — different orgs, different nonces | [S] | P1 |
| 6 | Nonce with empty operation data | [E] | P1 |

---

## 2. Nonce Consumption

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 7 | First use of nonce — succeeds | [U] | P1 |
| 8 | Second use of same nonce — reverts `NonceAlreadyUsed` | [S] | P1 |
| 9 | After consumption, `isNonceUsed` returns true | [U] | P1 |
| 10 | Before consumption, `isNonceUsed` returns false | [U] | P1 |

---

## 3. Cross-Operation Nonce Isolation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 11 | Admin operation nonce does NOT collide with transaction nonce (different operationType) | [S] | P1 |
| 12 | Transaction approval nonce does NOT collide with rejection nonce (same data, different salt/type) | [S] | P1 |
| 13 | Nonces from different operations on same org are independent | [U] | P1 |

---

## 4. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 14 | Fuzz: Random (operationType, operationData, salt) tuples produce unique nonces | [F] | P1 |
| 15 | Fuzz: Consumed nonces always revert on reuse | [F] | P1 |
| 16 | Fuzz: Unconsumed nonces always succeed | [F] | P1 |
| 17 | Fuzz: Random operation types with same data and salt — always produce different nonces | [F] | P1 |

---

## 5. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 18 | **Nonce monotonicity**: Once `isNonceUsed(nonce) == true`, it remains true forever | P0 |
| 19 | **No double-spend**: A nonce used for approval cannot be used for rejection (and vice versa) | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Computation | 6 | P1 |
| Consumption | 4 | P1 |
| Cross-operation isolation | 3 | P1 |
| Fuzz tests | 4 | P1 |
| Invariant tests | 2 | P0 |
| **Total** | **19** | |
