# 12 — Guardian Recovery Test Plan (Gap Analysis)

**Files Under Test:**
- `src/organization/libraries/LibOrganizationGuardianRecovery.sol`
- `src/organization/base/OrganizationGuardianRecoveryBase.sol`
- `src/interfaces/organization/IOrganizationGuardianRecovery.sol`

**Existing Tests:** `test/LibOrganizationGuardianRecovery.t.sol` (48 tests)

**Test File(s):** Existing file + `test/OrganizationGuardianRecoveryBase.t.sol`

---

## Existing Coverage Summary

The existing 48 tests cover:
- Storage slot validation
- Initialization (happy path + error cases)
- Recovery update flow (initiate/finalize/cancel/accept)
- Normal guardian flow (initiate/finalize/cancel/accept)
- Parallel flow execution
- Deferred initialization (initiate/finalize/cancel)

## Gaps to Fill

### 1. Base Contract Integration Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | `initiateRecoveryGuardianUpdate` only callable by `onlyGuardianRecoveryAddress` | [N] | P1 |
| 2 | `finalizeRecoveryGuardianUpdate` only callable by `onlyGuardianRecoveryAddress` | [N] | P1 |
| 3 | `cancelRecoveryGuardianUpdate` only callable by `onlyGuardianRecoveryAddress` | [N] | P1 |
| 4 | `acceptGuardianRecovery` only callable by `onlyRecoveryPendingGuardian` | [N] | P1 |
| 5 | `initiateInitializeGuardianRecovery` only callable by `onlyGuardian` | [N] | P1 |
| 6 | `finalizeInitializeGuardianRecovery` only callable by `onlyGuardian` | [N] | P1 |
| 7 | `cancelInitializeGuardianRecovery` only callable by `onlyGuardian` | [N] | P1 |

### 2. Admin Authorization for Deferred Init

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 8 | Deferred init requires admin auth signatures | [U] | P1 |
| 9 | Deferred init finalize requires admin auth signatures | [U] | P1 |
| 10 | Deferred init cancel requires admin auth signatures | [U] | P1 |
| 11 | Deferred init with insufficient admin signatures — reverts | [N] | P1 |

### 3. Edge Cases Not Covered

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 12 | Recovery flow after deferred init: full lifecycle | [I] | P1 |
| 13 | Recovery guardian update updates NORMAL guardian storage (not recovery storage) | [S] | P1 |
| 14 | After recovery completes, normal guardian flow can be used by new guardian | [I] | P1 |
| 15 | Recovery with same address as current guardian — succeeds (no validation against current) | [E] | P2 |

### 4. Event Validation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 16 | `RecoveryGuardianUpdateInitiated` emitted with correct params | [EV] | P2 |
| 17 | `RecoveryGuardianUpdateAccepted` emitted with old and new guardian | [EV] | P2 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Access control (base) | 7 | P1 |
| Admin auth | 4 | P1 |
| Edge cases | 4 | P1-P2 |
| Events | 2 | P2 |
| **Total** | **17** | |
