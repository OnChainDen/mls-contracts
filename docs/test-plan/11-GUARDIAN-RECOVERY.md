# 11 — Guardian Recovery Test Plan

**Files Under Test:**
- `src/organization/base/OrganizationGuardianRecoveryBase.sol`
- `src/organization/libraries/LibOrganizationGuardianRecovery.sol`

**Private Function Testability Plan (Global):**
All `private` functions in the files under test will be refactored to `internal` for testing and exposed via test harness contracts.

| File | Private functions to convert to `internal` for harness testing |
|---|---|
| `OrganizationGuardianRecoveryBase.sol` | None |
| `LibOrganizationGuardianRecovery.sol` | `_clearPendingGuardianRecoveryInitTimelock`, `_validateGuardianRecoveryNotConfiguredOrRevert`, `_validateGuardianRecoveryParamsOrRevert` |


---

## File 1: OrganizationGuardianRecoveryBase.sol

### 1.1 `initiateRecoveryGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGRB-IRGU-1 | Non-recovery-address caller — reverts (onlyGuardianRecoveryAddress modifier) | [N] | P0 |
| OGRB-IRGU-2 | Recovery address caller — delegates to `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate` | [U] | P1 |

---

### 1.2 `finalizeRecoveryGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGRB-FRGU-1 | Non-recovery-address caller — reverts (onlyGuardianRecoveryAddress modifier) | [N] | P0 |
| OGRB-FRGU-2 | Recovery address caller — delegates to `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate` | [U] | P1 |

---

### 1.3 `cancelRecoveryGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGRB-CRGU-1 | Non-recovery-address caller — reverts (onlyGuardianRecoveryAddress modifier) | [N] | P0 |
| OGRB-CRGU-2 | Recovery address caller — delegates to `LibOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate` | [U] | P1 |

---

### 1.4 `acceptGuardianRecovery`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGRB-AGR-1 | Non-pending-guardian caller — reverts (onlyRecoveryPendingGuardian modifier) | [N] | P0 |
| OGRB-AGR-2 | Recovery pending guardian caller — delegates to `LibOrganizationGuardianRecovery.acceptGuardianRecovery` | [U] | P1 |

---

### 1.5 `initiateInitializeGuardianRecovery`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGRB-IIGR-1 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| OGRB-IIGR-2 | Insufficient admin signatures — reverts | [N] | P0 |
| OGRB-IIGR-3 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| OGRB-IIGR-4 | `OperationType` is `InitiateInitializeGuardianRecovery` in admin auth | [U] | P1 |
| OGRB-IIGR-5 | `operationData` encodes `(recoveryAddress, timelockDurationSeconds)` | [U] | P1 |
| OGRB-IIGR-6 | Delegates to `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` | [U] | P1 |
| OGRB-IIGR-7 | `isApproval` passed to admin auth validation is `true` (execution path, not rejection path) | [U][S] | P1 |
| OGRB-IIGR-8 | **Desired Behavior:** if downstream library call reverts (e.g., invalid params/already configured), admin nonce is not permanently consumed; same signed request can succeed after fixing root cause | [S] | P0 |
| OGRB-IIGR-9 | **Desired Behavior:** signed `operationData` is bound to `recoveryAddress`; signatures for `(recoveryAddress=A, timelock=T)` cannot execute with `(recoveryAddress=B, timelock=T)` | [S] | P0 |
| OGRB-IIGR-10 | **Desired Behavior:** signed `operationData` is bound to `timelockDurationSeconds`; signatures for `(recoveryAddress=A, timelock=T1)` cannot execute with `(recoveryAddress=A, timelock=T2)` | [S] | P0 |
| OGRB-IIGR-11 | **Desired Behavior:** expired admin auth (`expirationTimestamp < block.timestamp`) reverts and nonce is not burned (same `operationType` + `operationData` + `salt` remains usable with fresh signatures) | [N][S] | P0 |

---

