# 10 — Guardian Test Plan

**Files Under Test:**
- `src/organization/base/OrganizationGuardianBase.sol`
- `src/organization/libraries/LibOrganizationGuardian.sol`

**Private Function Testability Plan (Global):**
All `private` functions in the files under test will be refactored to `internal` for testing and exposed via test harness contracts.

| File | Private functions to convert to `internal` for harness testing |
|---|---|
| `OrganizationGuardianBase.sol` | None |
| `LibOrganizationGuardian.sol` | None (all non-external helper functions are already `internal`) |


---

## File 1: OrganizationGuardianBase.sol

### 1.1 `initiateGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGB-IGU-1 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| OGB-IGU-2 | Insufficient admin signatures — reverts | [N] | P0 |
| OGB-IGU-3 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| OGB-IGU-4 | `OperationType` is `InitiateUpdateGuardian` in admin auth | [U] | P1 |
| OGB-IGU-5 | `operationData` encodes `newGuardian` | [U] | P1 |
| OGB-IGU-6 | Delegates to `LibOrganizationGuardian.initiateGuardianUpdate` | [U] | P1 |
| OGB-IGU-7 | Rejection signatures (`isApproval=false`) cannot execute `initiateGuardianUpdate` | [S] | P0 |
| OGB-IGU-8 | Signatures for a different `OperationType` (e.g., `FinalizeUpdateGuardian`) cannot authorize initiation | [S] | P0 |
| OGB-IGU-9 | Signed `operationData` binding: signatures for `newGuardian=A` cannot execute with `newGuardian=B` | [S] | P0 |
| OGB-IGU-10 | **Desired Behavior:** if downstream library call reverts (`InvalidGuardianAddress` or `GuardianUpdateAlreadyPending`), admin auth nonce/state rolls back so the same signed request can succeed after fixing root cause | [S] | P0 |

---

### 1.2 `finalizeGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGB-FGU-1 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| OGB-FGU-2 | Insufficient admin signatures — reverts | [N] | P0 |
| OGB-FGU-3 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| OGB-FGU-4 | `OperationType` is `FinalizeUpdateGuardian` in admin auth | [U] | P1 |
| OGB-FGU-5 | `operationData` encodes `pendingGuardianAddr` (fetched via `getPendingGuardian`) | [U] | P1 |
| OGB-FGU-6 | Delegates to `LibOrganizationGuardian.finalizeGuardianUpdate` | [U] | P1 |
| OGB-FGU-7 | Rejection signatures (`isApproval=false`) cannot execute `finalizeGuardianUpdate` | [S] | P0 |
| OGB-FGU-8 | Signatures for a different `OperationType` cannot authorize finalize | [S] | P0 |
| OGB-FGU-9 | Signed `operationData` binding to pending guardian: signatures for pending `A` fail after pending guardian changes to `B` | [S] | P0 |
| OGB-FGU-10 | **Desired Behavior:** if downstream library call reverts (`TimelockNotExpired` or `NoPendingGuardianUpdate`), admin auth nonce/state rolls back so the same signed request can be retried once conditions are satisfied | [S] | P0 |

---

### 1.3 `cancelGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGB-CGU-1 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| OGB-CGU-2 | Insufficient admin signatures — reverts | [N] | P0 |
| OGB-CGU-3 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| OGB-CGU-4 | `OperationType` is `CancelUpdateGuardian` in admin auth | [U] | P1 |
| OGB-CGU-5 | `operationData` encodes `pendingGuardianAddr` (fetched via `getPendingGuardian`) | [U] | P1 |
| OGB-CGU-6 | Delegates to `LibOrganizationGuardian.cancelGuardianUpdate` | [U] | P1 |
| OGB-CGU-7 | Rejection signatures (`isApproval=false`) cannot execute `cancelGuardianUpdate` | [S] | P0 |
| OGB-CGU-8 | Signatures for a different `OperationType` cannot authorize cancellation | [S] | P0 |
| OGB-CGU-9 | Signed `operationData` binding to pending guardian: cancel signatures for pending `A` fail after pending guardian changes to `B` | [S] | P0 |
| OGB-CGU-10 | **Desired Behavior:** if downstream library call reverts (`NoPendingGuardianUpdate`), admin auth nonce/state rolls back (same signed request remains usable if matching pending state exists later) | [S] | P0 |

