# 11 — Guardian Test Plan

**Files Under Test:**
- `src/organization/base/OrganizationGuardianBase.sol`
- `src/organization/libraries/LibOrganizationGuardian.sol`
- `src/interfaces/organization/IOrganizationGuardian.sol`

**Test File(s):** `test/OrganizationGuardianBase.t.sol`, `test/LibOrganizationGuardian.t.sol`

---

## File 1: OrganizationGuardianBase.sol

### 1.1 `initiateGuardianUpdate`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| 2 | Insufficient admin signatures — reverts | [N] | P0 |
| 3 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| 4 | `OperationType` is `InitiateUpdateGuardian` in admin auth | [U] | P1 |
| 5 | `operationData` encodes `newGuardian` | [U] | P1 |
| 6 | Delegates to `LibOrganizationGuardian.initiateGuardianUpdate` | [U] | P1 |

---

### 1.2 `finalizeGuardianUpdate`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 7 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| 8 | Insufficient admin signatures — reverts | [N] | P0 |
| 9 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| 10 | `OperationType` is `FinalizeUpdateGuardian` in admin auth | [U] | P1 |
| 11 | `operationData` encodes `pendingGuardianAddr` (fetched via `getPendingGuardian`) | [U] | P1 |
| 12 | Delegates to `LibOrganizationGuardian.finalizeGuardianUpdate` | [U] | P1 |

---

### 1.3 `cancelGuardianUpdate`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 13 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| 14 | Insufficient admin signatures — reverts | [N] | P0 |
| 15 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| 16 | `OperationType` is `CancelUpdateGuardian` in admin auth | [U] | P1 |
| 17 | `operationData` encodes `pendingGuardianAddr` (fetched via `getPendingGuardian`) | [U] | P1 |
| 18 | Delegates to `LibOrganizationGuardian.cancelGuardianUpdate` | [U] | P1 |

---

### 1.4 `acceptGuardian`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 19 | Non-pending-guardian caller — reverts (onlyPendingGuardian modifier) | [N] | P0 |
| 20 | Pending guardian caller — delegates to `LibOrganizationGuardian.acceptGuardian` | [U] | P1 |

---

### 1.5 View Functions (Base)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 21 | `guardian()` delegates to `getGuardian` — returns correct address | [U] | P3 |
| 22 | `pendingGuardian()` delegates to `getPendingGuardian` | [U] | P3 |
| 23 | `pendingGuardianUpdateTimestamp()` delegates to `getPendingGuardianUpdateTimestamp` | [U] | P3 |
| 24 | `isGuardianUpdateReadyForAcceptance()` delegates to `getIsGuardianUpdateReadyForAcceptance` | [U] | P3 |
| 25 | All view functions callable by anyone (no access restriction) | [U] | P3 |

---

## File 2: LibOrganizationGuardian.sol

> Note: All functions in this library are already `internal` (none are `private`), so no
> conversion is needed. Create a test harness that exposes them via public wrappers.

### 2.1 `initializeGuardian`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 26 | Valid address — sets guardian in storage | [U] | P1 |
| 27 | `address(0)` — reverts `InvalidGuardianAddress` | [N] | P1 |
| 28 | Guardian correctly readable via `getGuardian` after initialization | [U] | P1 |
| 28.1 | Guardian already initialized (storage != `address(0)`) — reverts (prevents re-initialization) | [S] | P0 |

---

### 2.2 `initiateGuardianUpdate`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 29 | Valid new guardian — sets `pendingGuardian` in storage | [U] | P1 |
| 30 | `address(0)` as new guardian — reverts `InvalidGuardianAddress` | [N] | P1 |
| 31 | Update already pending (`pendingGuardian != address(0)`) — reverts `GuardianUpdateAlreadyPending` | [N] | P1 |
| 32 | `canFinalizeAtTimestamp` computed correctly (`block.timestamp + timelock duration`) | [U] | P1 |
| 33 | Sets `isGuardianUpdateReadyForAcceptance = false` | [U] | P1 |
| 34 | Emits `GuardianUpdateInitiated(currentGuardian, newGuardian, canFinalizeAtTimestamp)` | [EV] | P1 |
| 35 | Current guardian remains unchanged during pending state | [U] | P1 |
| 36 | Same address as current guardian — still succeeds (not prohibited) | [E] | P2 |

---

### 2.3 `finalizeGuardianUpdate`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 37 | After timelock expires — sets `isGuardianUpdateReadyForAcceptance = true` | [U] | P1 |
| 38 | Before timelock expires — reverts `TimelockNotExpired` | [N] | P1 |
| 39 | At exactly timelock expiry timestamp — succeeds | [E] | P1 |
| 40 | No pending update (`pendingGuardian == address(0)`) — reverts `NoPendingGuardianUpdate` | [N] | P1 |
| 41 | Emits `GuardianUpdateFinalized(pendingGuardian)` | [EV] | P1 |
| 42 | Finalize does NOT change guardian — only marks ready for acceptance | [U] | P1 |
| 43 | Double finalize at library level — second call sets flag to true again (no-op effectively) | [E] | P2 |

---

### 2.4 `cancelGuardianUpdate`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 44 | Clears `pendingGuardian` to `address(0)` | [U] | P1 |
| 45 | Clears `pendingGuardianUpdateTimestamp` to 0 | [U] | P1 |
| 46 | Clears `isGuardianUpdateReadyForAcceptance` to false | [U] | P1 |
| 47 | No pending update — reverts `NoPendingGuardianUpdate` | [N] | P1 |
| 48 | Emits `GuardianUpdateCancelled(currentGuardian, cancelledGuardian)` | [EV] | P1 |
| 49 | Cancel before finalize — clears pending state correctly | [U] | P1 |
| 50 | Cancel after finalize but before accept — clears ready-for-acceptance state | [U] | P1 |

