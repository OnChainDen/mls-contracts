# 22 — Admin Operation Timelock Test Plan

**Files Under Test:**
- `src/organization/libraries/LibOrganizationAdminOperationTimelock.sol`
- `src/organization/base/OrganizationAdminOperationTimelockBase.sol`
- `src/organization/libraries/storage/LibOrganizationAdminOperationTimelockStorage.sol`
- `src/interfaces/organization/IOrganizationAdminOperationTimelock.sol`

**Test File(s):** `test/LibOrganizationAdminOperationTimelock.t.sol`

---

## 1. Initialization

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Initialize with valid duration (2 days) — succeeds | [U] | P2 |
| 2 | Initialize with valid duration (30 days) — succeeds | [U] | P2 |
| 3 | Initialize with invalid duration (< 2 days) — reverts `InvalidTimelockDuration` | [N] | P2 |
| 4 | Initialize with invalid duration (> 30 days) — reverts `InvalidTimelockDuration` | [N] | P2 |
| 5 | After init: `getAdminOperationTimelockDurationSeconds` returns correct value | [U] | P2 |

---

## 2. Timelock Validation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 6 | `validateTimelockExpiredOrRevert` at exactly expiry timestamp — succeeds (>=) | [E] | P2 |
| 7 | `validateTimelockExpiredOrRevert` before expiry — reverts `TimelockNotExpired` | [N] | P2 |
| 8 | `validateTimelockExpiredOrRevert` after expiry — succeeds | [U] | P2 |

---

## 3. Timestamp Computation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 9 | `computeCanFinalizeAtTimestamp` returns `block.timestamp + duration` | [U] | P2 |
| 10 | At different block timestamps, computation is correct | [U] | P2 |

---

## 4. Integration with Guardian Flow

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 11 | Guardian update uses admin operation timelock correctly | [I] | P2 |
| 12 | Recovery initialization uses admin operation timelock correctly | [I] | P2 |

---

## 5. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 13 | Fuzz: Random valid durations always accepted | [F] | P2 |
| 14 | Fuzz: Random timestamps before/after expiry — correct behavior | [F] | P2 |
| 15 | Fuzz: Random durations outside [2 days, 30 days] always revert `InvalidTimelockDuration` | [F] | P2 |
| 16 | Fuzz: Random block timestamps — `computeCanFinalizeAtTimestamp` always returns `block.timestamp + duration` | [F] | P2 |

---

## 6. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 17 | **Duration bounds**: Active timelock duration is always in [2 days, 30 days] | P2 |
| 18 | **Timestamp monotonicity**: `computeCanFinalizeAtTimestamp` result is always >= `block.timestamp` | P2 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Initialization | 5 | P2 |
| Validation | 3 | P2 |
| Computation | 2 | P2 |
| Integration | 2 | P2 |
| Fuzz tests | 4 | P2 |
| Invariant tests | 2 | P2 |
| **Total** | **18** | |