---

### 1.4 `acceptGuardian`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGB-AG-1 | Non-pending-guardian caller — reverts (onlyPendingGuardian modifier) | [N] | P0 |
| OGB-AG-2 | Pending guardian caller — delegates to `LibOrganizationGuardian.acceptGuardian` | [U] | P1 |
| OGB-AG-3 | Pending guardian caller before finalize — reverts `GuardianUpdateNotReadyForAcceptance` | [N] | P0 |
| OGB-AG-4 | After successful acceptance, second `acceptGuardian` call reverts (no pending guardian) and does not mutate state | [S] | P1 |

---

### 1.5 View Functions (Base)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGB-VIEW-1 | `guardian()` delegates to `getGuardian` — returns correct address | [U] | P3 |
| OGB-VIEW-2 | `pendingGuardian()` delegates to `getPendingGuardian` | [U] | P3 |
| OGB-VIEW-3 | `pendingGuardianUpdateTimestamp()` delegates to `getPendingGuardianUpdateTimestamp` | [U] | P3 |
| OGB-VIEW-4 | `isGuardianUpdateReadyForAcceptance()` delegates to `getIsGuardianUpdateReadyForAcceptance` | [U] | P3 |
| OGB-VIEW-5 | All view functions callable by anyone (no access restriction) | [U] | P3 |

---

## File 2: LibOrganizationGuardian.sol

> Note: All functions in this library are already `internal` (none are `private`), so no
> conversion is needed. Create a test harness that exposes them via public wrappers.

### 2.1 `initializeGuardian`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOG-INIT-1 | Valid address — sets guardian in storage | [U] | P1 |
| LOG-INIT-2 | `address(0)` — reverts `InvalidGuardianAddress` | [N] | P1 |
| LOG-INIT-3 | Guardian correctly readable via `getGuardian` after initialization | [U] | P1 |
| LOG-INIT-4 | Guardian already initialized (storage != `address(0)`) — reverts (prevents re-initialization) | [S] | P0 |
| LOG-INIT-5 | Initialization touches only `guardian`; pending state remains cleared (`pendingGuardian=0`, `pendingGuardianUpdateTimestamp=0`, `isReady=false`) | [U] | P1 |

---

### 2.2 `initiateGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOG-IGU-1 | Valid new guardian — sets `pendingGuardian` in storage | [U] | P1 |
| LOG-IGU-2 | `address(0)` as new guardian — reverts `InvalidGuardianAddress` | [N] | P1 |
| LOG-IGU-3 | Update already pending (`pendingGuardian != address(0)`) — reverts `GuardianUpdateAlreadyPending` | [N] | P1 |
| LOG-IGU-4 | `canFinalizeAtTimestamp` computed correctly (`block.timestamp + timelock duration`) | [U] | P1 |
| LOG-IGU-5 | Sets `isGuardianUpdateReadyForAcceptance = false` | [U] | P1 |
| LOG-IGU-6 | Emits `GuardianUpdateInitiated(currentGuardian, newGuardian, canFinalizeAtTimestamp)` | [EV] | P1 |
| LOG-IGU-7 | Current guardian remains unchanged during pending state | [U] | P1 |
| LOG-IGU-8 | Same address as current guardian — still succeeds (not prohibited) | [E] | P2 |

---

### 2.3 `finalizeGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOG-FGU-1 | After timelock expires — sets `isGuardianUpdateReadyForAcceptance = true` | [U] | P1 |
| LOG-FGU-2 | Before timelock expires — reverts `TimelockNotExpired` | [N] | P1 |
| LOG-FGU-3 | At exactly timelock expiry timestamp — succeeds | [E] | P1 |
| LOG-FGU-4 | No pending update (`pendingGuardian == address(0)`) — reverts `NoPendingGuardianUpdate` | [N] | P1 |
| LOG-FGU-5 | Emits `GuardianUpdateFinalized(pendingGuardian)` | [EV] | P1 |
| LOG-FGU-6 | Finalize does NOT change guardian — only marks ready for acceptance | [U] | P1 |
| LOG-FGU-7 | Double finalize at library level — second call sets flag to true again (no-op effectively) | [E] | P2 |

---

