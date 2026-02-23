# 11 — Guardian Recovery Test Plan

**Files Under Test:**
- `src/organization/base/OrganizationGuardianRecoveryBase.sol`
- `src/organization/libraries/LibOrganizationGuardianRecovery.sol`


---

## File 1: OrganizationGuardianRecoveryBase.sol

### 1.1 `initiateRecoveryGuardianUpdate`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Non-recovery-address caller — reverts (onlyGuardianRecoveryAddress modifier) | [N] | P0 |
| 2 | Recovery address caller — delegates to `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate` | [U] | P1 |

---

### 1.2 `finalizeRecoveryGuardianUpdate`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 3 | Non-recovery-address caller — reverts (onlyGuardianRecoveryAddress modifier) | [N] | P0 |
| 4 | Recovery address caller — delegates to `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate` | [U] | P1 |

---

### 1.3 `cancelRecoveryGuardianUpdate`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 5 | Non-recovery-address caller — reverts (onlyGuardianRecoveryAddress modifier) | [N] | P0 |
| 6 | Recovery address caller — delegates to `LibOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate` | [U] | P1 |

---

### 1.4 `acceptGuardianRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 7 | Non-pending-guardian caller — reverts (onlyRecoveryPendingGuardian modifier) | [N] | P0 |
| 8 | Recovery pending guardian caller — delegates to `LibOrganizationGuardianRecovery.acceptGuardianRecovery` | [U] | P1 |

---

### 1.5 `initiateInitializeGuardianRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 9 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| 10 | Insufficient admin signatures — reverts | [N] | P0 |
| 11 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| 12 | `OperationType` is `InitiateInitializeGuardianRecovery` in admin auth | [U] | P1 |
| 13 | `operationData` encodes `(recoveryAddress, timelockDurationSeconds)` | [U] | P1 |
| 14 | Delegates to `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` | [U] | P1 |

---

### 1.6 `finalizeInitializeGuardianRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 15 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| 16 | Insufficient admin signatures — reverts | [N] | P0 |
| 17 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| 18 | `OperationType` is `FinalizeInitializeGuardianRecovery` in admin auth | [U] | P1 |
| 19 | `operationData` encodes pending values `(pendingRecoveryAddress, pendingTimelockDurationSeconds)` from storage | [U] | P1 |
| 20 | Delegates to `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` | [U] | P1 |

---

### 1.7 `cancelInitializeGuardianRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 21 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| 22 | Insufficient admin signatures — reverts | [N] | P0 |
| 23 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| 24 | `OperationType` is `CancelInitializeGuardianRecovery` in admin auth | [U] | P1 |
| 25 | `operationData` encodes pending values `(pendingRecoveryAddress, pendingTimelockDurationSeconds)` from storage | [U] | P1 |
| 26 | Delegates to `LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery` | [U] | P1 |

---

### 1.8 `getGuardianRecoveryState` (view)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 27 | Returns full `GuardianRecoveryState` struct from storage | [U] | P3 |
| 28 | Callable by anyone (no access restriction) | [U] | P3 |
| 29 | Returns zeroed struct when no recovery is configured | [U] | P3 |
| 30 | Returns correct config after `initializeGuardianRecovery` | [U] | P3 |
| 31 | Returns correct pending state during recovery update flow | [U] | P3 |
| 32 | Returns correct pending init state during deferred init flow | [U] | P3 |

---

## File 2: LibOrganizationGuardianRecovery.sol

> Note: All public functions in this library are called via DELEGATECALL (library deployed as
> separate contract for bytecode size savings). The 3 private functions
> (`_clearPendingGuardianRecoveryInitTimelock`, `_validateGuardianRecoveryNotConfiguredOrRevert`,
> `_validateGuardianRecoveryParamsOrRevert`) need to be converted to `internal` and exposed via
> a test harness for direct testing.

