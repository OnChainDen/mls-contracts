# 22 — Fuzz Testing Strategy

**Scope:** Property-based testing using Foundry's built-in fuzzer. These tests complement the unit tests by exploring edge cases that manual test design might miss.

**Test File(s):** Fuzz tests are embedded in each module's test file. This document defines the cross-cutting fuzz strategy.

---

## Fuzz Test Design Principles

1. **Bound inputs**: Use `vm.assume()` or `bound()` to restrict fuzz inputs to valid ranges
2. **Property-based**: Each fuzz test asserts a property that must hold for ALL inputs
3. **Runs**: Configure `FOUNDRY_FUZZ_RUNS=1000` minimum (10000 for critical paths)
4. **Seed stability**: Store failing seeds in `foundry.toml` under `[fuzz]`

---

## 1. Signature Fuzzing

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 1 | Any valid private key (1 to SECP256K1_ORDER-1) produces recoverable signature | 10000 | P0 |
| 2 | Random bytes (length != 65 for EOA) never recover a valid signer | 10000 | P0 |
| 3 | Signature malleability: complement s value always rejected | 10000 | P0 |
| 4 | Random hash values: signature for hash A never validates for hash B | 10000 | P0 |
| 5 | ERC-1271 signer addresses: only contracts returning magic value accepted | 1000 | P0 |

---

## 2. Merkle Proof Fuzzing

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 6 | Random leaf included in tree: correct proof always verifies | 1000 | P0 |
| 7 | Random leaf NOT in tree: no proof verifies | 1000 | P0 |
| 8 | Random proof bytes against valid root: never falsely verifies | 10000 | P0 |
| 9 | Tree of N random leaves: each leaf verifiable with correct proof | 1000 | P1 |
| 10 | Modifying any byte of a valid proof: verification fails | 1000 | P0 |

---

## 3. Nonce Fuzzing

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 11 | Random (operationType, data, salt) tuples: all produce unique nonces | 1000 | P1 |
| 12 | Consumed nonces: replay always reverts regardless of other state | 1000 | P0 |
| 13 | Random salt values with same operation: unique nonces | 1000 | P1 |

---

## 4. Admin Authorization Fuzzing

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 14 | Random valid admin signatures always authenticate | 1000 | P0 |
| 15 | Random non-admin signers always rejected | 1000 | P0 |
| 16 | Random expiration timestamps: future accepted, past rejected | 1000 | P0 |
| 17 | Random voting thresholds in [1, adminCount]: always valid | 1000 | P0 |
| 18 | Random voting thresholds outside range: always revert | 1000 | P0 |

---

## 5. Policy Validation Fuzzing

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 19 | Random ERC-20 transfer calldata: token address extracted correctly | 1000 | P0 |
| 20 | Random ERC-20 transfer calldata: amount extracted correctly | 1000 | P0 |
| 21 | Random ERC-20 transfer calldata: recipient extracted correctly | 1000 | P0 |
| 22 | Random uint values against Range constraint: boundary behavior correct | 1000 | P0 |
| 23 | Random int values against Range constraint: signed comparison correct | 1000 | P0 |
| 24 | Random addresses against Exact constraint: only matching address passes | 1000 | P0 |
| 25 | Random rate limit usage: cumulative never exceeds limit | 1000 | P0 |

---

## 6. Group/Member Fuzzing

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 26 | Random non-zero addresses can be added as members | 1000 | P0 |
| 27 | Adding then removing random members: no longer members | 1000 | P0 |
| 28 | Random group IDs: create and verify | 1000 | P1 |
| 29 | Deleted group IDs: re-creation always reverts | 1000 | P0 |

---

## 7. EIP-712 Fuzzing

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 30 | Random chain IDs produce unique domain separators | 1000 | P0 |
| 31 | Random struct hashes produce unique typed data hashes | 1000 | P0 |
| 32 | Random operation data: initiator and review hashes always differ (different type hashes) | 1000 | P0 |

---

## 8. CREATE2 Fuzzing

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 33 | Random salts always produce unique account addresses | 1000 | P1 |
| 34 | Computed address always matches deployed address | 1000 | P1 |

---

## 9. Timelock Fuzzing

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 35 | Random durations in [2 days, 30 days]: always valid | 1000 | P1 |
| 36 | Random durations outside [2 days, 30 days]: always revert | 1000 | P1 |
| 37 | Random timestamps before timelock expiry: finalize always reverts | 1000 | P1 |
| 38 | Random timestamps at/after timelock expiry: finalize always succeeds | 1000 | P1 |

---

## 9.5 Parameter Constraint & Overflow Fuzzing

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 38.1 | Random parameter constraint offsets: bounds checking never overflows | 10000 | P0 |
| 38.2 | Random dynamic bytes lengths in constraints: validation always terminates without panic | 10000 | P0 |
| 38.3 | Random ERC-20 calldata: getActualDestination never panics or returns wrong type | 10000 | P0 |
| 38.4 | Random signature type prefixes (0x00-0xff): only 0x00 and 0x01 produce valid ERC-1271 response | 1000 | P0 |
| 38.5 | Random guardian addresses (EOA/contract/zero): module validation returns valid boolean | 1000 | P0 |
| 38.6 | Random admin modification arrays: modifyAdmins never leaves adminCount=0 | 1000 | P0 |
| 38.7 | Random rate limit configs: checkAndUpdateRateLimit never causes uint256 overflow | 10000 | P0 |

---

## 10. Byte Manipulation Fuzzing (Existing Coverage — Verify)

Existing BytesUtils fuzz tests cover:
- `sliceFrom` length correctness, data integrity, arbitrary length
- `sliceRange` arbitrary inputs, matching with sliceFrom

No additional fuzz tests needed for BytesUtils.

---

## Summary

| Category | Fuzz Tests | Min Runs | Priority |
|----------|-----------|----------|----------|
| Signatures | 5 | 10000 | P0 |
| Merkle proofs | 5 | 1000-10000 | P0 |
| Nonces | 3 | 1000 | P0-P1 |
| Admin auth | 5 | 1000 | P0 |
| Policy validation | 7 | 1000 | P0 |
| Groups/Members | 4 | 1000 | P0-P1 |
| EIP-712 | 3 | 1000 | P0 |
| CREATE2 | 2 | 1000 | P1 |
| Timelocks | 4 | 1000 | P1 |
| Param constraints & overflow | 7 | 1000-10000 | P0 |
| **Total** | **45** | | |