### 1.6 `finalizeInitializeGuardianRecovery`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGRB-FIGR-1 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| OGRB-FIGR-2 | Insufficient admin signatures — reverts | [N] | P0 |
| OGRB-FIGR-3 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| OGRB-FIGR-4 | `OperationType` is `FinalizeInitializeGuardianRecovery` in admin auth | [U] | P1 |
| OGRB-FIGR-5 | `operationData` encodes pending values `(pendingRecoveryAddress, pendingTimelockDurationSeconds)` from storage | [U] | P1 |
| OGRB-FIGR-6 | Delegates to `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` | [U] | P1 |
| OGRB-FIGR-7 | `isApproval` passed to admin auth validation is `true` (execution path, not rejection path) | [U][S] | P1 |
| OGRB-FIGR-8 | **Desired Behavior:** admin signatures are bound to current pending init tuple; signatures over stale `(pendingRecoveryAddress, pendingTimelockDurationSeconds)` revert after pending values change | [S] | P0 |
| OGRB-FIGR-9 | **Desired Behavior:** if downstream finalize reverts (`NoGuardianRecoveryInitializationPending` or `TimelockNotExpired`), admin nonce/state changes roll back (same signed request remains usable once conditions are met) | [S] | P0 |
| OGRB-FIGR-10 | **Desired Behavior:** signed finalize `operationData` is bound to `pendingRecoveryAddress`; signatures over stale pending address fail after pending address changes | [S] | P0 |
| OGRB-FIGR-11 | **Desired Behavior:** signed finalize `operationData` is bound to `pendingTimelockDurationSeconds`; signatures over stale pending timelock fail after pending timelock changes | [S] | P0 |
| OGRB-FIGR-12 | **Desired Behavior:** expired admin auth (`expirationTimestamp < block.timestamp`) reverts and nonce is not burned (same `operationType` + `operationData` + `salt` remains usable with fresh signatures) | [N][S] | P0 |

---

### 1.7 `cancelInitializeGuardianRecovery`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGRB-CIGR-1 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| OGRB-CIGR-2 | Insufficient admin signatures — reverts | [N] | P0 |
| OGRB-CIGR-3 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| OGRB-CIGR-4 | `OperationType` is `CancelInitializeGuardianRecovery` in admin auth | [U] | P1 |
| OGRB-CIGR-5 | `operationData` encodes pending values `(pendingRecoveryAddress, pendingTimelockDurationSeconds)` from storage | [U] | P1 |
| OGRB-CIGR-6 | Delegates to `LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery` | [U] | P1 |
| OGRB-CIGR-7 | `isApproval` passed to admin auth validation is `true` (execution path, not rejection path) | [U][S] | P1 |
| OGRB-CIGR-8 | **Desired Behavior:** cancel requires `OperationType.CancelInitializeGuardianRecovery`; signatures for initiate/finalize or rejection payloads cannot authorize cancel | [S] | P0 |
| OGRB-CIGR-9 | **Desired Behavior:** if downstream cancel reverts (`NoGuardianRecoveryInitializationPending`), admin nonce/state changes roll back (same signed request remains usable after pending state exists) | [S] | P0 |
| OGRB-CIGR-10 | **Desired Behavior:** signed cancel `operationData` is bound to `pendingRecoveryAddress`; signatures over stale pending address fail after pending address changes | [S] | P0 |
| OGRB-CIGR-11 | **Desired Behavior:** signed cancel `operationData` is bound to `pendingTimelockDurationSeconds`; signatures over stale pending timelock fail after pending timelock changes | [S] | P0 |
| OGRB-CIGR-12 | **Desired Behavior:** expired admin auth (`expirationTimestamp < block.timestamp`) reverts and nonce is not burned (same `operationType` + `operationData` + `salt` remains usable with fresh signatures) | [N][S] | P0 |

---

### 1.8 `getGuardianRecoveryState` (view)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGRB-GGRS-1 | Returns full `GuardianRecoveryState` struct from storage | [U] | P3 |
| OGRB-GGRS-2 | Callable by anyone (no access restriction) | [U] | P3 |
| OGRB-GGRS-3 | Returns zeroed struct when no recovery is configured | [U] | P3 |
| OGRB-GGRS-4 | Returns correct config after `initializeGuardianRecovery` | [U] | P3 |
| OGRB-GGRS-5 | Returns correct pending state during recovery update flow | [U] | P3 |
| OGRB-GGRS-6 | Returns correct pending init state during deferred init flow | [U] | P3 |

---

## File 2: LibOrganizationGuardianRecovery.sol

> Note: All public functions in this library are called via DELEGATECALL (library deployed as
> separate contract for bytecode size savings). The 3 private functions
> (`_clearPendingGuardianRecoveryInitTimelock`, `_validateGuardianRecoveryNotConfiguredOrRevert`,
> `_validateGuardianRecoveryParamsOrRevert`) need to be converted to `internal` and exposed via
> a test harness for direct testing.