---

### 2.5 `acceptGuardian`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 51 | Updates `guardian` to `pendingGuardian` address | [U] | P1 |
| 52 | Clears `pendingGuardian` to `address(0)` | [U] | P1 |
| 53 | Clears `pendingGuardianUpdateTimestamp` to 0 | [U] | P1 |
| 54 | Clears `isGuardianUpdateReadyForAcceptance` to false | [U] | P1 |
| 55 | No pending update (`pendingGuardian == address(0)`) — reverts `NoPendingGuardianUpdate` | [N] | P1 |
| 56 | Not ready for acceptance (`isGuardianUpdateReadyForAcceptance == false`) — reverts `GuardianUpdateNotReadyForAcceptance` | [N] | P1 |
| 57 | Emits `GuardianUpdateAccepted(previousGuardian, newGuardian)` | [EV] | P1 |
| 58 | After acceptance, old guardian address is no longer the guardian | [S] | P1 |
| 59 | After acceptance, new guardian address is the guardian | [U] | P1 |

---

### 2.6 `enforceOnlyGuardian`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 60 | `msg.sender == guardian` — no revert | [U] | P0 |
| 61 | `msg.sender != guardian` — reverts `UnauthorizedGuardian(msg.sender, guardian)` | [N] | P0 |
| 62 | Error includes both caller address and expected guardian address | [U] | P1 |

---

### 2.7 `enforceOnlyPendingGuardian`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 63 | `msg.sender == pendingGuardian` — no revert | [U] | P0 |
| 64 | `msg.sender != pendingGuardian` — reverts `UnauthorizedGuardianAcceptance(msg.sender, pendingGuardian)` | [N] | P0 |
| 65 | No pending update (`pendingGuardian == address(0)`) — any address reverts | [E] | P0 |

---

### 2.8 View Functions (Lib)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 66 | `getGuardian` returns current guardian address | [U] | P3 |
| 67 | `getPendingGuardian` returns `address(0)` when no pending update | [U] | P3 |
| 68 | `getPendingGuardian` returns correct address during pending update | [U] | P3 |
| 69 | `getPendingGuardianUpdateTimestamp` returns 0 when no pending update | [U] | P3 |
| 70 | `getPendingGuardianUpdateTimestamp` returns correct timestamp during pending update | [U] | P3 |
| 71 | `getIsGuardianUpdateReadyForAcceptance` returns false when no pending update | [U] | P3 |
| 72 | `getIsGuardianUpdateReadyForAcceptance` returns false after initiate (before finalize) | [U] | P3 |
| 73 | `getIsGuardianUpdateReadyForAcceptance` returns true after finalize | [U] | P3 |

---

## 3. Full Lifecycle Integration Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 74 | Complete flow: initiate → time passes → finalize → accept — guardian updated | [I] | P1 |
| 75 | Cancel during pending: initiate → cancel → initiate again with different address — works | [I] | P1 |
| 76 | Cancel after finalize: initiate → finalize → cancel → all pending state cleared | [I] | P1 |
| 77 | Multiple sequential updates: complete first update → start and complete second update | [I] | P1 |

---

## 4. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 78 | Fuzz: Random valid addresses as new guardian — update flow completes | [F] | P1 |
| 79 | Fuzz: Random timestamps before/after timelock — correct pass/fail on finalize | [F] | P1 |
| 80 | Fuzz: `address(0)` always reverts `InvalidGuardianAddress` on initiate | [F] | P1 |
| 81 | Fuzz: Random non-pending-guardian addresses always revert on `enforceOnlyPendingGuardian` | [F] | P1 |
| 82 | Fuzz: Random timelock durations — `canFinalizeAtTimestamp` always equals `block.timestamp + duration` | [F] | P1 |
| 83 | Fuzz: Random addresses — `enforceOnlyGuardian` always passes for correct guardian, fails for others | [F] | P0 |

---

## 5. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 84 | **Guardian always set**: `guardian() != address(0)` after initialization | P0 |
| 85 | **Pending exclusivity**: At most one pending guardian update at a time | P0 |
| 86 | **Timelock enforcement**: Guardian cannot change without timelock expiry + finalize + accept | P0 |
| 87 | **State consistency**: If `pendingGuardian == address(0)`, then `pendingGuardianUpdateTimestamp == 0` AND `isGuardianUpdateReadyForAcceptance == false` | P0 |
| 88 | **Accept clears all**: After `acceptGuardian`, all three pending fields are reset (`address(0)`, `0`, `false`) | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `initiateGuardianUpdate` (Base) | 6 | P0-P1 |
| `finalizeGuardianUpdate` (Base) | 6 | P0-P1 |
| `cancelGuardianUpdate` (Base) | 6 | P0-P1 |
| `acceptGuardian` (Base) | 2 | P0-P1 |
| View functions (Base) | 5 | P3 |
| `initializeGuardian` | 4 | P0-P1 |
| `initiateGuardianUpdate` (Lib) | 8 | P1-P2 |
| `finalizeGuardianUpdate` (Lib) | 7 | P1-P2 |
| `cancelGuardianUpdate` (Lib) | 7 | P1 |
| `acceptGuardian` (Lib) | 9 | P1 |
| `enforceOnlyGuardian` | 3 | P0-P1 |
| `enforceOnlyPendingGuardian` | 3 | P0 |
| View functions (Lib) | 8 | P3 |
| Full lifecycle integration | 4 | P1 |
| Fuzz tests | 6 | P0-P1 |
| Invariant tests | 5 | P0 |
| **Total** | **89** | |