### 2.4 `cancelGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOG-CGU-1 | Clears `pendingGuardian` to `address(0)` | [U] | P1 |
| LOG-CGU-2 | Clears `pendingGuardianUpdateTimestamp` to 0 | [U] | P1 |
| LOG-CGU-3 | Clears `isGuardianUpdateReadyForAcceptance` to false | [U] | P1 |
| LOG-CGU-4 | No pending update — reverts `NoPendingGuardianUpdate` | [N] | P1 |
| LOG-CGU-5 | Emits `GuardianUpdateCancelled(currentGuardian, cancelledGuardian)` | [EV] | P1 |
| LOG-CGU-6 | Cancel before finalize — clears pending state correctly | [U] | P1 |
| LOG-CGU-7 | Cancel after finalize but before accept — clears ready-for-acceptance state | [U] | P1 |
| LOG-CGU-8 | Cancel after finalize then call `acceptGuardian` — reverts `NoPendingGuardianUpdate` | [N] | P1 |

---

### 2.5 `acceptGuardian`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOG-AG-1 | Updates `guardian` to `pendingGuardian` address | [U] | P1 |
| LOG-AG-2 | Clears `pendingGuardian` to `address(0)` | [U] | P1 |
| LOG-AG-3 | Clears `pendingGuardianUpdateTimestamp` to 0 | [U] | P1 |
| LOG-AG-4 | Clears `isGuardianUpdateReadyForAcceptance` to false | [U] | P1 |
| LOG-AG-5 | No pending update (`pendingGuardian == address(0)`) — reverts `NoPendingGuardianUpdate` | [N] | P1 |
| LOG-AG-6 | Not ready for acceptance (`isGuardianUpdateReadyForAcceptance == false`) — reverts `GuardianUpdateNotReadyForAcceptance` | [N] | P1 |
| LOG-AG-7 | Emits `GuardianUpdateAccepted(previousGuardian, newGuardian)` | [EV] | P1 |
| LOG-AG-8 | After acceptance, old guardian address is no longer the guardian | [S] | P1 |
| LOG-AG-9 | After acceptance, new guardian address is the guardian | [U] | P1 |

---

### 2.6 `enforceOnlyGuardian`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOG-EOG-1 | `msg.sender == guardian` — no revert | [U] | P0 |
| LOG-EOG-2 | `msg.sender != guardian` — reverts `UnauthorizedGuardian(msg.sender, guardian)` | [N] | P0 |
| LOG-EOG-3 | Error includes both caller address and expected guardian address | [U] | P1 |

---

### 2.7 `enforceOnlyPendingGuardian`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOG-EPG-1 | `msg.sender == pendingGuardian` — no revert | [U] | P0 |
| LOG-EPG-2 | `msg.sender != pendingGuardian` — reverts `UnauthorizedGuardianAcceptance(msg.sender, pendingGuardian)` | [N] | P0 |
| LOG-EPG-3 | No pending update (`pendingGuardian == address(0)`) — any address reverts | [E] | P0 |
| LOG-EPG-4 | Error includes both caller address and expected pending guardian address | [U] | P1 |

---

### 2.8 View Functions (Lib)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOG-VIEW-1 | `getGuardian` returns current guardian address | [U] | P3 |
| LOG-VIEW-2 | `getPendingGuardian` returns `address(0)` when no pending update | [U] | P3 |
| LOG-VIEW-3 | `getPendingGuardian` returns correct address during pending update | [U] | P3 |
| LOG-VIEW-4 | `getPendingGuardianUpdateTimestamp` returns 0 when no pending update | [U] | P3 |
| LOG-VIEW-5 | `getPendingGuardianUpdateTimestamp` returns correct timestamp during pending update | [U] | P3 |
| LOG-VIEW-6 | `getIsGuardianUpdateReadyForAcceptance` returns false when no pending update | [U] | P3 |
| LOG-VIEW-7 | `getIsGuardianUpdateReadyForAcceptance` returns false after initiate (before finalize) | [U] | P3 |
| LOG-VIEW-8 | `getIsGuardianUpdateReadyForAcceptance` returns true after finalize | [U] | P3 |

---

