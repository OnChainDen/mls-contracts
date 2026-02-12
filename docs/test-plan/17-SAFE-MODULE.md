# 17 — Safe Module Test Plan (Gap Analysis)

**Files Under Test:**
- `src/safe-module/SafeExecutorModule.sol`
- `src/safe-module/BatchedTransaction.sol`
- `src/interfaces/ISafeExecutorModule.sol`
- `src/interfaces/IBatchedTransaction.sol`

**Existing Tests:** `test/safe-module/SafeExecutorModule.t.sol` (32 tests), `test/safe-module/BatchedTransaction.t.sol` (22 tests)

**Test File(s):** Existing files (gap additions)

---

## Existing Coverage Summary

**SafeExecutorModule.t.sol** covers:
- Constructor validation, authorization, Safe protection, CALL vs DELEGATECALL, state changes, management function blocking

**BatchedTransaction.t.sol** covers:
- Single/multiple batching, empty batches, address(this) blocking, fuzz tests

## Gaps to Fill

### 1. SafeExecutorModule Gaps

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | `isValidSignature` with valid EOA signature — returns magic value | [U] | P2 |
| 2 | `isValidSignature` with invalid signature — returns invalid value | [N] | P2 |
| 3 | `isValidSignature` with ERC-1271 contract signature | [U] | P2 |
| 4 | `isValidSignature` with empty signature — returns invalid value | [E] | P2 |
| 5 | Module enabled on Safe (integration with real Safe contract) | [I] | P2 |

### 2. BatchedTransaction Gaps

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 6 | Packed transaction with maximum data length | [E] | P2 |
| 7 | Transaction with data length exactly 0 — valid (empty call) | [E] | P2 |
| 8 | Gas consumption: large batch doesn't exceed block gas limit | [E] | P3 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| SafeExecutorModule gaps | 5 | P2 |
| BatchedTransaction gaps | 3 | P2-P3 |
| **Total** | **8** | |