### 2.1 `initializeGuardianRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 33 | Valid address + valid timelock duration — sets `recoveryAddress` in storage | [U] | P1 |
| 34 | Valid address + valid timelock duration — sets `timelockDurationSeconds` in storage | [U] | P1 |
| 35 | `address(0)` — reverts `InvalidGuardianRecoveryAddress` | [N] | P1 |
| 36 | Timelock below minimum (< 2 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| 37 | Timelock above maximum (> 30 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| 38 | Already configured (`recoveryAddress` non-zero) — reverts `GuardianRecoveryAlreadyConfigured` | [N] | P0 |
| 39 | Already configured (`timelockDurationSeconds` non-zero) — reverts `GuardianRecoveryAlreadyConfigured` | [N] | P0 |
| 40 | Values readable via `getGuardianRecoveryState()` after initialization | [U] | P1 |

---

### 2.2 `initiateRecoveryGuardianUpdate`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 41 | Valid new guardian — sets `pendingGuardian` in recovery storage | [U] | P1 |
| 42 | `pendingGuardianTimestamp` computed as `block.timestamp + timelockDurationSeconds` | [U] | P1 |
| 43 | Sets `isUpdateReadyForAcceptance = false` | [U] | P1 |
| 44 | `address(0)` as new guardian — reverts `InvalidNewGuardianAddress` | [N] | P1 |
| 45 | Update already pending (`pendingGuardian != address(0)`) — reverts `RecoveryGuardianUpdateAlreadyPending` | [N] | P1 |
| 46 | Emits `RecoveryGuardianUpdateInitiated(currentGuardian, newGuardian, canFinalizeAtTimestamp)` | [EV] | P1 |
| 47 | Event `currentGuardian` is read from normal guardian storage (not recovery storage) | [U] | P1 |
| 48 | Current guardian remains unchanged during pending state | [U] | P1 |
| 49 | Same address as current guardian — succeeds (no validation against current) | [E] | P2 |

---

### 2.3 `finalizeRecoveryGuardianUpdate`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 50 | After timelock expires — sets `isUpdateReadyForAcceptance = true` | [U] | P1 |
| 51 | Before timelock expires — reverts `TimelockNotExpired` | [N] | P1 |
| 52 | At exactly timelock expiry timestamp — succeeds | [E] | P1 |
| 53 | No pending update (`pendingGuardian == address(0)`) — reverts `NoPendingRecoveryGuardianUpdate` | [N] | P1 |
| 54 | Emits `RecoveryGuardianUpdateFinalized(pendingGuardian)` | [EV] | P1 |
| 55 | Finalize does NOT change guardian — only marks ready for acceptance | [U] | P1 |
| 56 | `pendingGuardian` and `pendingGuardianTimestamp` remain unchanged after finalize | [U] | P1 |
| 57 | Double finalize — second call sets flag to true again (no-op effectively) | [E] | P2 |

---

### 2.4 `cancelRecoveryGuardianUpdate`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 58 | Clears `pendingGuardian` to `address(0)` | [U] | P1 |
| 59 | Clears `pendingGuardianTimestamp` to 0 | [U] | P1 |
| 60 | Clears `isUpdateReadyForAcceptance` to false | [U] | P1 |
| 61 | No pending update (`pendingGuardian == address(0)`) — reverts `NoPendingRecoveryGuardianUpdate` | [N] | P1 |
| 62 | Emits `RecoveryGuardianUpdateCancelled(cancelledGuardian)` | [EV] | P1 |
| 63 | Cancel before finalize — clears pending state correctly | [U] | P1 |
| 64 | Cancel after finalize but before accept — clears ready-for-acceptance state | [U] | P1 |
| 65 | Recovery config (`recoveryAddress`, `timelockDurationSeconds`) unchanged after cancel | [U] | P1 |

---

### 2.5 `acceptGuardianRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 66 | Updates `guardian` in NORMAL guardian storage (not recovery storage) | [S] | P0 |
| 67 | Clears `pendingGuardian` to `address(0)` in recovery storage | [U] | P1 |
| 68 | Clears `pendingGuardianTimestamp` to 0 in recovery storage | [U] | P1 |
| 69 | Clears `isUpdateReadyForAcceptance` to false in recovery storage | [U] | P1 |
| 70 | No pending update (`pendingGuardian == address(0)`) — reverts `NoPendingRecoveryGuardianUpdate` | [N] | P1 |
| 71 | Not ready for acceptance (`isUpdateReadyForAcceptance == false`) — reverts `RecoveryGuardianUpdateNotReadyForAcceptance` | [N] | P1 |
| 72 | Emits `RecoveryGuardianUpdateAccepted(previousGuardian, newGuardian)` | [EV] | P1 |
| 73 | After acceptance, old guardian address is no longer the guardian | [S] | P1 |
| 74 | After acceptance, new guardian address is the guardian | [U] | P1 |
| 75 | Recovery config (`recoveryAddress`, `timelockDurationSeconds`) unchanged after accept | [U] | P1 |

---

### 2.6 `initiateInitializeGuardianRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 76 | Valid params — sets `pendingInit.pendingRecoveryAddress` in storage | [U] | P1 |
| 77 | Valid params — sets `pendingInit.pendingTimelockDurationSeconds` in storage | [U] | P1 |
| 78 | `pendingInit.pendingTimestamp` computed via `LibOrganizationAdminOperationTimelock.computeCanFinalizeAtTimestamp()` | [U] | P1 |
| 79 | Already configured (`recoveryAddress` non-zero) — reverts `GuardianRecoveryAlreadyConfigured` | [N] | P0 |
| 80 | Already pending (`pendingInit.pendingTimestamp != 0`) — reverts `GuardianRecoveryInitializationAlreadyPending` | [N] | P1 |
| 81 | `address(0)` recovery address — reverts `InvalidGuardianRecoveryAddress` | [N] | P1 |
| 82 | Timelock below minimum — reverts `InvalidTimelockDuration` | [N] | P1 |
| 83 | Timelock above maximum — reverts `InvalidTimelockDuration` | [N] | P1 |
| 84 | Emits `GuardianRecoveryInitializationInitiated(recoveryAddress, timelockDurationSeconds, canFinalizeAtTimestamp)` | [EV] | P1 |
| 85 | Validation order: not-configured check before already-pending check | [U] | P1 |

---

### 2.7 `finalizeInitializeGuardianRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 86 | After timelock expires — sets `recoveryAddress` and `timelockDurationSeconds` in config | [U] | P1 |
| 87 | No pending initialization (`pendingTimestamp == 0`) — reverts `NoGuardianRecoveryInitializationPending` | [N] | P1 |
| 88 | Before timelock expires — reverts `TimelockNotExpired` | [N] | P1 |
| 89 | At exactly timelock expiry timestamp — succeeds | [E] | P1 |
| 90 | Clears all `pendingInit` fields after finalization (delegates to `_clearPendingGuardianRecoveryInitTimelock`) | [U] | P1 |
| 91 | Delegates to `initializeGuardianRecovery` for validation and config writes | [U] | P1 |
| 92 | Emits `GuardianRecoveryInitializationFinalized(pendingAddress, pendingTimelock)` | [EV] | P1 |
| 93 | After finalization, recovery flow (initiate/finalize/cancel/accept) can be used | [I] | P1 |

---

### 2.8 `cancelInitializeGuardianRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 94 | No pending initialization (`pendingTimestamp == 0`) — reverts `NoGuardianRecoveryInitializationPending` | [N] | P1 |
| 95 | Clears `pendingInit.pendingRecoveryAddress` to `address(0)` | [U] | P1 |
| 96 | Clears `pendingInit.pendingTimelockDurationSeconds` to 0 | [U] | P1 |
| 97 | Clears `pendingInit.pendingTimestamp` to 0 | [U] | P1 |
| 98 | Emits `GuardianRecoveryInitializationCancelled()` | [EV] | P1 |
| 99 | Recovery config (`recoveryAddress`, `timelockDurationSeconds`) remain zero after cancel | [U] | P1 |
| 100 | Can initiate again after cancel | [U] | P1 |

---

### 2.9 `enforceOnlyGuardianRecoveryAddress`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 101 | `msg.sender == recoveryAddress` — no revert | [U] | P0 |
| 102 | `msg.sender != recoveryAddress` — reverts `UnauthorizedGuardianRecoveryAddress(msg.sender, expected)` | [N] | P0 |
| 103 | Error includes both caller address and expected recovery address | [U] | P1 |
| 104 | Recovery not configured (`recoveryAddress == address(0)`) — any address reverts | [E] | P0 |

---

### 2.10 `enforceOnlyRecoveryPendingGuardian`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 105 | `msg.sender == pendingGuardian` — no revert | [U] | P0 |
| 106 | `msg.sender != pendingGuardian` — reverts `UnauthorizedRecoveryGuardianAcceptance(msg.sender, pendingGuardian)` | [N] | P0 |
| 107 | No pending update (`pendingGuardian == address(0)`) — any address reverts | [E] | P0 |

---

### 2.11 `_clearPendingGuardianRecoveryInitTimelock` (private → internal)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 108 | After clear: `pendingInit.pendingRecoveryAddress == address(0)` | [U] | P1 |
| 109 | After clear: `pendingInit.pendingTimelockDurationSeconds == 0` | [U] | P1 |
| 110 | After clear: `pendingInit.pendingTimestamp == 0` | [U] | P1 |
| 111 | Clearing already-zeroed state — no-op, no revert | [E] | P2 |

---

### 2.12 `_validateGuardianRecoveryNotConfiguredOrRevert` (private → internal)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 112 | Both `recoveryAddress` and `timelockDurationSeconds` zero — succeeds (not configured) | [U] | P1 |
| 113 | `recoveryAddress` non-zero, `timelockDurationSeconds` zero — reverts `GuardianRecoveryAlreadyConfigured` | [N] | P1 |
| 114 | `recoveryAddress` zero, `timelockDurationSeconds` non-zero — reverts `GuardianRecoveryAlreadyConfigured` | [N] | P1 |
| 115 | Both non-zero — reverts `GuardianRecoveryAlreadyConfigured` | [N] | P1 |

---

### 2.13 `_validateGuardianRecoveryParamsOrRevert` (private → internal)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 116 | Valid address + valid timelock duration — succeeds | [U] | P1 |
| 117 | `recoveryAddress == address(0)` — reverts `InvalidGuardianRecoveryAddress` | [N] | P1 |
| 118 | Timelock below minimum (< 2 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| 119 | Timelock above maximum (> 30 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| 120 | Timelock at exact minimum boundary (2 days) — succeeds | [E] | P1 |
| 121 | Timelock at exact maximum boundary (30 days) — succeeds | [E] | P1 |
| 122 | Timelock at 0 seconds — reverts `InvalidTimelockDuration` | [E] | P1 |

---

## 3. Full Lifecycle Integration Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 123 | Complete recovery flow: initiate → time passes → finalize → accept — guardian updated in normal storage | [I] | P0 |
| 124 | Cancel during pending: initiate → cancel → initiate again with different address — works | [I] | P1 |
| 125 | Cancel after finalize: initiate → finalize → cancel → all pending state cleared | [I] | P1 |
| 126 | Deferred init lifecycle: initiateInit → time passes → finalizeInit → recovery config set | [I] | P1 |
| 127 | Deferred init cancel + retry: initiateInit → cancelInit → initiateInit again — works | [I] | P1 |
| 128 | Full lifecycle after deferred init: initiateInit → finalizeInit → initiateRecovery → finalize → accept | [I] | P1 |
| 129 | Recovery and normal guardian update in parallel — both can run simultaneously, both complete independently | [I] | P0 |
| 130 | After recovery completes, normal guardian flow can be used by the new guardian | [I] | P1 |
| 131 | After normal guardian update completes, recovery flow can still be used by recovery address | [I] | P1 |
| 132 | Multiple sequential recovery updates: complete first → start and complete second | [I] | P1 |

---

## 4. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 133 | Fuzz: Random non-zero recovery addresses with valid timelock durations always configure successfully | [F] | P1 |
| 134 | Fuzz: Random timelock durations in [2 days, 30 days] always accepted by `_validateGuardianRecoveryParamsOrRevert` | [F] | P1 |
| 135 | Fuzz: Random timelock durations outside [2 days, 30 days] always revert `InvalidTimelockDuration` | [F] | P1 |
| 136 | Fuzz: Random timestamps before timelock expiry — finalize always reverts `TimelockNotExpired` | [F] | P1 |
| 137 | Fuzz: Random timestamps at/after timelock expiry — finalize always succeeds | [F] | P1 |
| 138 | Fuzz: Random valid addresses as new guardian — recovery update flow completes | [F] | P1 |
| 139 | Fuzz: Random non-recovery addresses always revert on `enforceOnlyGuardianRecoveryAddress` | [F] | P0 |
| 140 | Fuzz: Random non-pending-guardian addresses always revert on `enforceOnlyRecoveryPendingGuardian` | [F] | P0 |
| 141 | Fuzz: Random guardian recovery timelock durations — `canFinalizeAtTimestamp` always equals `block.timestamp + duration` | [F] | P1 |
| 142 | Fuzz: `address(0)` always reverts `InvalidNewGuardianAddress` on `initiateRecoveryGuardianUpdate` | [F] | P1 |

---

## 5. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 143 | **Recovery isolation**: Recovery pending state (`pendingGuardian`, `pendingGuardianTimestamp`, `isUpdateReadyForAcceptance`) never modifies normal guardian pending state and vice versa | P0 |
| 144 | **Guardian always valid**: After any recovery accept operation completes, `guardian() != address(0)` | P0 |
| 145 | **Timelock enforcement**: Recovery guardian cannot change without timelock expiry + finalize + accept | P0 |
| 146 | **State consistency**: If `pendingGuardian == address(0)` in recovery storage, then `pendingGuardianTimestamp == 0` AND `isUpdateReadyForAcceptance == false` | P0 |
| 147 | **Accept clears all recovery pending**: After `acceptGuardianRecovery`, all three recovery pending fields are reset (`address(0)`, `0`, `false`) | P0 |
| 148 | **Config immutability**: `recoveryAddress` and `timelockDurationSeconds` never change after initialization (only set once) | P0 |
| 149 | **Deferred init state consistency**: If `pendingInit.pendingTimestamp == 0`, then `pendingInit.pendingRecoveryAddress == address(0)` AND `pendingInit.pendingTimelockDurationSeconds == 0` | P0 |
| 150 | **Tx recovery isolation**: Guardian recovery operations never modify tx recovery state | P0 |
| 151 | **Accept writes to normal storage**: `acceptGuardianRecovery` always writes to `LibOrganizationGuardianStorage.layout().guardian`, never to recovery storage's config fields | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `initiateRecoveryGuardianUpdate` (Base) | 2 | P0-P1 |
| `finalizeRecoveryGuardianUpdate` (Base) | 2 | P0-P1 |
| `cancelRecoveryGuardianUpdate` (Base) | 2 | P0-P1 |
| `acceptGuardianRecovery` (Base) | 2 | P0-P1 |
| `initiateInitializeGuardianRecovery` (Base) | 6 | P0-P1 |
| `finalizeInitializeGuardianRecovery` (Base) | 6 | P0-P1 |
| `cancelInitializeGuardianRecovery` (Base) | 6 | P0-P1 |
| `getGuardianRecoveryState` (Base) | 6 | P3 |
| `initializeGuardianRecovery` (Lib) | 8 | P0-P1 |
| `initiateRecoveryGuardianUpdate` (Lib) | 9 | P1-P2 |
| `finalizeRecoveryGuardianUpdate` (Lib) | 8 | P1-P2 |
| `cancelRecoveryGuardianUpdate` (Lib) | 8 | P1 |
| `acceptGuardianRecovery` (Lib) | 10 | P0-P1 |
| `initiateInitializeGuardianRecovery` (Lib) | 10 | P0-P1 |
| `finalizeInitializeGuardianRecovery` (Lib) | 8 | P1 |
| `cancelInitializeGuardianRecovery` (Lib) | 7 | P1 |
| `enforceOnlyGuardianRecoveryAddress` | 4 | P0-P1 |
| `enforceOnlyRecoveryPendingGuardian` | 3 | P0 |
| `_clearPendingGuardianRecoveryInitTimelock` | 4 | P1-P2 |
| `_validateGuardianRecoveryNotConfiguredOrRevert` | 4 | P1 |
| `_validateGuardianRecoveryParamsOrRevert` | 7 | P1 |
| Full lifecycle integration | 10 | P0-P1 |
| Fuzz tests | 10 | P0-P1 |
| Invariant tests | 9 | P0 |
| **Total** | **151** | |
