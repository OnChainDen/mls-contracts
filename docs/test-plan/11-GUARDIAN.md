# 11 — Guardian Test Plan

**Files Under Test:**
- `src/organization/libraries/LibOrganizationGuardian.sol`
- `src/organization/base/OrganizationGuardianBase.sol`
- `src/interfaces/organization/IOrganizationGuardian.sol`

**Test File(s):** `test/LibOrganizationGuardian.t.sol`, `test/OrganizationGuardianBase.t.sol`

---

## 1. Guardian Initialization

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Initialize guardian with valid address — succeeds | [U] | P1 |
| 2 | Initialize guardian with address(0) — reverts `InvalidGuardianAddress` | [N] | P1 |
| 3 | Guardian set correctly after initialization | [U] | P1 |

---

## 2. Guardian Update Flow (Initiate → Finalize → Accept)

### 2.1 Initiate

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 4 | Initiate with valid new guardian — sets pending state | [U] | P1 |
| 5 | Initiate with address(0) — reverts `InvalidGuardianAddress` | [N] | P1 |
| 6 | Initiate when update already pending — reverts `GuardianUpdateAlreadyPending` | [N] | P1 |
| 7 | Initiate emits `GuardianUpdateInitiated` event | [EV] | P1 |
| 8 | Pending guardian timestamp computed correctly (block.timestamp + timelock) | [U] | P1 |
| 9 | Initiate requires admin authorization | [U] | P1 |

### 2.2 Finalize

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 10 | Finalize after timelock expires — marks ready for acceptance | [U] | P1 |
| 11 | Finalize before timelock expires — reverts `TimelockNotExpired` | [N] | P1 |
| 12 | Finalize at exactly timelock expiry timestamp — succeeds | [E] | P1 |
| 13 | Finalize when no pending update — reverts `NoPendingGuardianUpdate` | [N] | P1 |
| 14 | Finalize emits `GuardianUpdateFinalized` event | [EV] | P1 |
| 15 | Finalize requires admin authorization | [U] | P1 |

### 2.3 Accept

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 16 | Accept by pending guardian — guardian updated, pending cleared | [U] | P1 |
| 17 | Accept when not ready for acceptance — reverts `GuardianUpdateNotReadyForAcceptance` | [N] | P1 |
| 18 | Accept when no pending update — reverts `NoPendingGuardianUpdate` | [N] | P1 |
| 19 | Accept by wrong address — reverts `UnauthorizedGuardianAcceptance` | [S] | P1 |
| 20 | Accept emits `GuardianUpdateAccepted` event | [EV] | P1 |
| 21 | After acceptance, old guardian can no longer act as guardian | [S] | P1 |
| 22 | After acceptance, new guardian can act as guardian | [U] | P1 |

### 2.4 Cancel

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 23 | Cancel pending update — clears all pending state | [U] | P1 |
| 24 | Cancel when no pending update — reverts `NoPendingGuardianUpdate` | [N] | P1 |
| 25 | Cancel emits `GuardianUpdateCancelled` event | [EV] | P1 |
| 26 | Cancel requires admin authorization | [U] | P1 |
| 27 | After cancel, initiate can be called again | [U] | P1 |

---

## 3. Full Update Lifecycle

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 28 | Complete flow: initiate → (time passes) → finalize → accept | [I] | P1 |
| 29 | Cancel during pending: initiate → cancel → initiate again works | [I] | P1 |
| 30 | Cancel after finalize but before accept: clears state | [I] | P1 |

---

## 4. Access Control

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 31 | `initiateGuardianUpdate` requires `onlyGuardian` | [N] | P1 |
| 32 | `finalizeGuardianUpdate` requires `onlyGuardian` | [N] | P1 |
| 33 | `cancelGuardianUpdate` requires `onlyGuardian` | [N] | P1 |
| 34 | `acceptGuardian` requires `onlyPendingGuardian` | [N] | P1 |
| 35 | View functions callable by anyone | [U] | P3 |

---

## 5. Query Functions

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 36 | `guardian()` returns current guardian | [U] | P3 |
| 37 | `pendingGuardian()` returns address(0) when no pending | [U] | P3 |
| 38 | `pendingGuardianUpdateTimestamp()` returns 0 when no pending | [U] | P3 |
| 39 | `isGuardianUpdateReadyForAcceptance()` returns false when no pending | [U] | P3 |

---

## 6. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 40 | Fuzz: Random valid addresses as new guardian — update flow completes | [F] | P1 |
| 41 | Fuzz: Random timestamps before/after timelock — correct behavior | [F] | P1 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Initialization | 3 | P1 |
| Initiate | 6 | P1 |
| Finalize | 6 | P1 |
| Accept | 7 | P1 |
| Cancel | 5 | P1 |
| Full lifecycle | 3 | P1 |
| Access control | 5 | P1-P3 |
| Query functions | 4 | P3 |
| Fuzz tests | 2 | P1 |
| **Total** | **41** | |