### 2.1 `initializeGuardianRecovery`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOGR-IGR-1 | Valid address + valid timelock duration — sets `recoveryAddress` in storage | [U] | P1 |
| LOGR-IGR-2 | Valid address + valid timelock duration — sets `timelockDurationSeconds` in storage | [U] | P1 |
| LOGR-IGR-3 | `address(0)` — reverts `InvalidGuardianRecoveryAddress` | [N] | P1 |
| LOGR-IGR-4 | Timelock below minimum (< 2 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| LOGR-IGR-5 | Timelock above maximum (> 30 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| LOGR-IGR-6 | Already configured (`recoveryAddress` non-zero) — reverts `GuardianRecoveryAlreadyConfigured` | [N] | P0 |
| LOGR-IGR-7 | Already configured (`timelockDurationSeconds` non-zero) — reverts `GuardianRecoveryAlreadyConfigured` | [N] | P0 |
| LOGR-IGR-8 | Values readable via `getGuardianRecoveryState()` after initialization | [U] | P1 |

---

### 2.2 `initiateRecoveryGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOGR-IRGU-1 | Valid new guardian — sets `pendingGuardian` in recovery storage | [U] | P1 |
| LOGR-IRGU-2 | `pendingGuardianTimestamp` computed as `block.timestamp + timelockDurationSeconds` | [U] | P1 |
| LOGR-IRGU-3 | Sets `isUpdateReadyForAcceptance = false` | [U] | P1 |
| LOGR-IRGU-4 | `address(0)` as new guardian — reverts `InvalidNewGuardianAddress` | [N] | P1 |
| LOGR-IRGU-5 | Update already pending (`pendingGuardian != address(0)`) — reverts `RecoveryGuardianUpdateAlreadyPending` | [N] | P1 |
| LOGR-IRGU-6 | Emits `RecoveryGuardianUpdateInitiated(currentGuardian, newGuardian, canFinalizeAtTimestamp)` | [EV] | P1 |
| LOGR-IRGU-7 | Event `currentGuardian` is read from normal guardian storage (not recovery storage) | [U] | P1 |
| LOGR-IRGU-8 | Current guardian remains unchanged during pending state | [U] | P1 |
| LOGR-IRGU-9 | Same address as current guardian — succeeds (no validation against current) | [E] | P2 |

---

### 2.3 `finalizeRecoveryGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOGR-FRGU-1 | After timelock expires — sets `isUpdateReadyForAcceptance = true` | [U] | P1 |
| LOGR-FRGU-2 | Before timelock expires — reverts `TimelockNotExpired` | [N] | P1 |
| LOGR-FRGU-3 | At exactly timelock expiry timestamp — succeeds | [E] | P1 |
| LOGR-FRGU-4 | No pending update (`pendingGuardian == address(0)`) — reverts `NoPendingRecoveryGuardianUpdate` | [N] | P1 |
| LOGR-FRGU-5 | Emits `RecoveryGuardianUpdateFinalized(pendingGuardian)` | [EV] | P1 |
| LOGR-FRGU-6 | Finalize does NOT change guardian — only marks ready for acceptance | [U] | P1 |
| LOGR-FRGU-7 | `pendingGuardian` and `pendingGuardianTimestamp` remain unchanged after finalize | [U] | P1 |
| LOGR-FRGU-8 | Double finalize — second call sets flag to true again (no-op effectively) | [E] | P2 |

---

### 2.4 `cancelRecoveryGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOGR-CRGU-1 | Clears `pendingGuardian` to `address(0)` | [U] | P1 |
| LOGR-CRGU-2 | Clears `pendingGuardianTimestamp` to 0 | [U] | P1 |
| LOGR-CRGU-3 | Clears `isUpdateReadyForAcceptance` to false | [U] | P1 |
| LOGR-CRGU-4 | No pending update (`pendingGuardian == address(0)`) — reverts `NoPendingRecoveryGuardianUpdate` | [N] | P1 |
| LOGR-CRGU-5 | Emits `RecoveryGuardianUpdateCancelled(cancelledGuardian)` | [EV] | P1 |
| LOGR-CRGU-6 | Cancel before finalize — clears pending state correctly | [U] | P1 |
| LOGR-CRGU-7 | Cancel after finalize but before accept — clears ready-for-acceptance state | [U] | P1 |
| LOGR-CRGU-8 | Recovery config (`recoveryAddress`, `timelockDurationSeconds`) unchanged after cancel | [U] | P1 |

---

### 2.5 `acceptGuardianRecovery`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOGR-AGR-1 | Updates `guardian` in NORMAL guardian storage (not recovery storage) | [S] | P0 |
| LOGR-AGR-2 | Clears `pendingGuardian` to `address(0)` in recovery storage | [U] | P1 |
| LOGR-AGR-3 | Clears `pendingGuardianTimestamp` to 0 in recovery storage | [U] | P1 |
| LOGR-AGR-4 | Clears `isUpdateReadyForAcceptance` to false in recovery storage | [U] | P1 |
| LOGR-AGR-5 | No pending update (`pendingGuardian == address(0)`) — reverts `NoPendingRecoveryGuardianUpdate` | [N] | P1 |
| LOGR-AGR-6 | Not ready for acceptance (`isUpdateReadyForAcceptance == false`) — reverts `RecoveryGuardianUpdateNotReadyForAcceptance` | [N] | P1 |
| LOGR-AGR-7 | Emits `RecoveryGuardianUpdateAccepted(previousGuardian, newGuardian)` | [EV] | P1 |
| LOGR-AGR-8 | After acceptance, old guardian address is no longer the guardian | [S] | P1 |
| LOGR-AGR-9 | After acceptance, new guardian address is the guardian | [U] | P1 |
| LOGR-AGR-10 | Recovery config (`recoveryAddress`, `timelockDurationSeconds`) unchanged after accept | [U] | P1 |
| LOGR-AGR-11 | Pending guardian equals current guardian — accept still clears pending recovery state and emits `RecoveryGuardianUpdateAccepted` with `previousGuardian == newGuardian` | [E] | P2 |

---

### 2.6 `initiateInitializeGuardianRecovery`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOGR-IIGR-1 | Valid params — sets `pendingInit.pendingRecoveryAddress` in storage | [U] | P1 |
| LOGR-IIGR-2 | Valid params — sets `pendingInit.pendingTimelockDurationSeconds` in storage | [U] | P1 |
| LOGR-IIGR-3 | `pendingInit.pendingTimestamp` computed via `LibOrganizationAdminOperationTimelock.computeCanFinalizeAtTimestamp()` | [U] | P1 |
| LOGR-IIGR-4 | Already configured (`recoveryAddress` non-zero) — reverts `GuardianRecoveryAlreadyConfigured` | [N] | P0 |
| LOGR-IIGR-5 | Already pending (`pendingInit.pendingTimestamp != 0`) — reverts `GuardianRecoveryInitializationAlreadyPending` | [N] | P1 |
| LOGR-IIGR-6 | `address(0)` recovery address — reverts `InvalidGuardianRecoveryAddress` | [N] | P1 |
| LOGR-IIGR-7 | Timelock below minimum — reverts `InvalidTimelockDuration` | [N] | P1 |
| LOGR-IIGR-8 | Timelock above maximum — reverts `InvalidTimelockDuration` | [N] | P1 |
| LOGR-IIGR-9 | Emits `GuardianRecoveryInitializationInitiated(recoveryAddress, timelockDurationSeconds, canFinalizeAtTimestamp)` | [EV] | P1 |
| LOGR-IIGR-10 | Validation order: not-configured check before already-pending check | [U] | P1 |

---

### 2.7 `finalizeInitializeGuardianRecovery`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOGR-FIGR-1 | After timelock expires — sets `recoveryAddress` and `timelockDurationSeconds` in config | [U] | P1 |
| LOGR-FIGR-2 | No pending initialization (`pendingTimestamp == 0`) — reverts `NoGuardianRecoveryInitializationPending` | [N] | P1 |
| LOGR-FIGR-3 | Before timelock expires — reverts `TimelockNotExpired` | [N] | P1 |
| LOGR-FIGR-4 | At exactly timelock expiry timestamp — succeeds | [E] | P1 |
| LOGR-FIGR-5 | Clears all `pendingInit` fields after finalization (delegates to `_clearPendingGuardianRecoveryInitTimelock`) | [U] | P1 |
| LOGR-FIGR-6 | Delegates to `initializeGuardianRecovery` for validation and config writes | [U] | P1 |
| LOGR-FIGR-7 | Emits `GuardianRecoveryInitializationFinalized(pendingAddress, pendingTimelock)` | [EV] | P1 |
| LOGR-FIGR-8 | After finalization, recovery flow (initiate/finalize/cancel/accept) can be used | [I] | P1 |
| LOGR-FIGR-9 | **Desired Behavior:** if pending init fields are malformed and delegated `initializeGuardianRecovery` reverts, finalization is atomic: pending init fields and config remain unchanged (full rollback) | [S] | P0 |

---

### 2.8 `cancelInitializeGuardianRecovery`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOGR-CIGR-1 | No pending initialization (`pendingTimestamp == 0`) — reverts `NoGuardianRecoveryInitializationPending` | [N] | P1 |
| LOGR-CIGR-2 | Clears `pendingInit.pendingRecoveryAddress` to `address(0)` | [U] | P1 |
| LOGR-CIGR-3 | Clears `pendingInit.pendingTimelockDurationSeconds` to 0 | [U] | P1 |
| LOGR-CIGR-4 | Clears `pendingInit.pendingTimestamp` to 0 | [U] | P1 |
| LOGR-CIGR-5 | Emits `GuardianRecoveryInitializationCancelled()` | [EV] | P1 |
| LOGR-CIGR-6 | Recovery config (`recoveryAddress`, `timelockDurationSeconds`) remain zero after cancel | [U] | P1 |
| LOGR-CIGR-7 | Can initiate again after cancel | [U] | P1 |

---

### 2.9 `enforceOnlyGuardianRecoveryAddress`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOGR-EOGRA-1 | `msg.sender == recoveryAddress` — no revert | [U] | P0 |
| LOGR-EOGRA-2 | `msg.sender != recoveryAddress` — reverts `UnauthorizedGuardianRecoveryAddress(msg.sender, expected)` | [N] | P0 |
| LOGR-EOGRA-3 | Error includes both caller address and expected recovery address | [U] | P1 |
| LOGR-EOGRA-4 | Recovery not configured (`recoveryAddress == address(0)`) — any address reverts | [E] | P0 |

---

### 2.10 `enforceOnlyRecoveryPendingGuardian`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOGR-EORPG-1 | `msg.sender == pendingGuardian` — no revert | [U] | P0 |
| LOGR-EORPG-2 | `msg.sender != pendingGuardian` — reverts `UnauthorizedRecoveryGuardianAcceptance(msg.sender, pendingGuardian)` | [N] | P0 |
| LOGR-EORPG-3 | No pending update (`pendingGuardian == address(0)`) — any address reverts | [E] | P0 |
| LOGR-EORPG-4 | Error includes both caller address and expected pending guardian address | [U] | P1 |

---

### 2.11 `_clearPendingGuardianRecoveryInitTimelock` (private → internal)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOGR-CPGRIT-1 | After clear: `pendingInit.pendingRecoveryAddress == address(0)` | [U] | P1 |
| LOGR-CPGRIT-2 | After clear: `pendingInit.pendingTimelockDurationSeconds == 0` | [U] | P1 |
| LOGR-CPGRIT-3 | After clear: `pendingInit.pendingTimestamp == 0` | [U] | P1 |
| LOGR-CPGRIT-4 | Clearing already-zeroed state — no-op, no revert | [E] | P2 |
| LOGR-CPGRIT-5 | Clearing pending init does NOT modify `recoveryAddress`, `timelockDurationSeconds`, or recovery update pending fields (`pendingGuardian`, `pendingGuardianTimestamp`, `isUpdateReadyForAcceptance`) | [S] | P1 |

---

### 2.12 `_validateGuardianRecoveryNotConfiguredOrRevert` (private → internal)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOGR-VGRNCOR-1 | Both `recoveryAddress` and `timelockDurationSeconds` zero — succeeds (not configured) | [U] | P1 |
| LOGR-VGRNCOR-2 | `recoveryAddress` non-zero, `timelockDurationSeconds` zero — reverts `GuardianRecoveryAlreadyConfigured` | [N] | P1 |
| LOGR-VGRNCOR-3 | `recoveryAddress` zero, `timelockDurationSeconds` non-zero — reverts `GuardianRecoveryAlreadyConfigured` | [N] | P1 |
| LOGR-VGRNCOR-4 | Both non-zero — reverts `GuardianRecoveryAlreadyConfigured` | [N] | P1 |

---

### 2.13 `_validateGuardianRecoveryParamsOrRevert` (private → internal)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOGR-VGRPOR-1 | Valid address + valid timelock duration — succeeds | [U] | P1 |
| LOGR-VGRPOR-2 | `recoveryAddress == address(0)` — reverts `InvalidGuardianRecoveryAddress` | [N] | P1 |
| LOGR-VGRPOR-3 | Timelock below minimum (< 2 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| LOGR-VGRPOR-4 | Timelock above maximum (> 30 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| LOGR-VGRPOR-5 | Timelock at exact minimum boundary (2 days) — succeeds | [E] | P1 |
| LOGR-VGRPOR-6 | Timelock at exact maximum boundary (30 days) — succeeds | [E] | P1 |
| LOGR-VGRPOR-7 | Timelock at 0 seconds — reverts `InvalidTimelockDuration` | [E] | P1 |
| LOGR-VGRPOR-8 | `recoveryAddress == address(0)` with out-of-range timelock — reverts `InvalidGuardianRecoveryAddress` (address check executes before timelock validation) | [E] | P1 |

---

## 3. Full Lifecycle Integration Tests

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGR-INT-1 | Complete recovery flow: initiate → time passes → finalize → accept — guardian updated in normal storage | [I] | P0 |
| OGR-INT-2 | Cancel during pending: initiate → cancel → initiate again with different address — works | [I] | P1 |
| OGR-INT-3 | Cancel after finalize: initiate → finalize → cancel → all pending state cleared | [I] | P1 |
| OGR-INT-4 | Deferred init lifecycle: initiateInit → time passes → finalizeInit → recovery config set | [I] | P1 |
| OGR-INT-5 | Deferred init cancel + retry: initiateInit → cancelInit → initiateInit again — works | [I] | P1 |
| OGR-INT-6 | Full lifecycle after deferred init: initiateInit → finalizeInit → initiateRecovery → finalize → accept | [I] | P1 |
| OGR-INT-7 | Recovery and normal guardian update in parallel — both can run simultaneously, both complete independently | [I] | P0 |
| OGR-INT-8 | After recovery completes, normal guardian flow can be used by the new guardian | [I] | P1 |
| OGR-INT-9 | After normal guardian update completes, recovery flow can still be used by recovery address | [I] | P1 |
| OGR-INT-10 | Multiple sequential recovery updates: complete first → start and complete second | [I] | P1 |
| OGR-INT-11 | **Desired Behavior:** deferred-init finalize signatures become invalid after `cancelInitializeGuardianRecovery` + re-init with new params (`operationData` binding prevents stale-signature replay) | [I][S] | P0 |
| OGR-INT-12 | **Desired Behavior:** deferred-init cancel signatures become invalid after pending params change (`operationData` binding to current pending tuple) | [I][S] | P0 |

---

## 4. Fuzz Tests

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OGR-FZ-1 | Fuzz: Random non-zero recovery addresses with valid timelock durations always configure successfully | [F] | P1 |
| OGR-FZ-2 | Fuzz: Random timelock durations in [2 days, 30 days] always accepted by `_validateGuardianRecoveryParamsOrRevert` | [F] | P1 |
| OGR-FZ-3 | Fuzz: Random timelock durations outside [2 days, 30 days] always revert `InvalidTimelockDuration` | [F] | P1 |
| OGR-FZ-4 | Fuzz: Random timestamps before timelock expiry — finalize always reverts `TimelockNotExpired` | [F] | P1 |
| OGR-FZ-5 | Fuzz: Random timestamps at/after timelock expiry — finalize always succeeds | [F] | P1 |
| OGR-FZ-6 | Fuzz: Random valid addresses as new guardian — recovery update flow completes | [F] | P1 |
| OGR-FZ-7 | Fuzz: Random non-recovery addresses always revert on `enforceOnlyGuardianRecoveryAddress` | [F] | P0 |
| OGR-FZ-8 | Fuzz: Random non-pending-guardian addresses always revert on `enforceOnlyRecoveryPendingGuardian` | [F] | P0 |
| OGR-FZ-9 | Fuzz: Random guardian recovery timelock durations — `canFinalizeAtTimestamp` always equals `block.timestamp + duration` | [F] | P1 |
| OGR-FZ-10 | Fuzz: `address(0)` always reverts `InvalidNewGuardianAddress` on `initiateRecoveryGuardianUpdate` | [F] | P1 |

---

## 5. Invariant Tests

| ID | Invariant | Priority |
|---|-----------|----------|
| OGR-INV-1 | **Recovery isolation**: Recovery pending state (`pendingGuardian`, `pendingGuardianTimestamp`, `isUpdateReadyForAcceptance`) never modifies normal guardian pending state and vice versa | P0 |
| OGR-INV-2 | **Guardian always valid**: After any recovery accept operation completes, `guardian() != address(0)` | P0 |
| OGR-INV-3 | **Timelock enforcement**: Recovery guardian cannot change without timelock expiry + finalize + accept | P0 |
| OGR-INV-4 | **State consistency**: If `pendingGuardian == address(0)` in recovery storage, then `pendingGuardianTimestamp == 0` AND `isUpdateReadyForAcceptance == false` | P0 |
| OGR-INV-5 | **Accept clears all recovery pending**: After `acceptGuardianRecovery`, all three recovery pending fields are reset (`address(0)`, `0`, `false`) | P0 |
| OGR-INV-6 | **Config immutability**: `recoveryAddress` and `timelockDurationSeconds` never change after initialization (only set once) | P0 |
| OGR-INV-7 | **Deferred init state consistency**: If `pendingInit.pendingTimestamp == 0`, then `pendingInit.pendingRecoveryAddress == address(0)` AND `pendingInit.pendingTimelockDurationSeconds == 0` | P0 |
| OGR-INV-8 | **Tx recovery isolation**: Guardian recovery operations never modify tx recovery state | P0 |
| OGR-INV-9 | **Accept writes to normal storage**: `acceptGuardianRecovery` always writes to `LibOrganizationGuardianStorage.layout().guardian`, never to recovery storage's config fields | P0 |
| OGR-INV-10 | **Ready-state consistency (reverse)**: If `isUpdateReadyForAcceptance == true`, then `pendingGuardian != address(0)` AND `pendingGuardianTimestamp != 0` | P0 |
| OGR-INV-11 | **Deferred-init consistency (reverse)**: If `pendingInit.pendingTimestamp != 0`, then `pendingInit.pendingRecoveryAddress != address(0)` AND `pendingInit.pendingTimelockDurationSeconds` is within `[2 days, 30 days]` | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `initiateRecoveryGuardianUpdate` (Base) | 2 | P0-P1 |
| `finalizeRecoveryGuardianUpdate` (Base) | 2 | P0-P1 |
| `cancelRecoveryGuardianUpdate` (Base) | 2 | P0-P1 |
| `acceptGuardianRecovery` (Base) | 2 | P0-P1 |
| `initiateInitializeGuardianRecovery` (Base) | 11 | P0-P1 |
| `finalizeInitializeGuardianRecovery` (Base) | 12 | P0-P1 |
| `cancelInitializeGuardianRecovery` (Base) | 12 | P0-P1 |
| `getGuardianRecoveryState` (Base) | 6 | P3 |
| `initializeGuardianRecovery` (Lib) | 8 | P0-P1 |
| `initiateRecoveryGuardianUpdate` (Lib) | 9 | P1-P2 |
| `finalizeRecoveryGuardianUpdate` (Lib) | 8 | P1-P2 |
| `cancelRecoveryGuardianUpdate` (Lib) | 8 | P1 |
| `acceptGuardianRecovery` (Lib) | 11 | P0-P2 |
| `initiateInitializeGuardianRecovery` (Lib) | 10 | P0-P1 |
| `finalizeInitializeGuardianRecovery` (Lib) | 9 | P0-P1 |
| `cancelInitializeGuardianRecovery` (Lib) | 7 | P1 |
| `enforceOnlyGuardianRecoveryAddress` | 4 | P0-P1 |
| `enforceOnlyRecoveryPendingGuardian` | 4 | P0-P1 |
| `_clearPendingGuardianRecoveryInitTimelock` | 5 | P1-P2 |
| `_validateGuardianRecoveryNotConfiguredOrRevert` | 4 | P1 |
| `_validateGuardianRecoveryParamsOrRevert` | 8 | P1 |
| Full lifecycle integration | 12 | P0-P1 |
| Fuzz tests | 10 | P0-P1 |
| Invariant tests | 11 | P0 |
| **Total** | **177** | |