## 3. Full Lifecycle Integration Tests

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| GINT-1 | Complete flow: initiate → time passes → finalize → accept — guardian updated | [I] | P1 |
| GINT-2 | Cancel during pending: initiate → cancel → initiate again with different address — works | [I] | P1 |
| GINT-3 | Cancel after finalize: initiate → finalize → cancel → all pending state cleared | [I] | P1 |
| GINT-4 | Multiple sequential updates: complete first update → start and complete second update | [I] | P1 |
| GINT-5 | Normal flow and recovery flow can both be pending at the same time (separate state domains) | [I][S] | P1 |
| GINT-6 | Completing recovery flow updates `guardian` but does not clear normal-flow pending guardian state | [I][S] | P1 |
| GINT-7 | If guardian changes via recovery while normal update is pending, previous guardian loses `onlyGuardian` rights; new guardian controls normal-flow finalize/cancel | [I][S] | P0 |
| GINT-8 | Cancel during pending then wait past the original timelock window — previous pending guardian `acceptGuardian` still reverts (no pending guardian after cancel) | [I] | P1 |
| GINT-9 | Cancel after finalize — previous pending guardian `acceptGuardian` reverts (canceled finalized update cannot be accepted) | [I] | P1 |

---

## 4. Fuzz Tests

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| GFZ-1 | Fuzz: Random valid addresses as new guardian — update flow completes | [F] | P1 |
| GFZ-2 | Fuzz: Random timestamps before/after timelock — correct pass/fail on finalize | [F] | P1 |
| GFZ-3 | Fuzz: `address(0)` always reverts `InvalidGuardianAddress` on initiate | [F] | P1 |
| GFZ-4 | Fuzz: Random non-pending-guardian addresses always revert on `enforceOnlyPendingGuardian` | [F] | P1 |
| GFZ-5 | Fuzz: Random timelock durations — `canFinalizeAtTimestamp` always equals `block.timestamp + duration` | [F] | P1 |
| GFZ-6 | Fuzz: Random addresses — `enforceOnlyGuardian` always passes for correct guardian, fails for others | [F] | P0 |

---

## 5. Invariant Tests

| ID | Invariant | Priority |
|---|-----------|----------|
| GINV-1 | **Guardian always set**: `guardian() != address(0)` after initialization | P0 |
| GINV-2 | **Pending exclusivity**: At most one pending guardian update at a time | P0 |
| GINV-3 | **Timelock enforcement**: Guardian cannot change without timelock expiry + finalize + accept | P0 |
| GINV-4 | **State consistency**: If `pendingGuardian == address(0)`, then `pendingGuardianUpdateTimestamp == 0` AND `isGuardianUpdateReadyForAcceptance == false` | P0 |
| GINV-5 | **Accept clears all**: After `acceptGuardian`, all three pending fields are reset (`address(0)`, `0`, `false`) | P0 |
| GINV-6 | **Guardian mutation point**: In normal flow, `guardian` is only modified by `acceptGuardian` (never by initiate/finalize/cancel) | P0 |
| GINV-7 | **Ready-state coherence**: If `isGuardianUpdateReadyForAcceptance == true`, then `pendingGuardian != address(0)` AND `pendingGuardianUpdateTimestamp != 0` | P0 |
| GINV-8 | **Pending timestamp coherence**: If `pendingGuardian != address(0)`, then `pendingGuardianUpdateTimestamp != 0` | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `initiateGuardianUpdate` (Base) | 10 | P0-P1 |
| `finalizeGuardianUpdate` (Base) | 10 | P0-P1 |
| `cancelGuardianUpdate` (Base) | 10 | P0-P1 |
| `acceptGuardian` (Base) | 4 | P0-P1 |
| View functions (Base) | 5 | P3 |
| `initializeGuardian` | 5 | P0-P1 |
| `initiateGuardianUpdate` (Lib) | 8 | P1-P2 |
| `finalizeGuardianUpdate` (Lib) | 7 | P1-P2 |
| `cancelGuardianUpdate` (Lib) | 8 | P1 |
| `acceptGuardian` (Lib) | 9 | P1 |
| `enforceOnlyGuardian` | 3 | P0-P1 |
| `enforceOnlyPendingGuardian` | 4 | P0-P1 |
| View functions (Lib) | 8 | P3 |
| Full lifecycle integration | 9 | P0-P1 |
| Fuzz tests | 6 | P0-P1 |
| Invariant tests | 8 | P0 |
| **Total** | **114** | |
