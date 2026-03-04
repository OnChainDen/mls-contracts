# 22 - Admin Operation Timelock Test Plan

**Primary Files Under Test:**
- `src/organization/libraries/LibOrganizationAdminOperationTimelock.sol`
- `src/organization/base/OrganizationAdminOperationTimelockBase.sol`

**Admin Operation Timelock Consumer Files (integration behavior only):**

These files call `LibOrganizationAdminOperationTimelock` helpers (`computeCanFinalizeAtTimestamp`, `validateTimelockExpiredOrRevert`) to gate sensitive admin operations. This plan only covers the code paths where the admin operation timelock is consumed — it does **not** cover the full behavior of these files (e.g., access control, acceptance flows, domain-specific recovery timelocks). Full coverage for those concerns belongs in their respective dedicated test plans.

- `src/organization/libraries/LibOrganizationInitialization.sol` — calls `initializeAdminOperationTimelock` during org setup
- `src/organization/libraries/LibOrganizationGuardian.sol` — guardian update initiate/finalize/cancel use the admin operation timelock
- `src/organization/libraries/LibOrganizationGuardianRecovery.sol` — deferred guardian-recovery initialization (`initiateInitializeGuardianRecovery` / `finalizeInitializeGuardianRecovery` / `cancelInitializeGuardianRecovery`) is gated by the admin operation timelock; `finalizeRecoveryGuardianUpdate` also calls the shared `validateTimelockExpiredOrRevert` helper. Note: the recovery guardian update flow itself (`initiateRecoveryGuardianUpdate`) uses its own guardian-recovery timelock, not the admin operation timelock — those paths are out of scope here.
- `src/organization/libraries/LibOrganizationTxRecovery.sol` — deferred tx-recovery initialization (`initiateInitializeTxRecovery` / `finalizeInitializeTxRecovery` / `cancelInitializeTxRecovery`) is gated by the admin operation timelock; `finalizeEnableTxRecovery` also calls the shared `validateTimelockExpiredOrRevert` helper. Note: the enable tx-recovery flow itself (`initiateEnableTxRecovery`) uses its own tx-recovery timelock, not the admin operation timelock — those paths are out of scope here.

**Out of Scope for This Plan:**
- `src/interfaces/organization/IOrganizationAdminOperationTimelock.sol` (interface coverage tracked elsewhere)
- `src/organization/libraries/storage/LibOrganizationAdminOperationTimelockStorage.sol` (storage coverage tracked elsewhere)

> Note on internal/private function testing:
> This plan explicitly covers helper logic that is currently `private` where timelock safety depends on it.
> For implementation, all currently-private timelock helpers should be exposed as `internal` in harness-only test builds so they can be tested directly.

---

## Legend

| Code | Meaning |
|------|---------|
| `[U]` | Unit |
| `[N]` | Negative / revert path |
| `[E]` | Edge case |
| `[S]` | Security-focused |
| `[I]` | Integration |
| `[EV]` | Event behavior |
| `[F]` | Fuzz / property |
| `[INV]` | Invariant |

---

## File 1: `LibOrganizationAdminOperationTimelock.sol`

### 1.1 `initializeAdminOperationTimelock`

| Test Case | Type | Priority |
|---|---|---|
| Valid duration at minimum boundary (`2 days`) is accepted and stored | `[U]` | P1 |
| Valid duration at maximum boundary (`30 days`) is accepted and stored | `[U]` | P1 |
| Duration below minimum reverts `InvalidTimelockDuration` | `[N]` | P0 |
| Duration above maximum reverts `InvalidTimelockDuration` | `[N]` | P0 |
| Stored value matches exactly (no rounding/truncation) | `[U]` | P1 |
| Harness-only: repeated calls overwrite stored duration (document raw library behavior; integration layer must prevent this) | `[E]` | P2 |

---

### 1.2 `getAdminOperationTimelockDurationSeconds`

| Test Case | Type | Priority |
|---|---|---|
| Returns `0` in uninitialized harness state | `[E]` | P2 |
| Returns configured duration after initialization | `[U]` | P1 |
| Returns most recent value in harness-only repeated-init scenario | `[E]` | P2 |

---

### 1.3 `validateTimelockExpiredOrRevert`

| Test Case | Type | Priority |
|---|---|---|
| `block.timestamp < canFinalizeAtTimestamp` reverts `TimelockNotExpired` | `[N]` | P0 |
| Revert payload includes correct `canFinalizeAtTimestamp` and `currentTime` values | `[U]` | P1 |
| `block.timestamp == canFinalizeAtTimestamp` succeeds | `[E]` | P1 |
| `block.timestamp > canFinalizeAtTimestamp` succeeds | `[U]` | P1 |
| `canFinalizeAtTimestamp = 0` succeeds (helper semantics; callers must gate pending-state existence) | `[E]` | P2 |

---

### 1.4 `computeCanFinalizeAtTimestamp`

| Test Case | Type | Priority |
|---|---|---|
| Returns `block.timestamp + adminOperationTimelockDurationSeconds` | `[U]` | P1 |
| With duration at min boundary, computed timestamp is exactly `now + 2 days` | `[E]` | P1 |
| With duration at max boundary, computed timestamp is exactly `now + 30 days` | `[E]` | P1 |
| Uninitialized harness state (`duration=0`) returns `block.timestamp` (documented helper behavior) | `[E]` | P2 |

---

## File 2: `OrganizationAdminOperationTimelockBase.sol`

### 2.1 `adminOperationTimelockDurationSeconds`

| Test Case | Type | Priority |
|---|---|---|
| Returns the value stored by `LibOrganizationAdminOperationTimelock` | `[U]` | P1 |
| Callable by any address (no access control) | `[U]` | P3 |
| Returns expected value through `OrganizationImplementation` after successful initialization | `[I]` | P1 |

---

## File 3: `LibOrganizationInitialization.sol` (timelock-specific integration)

### 3.1 `initialize`

| Test Case | Type | Priority |
|---|---|---|
| Valid `adminOperationTimelockDurationSeconds` is persisted and readable from base getter | `[I]` | P0 |
| `OrganizationInitialized` event includes the exact configured admin-operation timelock value | `[EV]` | P1 |
| Timelock below min reverts initialization with `InvalidTimelockDuration` | `[N]` | P0 |
| Timelock above max reverts initialization with `InvalidTimelockDuration` | `[N]` | P0 |
| Invalid timelock causes full initialization revert (no partial persisted org state) | `[S]` | P0 |
| If a later initialization step reverts (for example, invalid guardian), admin-operation timelock state write is rolled back atomically | `[S]` | P0 |
| Second initialize attempt reverts (`AlreadyInitialized`) and does not change timelock value | `[N]` | P0 |

---

## File 4: `LibOrganizationGuardian.sol` (admin-operation timelock call sites)

### 4.1 `initiateGuardianUpdate`

| Test Case | Type | Priority |
|---|---|---|
| Sets `pendingGuardianUpdateTimestamp = block.timestamp + adminOperationTimelockDurationSeconds` | `[I]` | P0 |
| `GuardianUpdateInitiated(..., canFinalizeAtTimestamp)` emits the same timestamp persisted in storage | `[EV]` | P1 |
| Same-block finalize attempt reverts (`TimelockNotExpired`) | `[S]` | P0 |

---

### 4.2 `finalizeGuardianUpdate`

| Test Case | Type | Priority |
|---|---|---|
| Before pending timestamp reverts `TimelockNotExpired` | `[N]` | P0 |
| At exact pending timestamp succeeds | `[E]` | P1 |
| After pending timestamp succeeds | `[U]` | P1 |
| Success sets `isGuardianUpdateReadyForAcceptance = true` while preserving pending guardian + pending timestamp until accept/cancel | `[U]` | P1 |
| After cancellation, finalize reverts `NoPendingGuardianUpdate` even if previous timestamp has passed | `[S]` | P1 |

---

### 4.3 `cancelGuardianUpdate`

| Test Case | Type | Priority |
|---|---|---|
| Before timelock expiry, cancel clears pending guardian timestamp to `0` and emits `GuardianUpdateCancelled` with the cancelled pending guardian | `[U][EV]` | P1 |
| After timelock expiry (but before acceptance), cancel still succeeds and clears pending timelock state | `[E]` | P1 |
| Cancelling a finalized-but-not-yet-accepted update resets `isGuardianUpdateReadyForAcceptance` to `false` | `[U]` | P1 |
| After cancellation, re-initiation computes a fresh `canFinalizeAtTimestamp = newStart + adminOperationTimelockDurationSeconds` (no stale timestamp reuse) | `[S]` | P1 |

---

## File 5: `LibOrganizationGuardianRecovery.sol` (timelock-relevant paths)

### 5.1 `initiateInitializeGuardianRecovery`

| Test Case | Type | Priority |
|---|---|---|
| Deferred-init pending timestamp uses **admin-operation** timelock (`now + adminOperationTimelockDurationSeconds`) | `[I]` | P0 |
| Deferred-init pending timestamp does **not** use guardian-recovery timelock duration input | `[S]` | P0 |
| Stores `pendingRecoveryAddress` and `pendingTimelockDurationSeconds` exactly as requested for finalize/cancel operation-data binding | `[U]` | P1 |
| `GuardianRecoveryInitializationInitiated(..., canFinalizeAtTimestamp)` emits the same pending timestamp stored in state | `[EV]` | P1 |

---

### 5.2 `finalizeInitializeGuardianRecovery`

| Test Case | Type | Priority |
|---|---|---|
| Before pending timestamp reverts `TimelockNotExpired` | `[N]` | P0 |
| At exact pending timestamp succeeds | `[E]` | P1 |
| After pending timestamp succeeds | `[U]` | P1 |
| Success clears pending-init timelock state and writes final recovery config | `[U]` | P1 |
| Emits `GuardianRecoveryInitializationFinalized(recoveryAddress,timelockDurationSeconds)` matching pending-init values used during finalization | `[EV]` | P1 |
| After cancellation, finalize reverts `NoGuardianRecoveryInitializationPending` even if cancelled timestamp would have expired | `[S]` | P1 |
| Harness-only state-mutation scenario: if downstream config write would revert, pending-init state remains unchanged (atomicity) | `[S]` | P1 |

---

### 5.3 `cancelInitializeGuardianRecovery`

| Test Case | Type | Priority |
|---|---|---|
| Clears `pendingRecoveryAddress`, `pendingTimelockDurationSeconds`, and `pendingTimestamp` and emits `GuardianRecoveryInitializationCancelled` | `[U][EV]` | P1 |
| Cancel is allowed both before and after timelock expiry, as long as finalization has not occurred | `[E]` | P1 |
| No pending init reverts `NoGuardianRecoveryInitializationPending` | `[N]` | P0 |
| After cancellation, a fresh initiate is allowed and uses a new admin-operation timelock timestamp | `[S]` | P1 |

---

### 5.4 `finalizeRecoveryGuardianUpdate`

| Test Case | Type | Priority |
|---|---|---|
| Uses shared `validateTimelockExpiredOrRevert` semantics: before timestamp reverts | `[I]` | P1 |
| Uses shared `validateTimelockExpiredOrRevert` semantics: at exact timestamp succeeds | `[E]` | P1 |
| Uses shared `validateTimelockExpiredOrRevert` semantics: after timestamp succeeds | `[U]` | P1 |

---

### 5.5 `_clearPendingGuardianRecoveryInitTimelock` (private; harness-only)

| Test Case | Type | Priority |
|---|---|---|
| Clears `pendingRecoveryAddress`, `pendingTimelockDurationSeconds`, and `pendingTimestamp` to zero | `[U]` | P1 |
| Idempotent when fields are already zero | `[E]` | P2 |

---

### 5.6 `_validateGuardianRecoveryNotConfiguredOrRevert` (private; harness-only)

| Test Case | Type | Priority |
|---|---|---|
| Unconfigured state (`recoveryAddress=0` and `timelockDurationSeconds=0`) succeeds | `[U]` | P1 |
| `recoveryAddress!=0` and `timelockDurationSeconds=0` reverts `GuardianRecoveryAlreadyConfigured` | `[N]` | P0 |
| `recoveryAddress=0` and `timelockDurationSeconds!=0` reverts `GuardianRecoveryAlreadyConfigured` | `[N]` | P0 |

| `recoveryAddress!=0` and `timelockDurationSeconds!=0` reverts `GuardianRecoveryAlreadyConfigured` | `[N]` | P0 |

---

### 5.7 `_validateGuardianRecoveryParamsOrRevert` (private; harness-only)

| Test Case | Type | Priority |
|---|---|---|
| `recoveryAddress=0` reverts `InvalidGuardianRecoveryAddress` | `[N]` | P0 |
| Timelock below minimum reverts `InvalidTimelockDuration` | `[N]` | P0 |
| Timelock above maximum reverts `InvalidTimelockDuration` | `[N]` | P0 |
| Non-zero address + timelock at min boundary (`2 days`) succeeds | `[E]` | P1 |
| Non-zero address + timelock within boundary (`2 days` < x < `30 days`) succeeds | `[E]` | P1 |
| Non-zero address + timelock at max boundary (`30 days`) succeeds | `[E]` | P1 |

---

## File 6: `LibOrganizationTxRecovery.sol` (timelock-relevant paths)

### 6.1 `initiateInitializeTxRecovery`

| Test Case | Type | Priority |
|---|---|---|
| Deferred-init pending timestamp uses **admin-operation** timelock (`now + adminOperationTimelockDurationSeconds`) | `[I]` | P0 |
| Deferred-init pending timestamp does **not** use tx-recovery timelock duration input | `[S]` | P0 |
| Stores `pendingRecoveryAddress` and `pendingTimelockDurationSeconds` exactly as requested for finalize/cancel operation-data binding | `[U]` | P1 |
| `TxRecoveryInitializationInitiated(..., canFinalizeAtTimestamp)` emits the same pending timestamp stored in state | `[EV]` | P1 |
| Same-block finalize attempt reverts (TimelockNotExpired) | [S] | P0 |


---

### 6.2 `finalizeInitializeTxRecovery`

| Test Case | Type | Priority |
|---|---|---|
| Before pending timestamp reverts `TimelockNotExpired` | `[N]` | P0 |
| At exact pending timestamp succeeds | `[E]` | P1 |
| After pending timestamp succeeds | `[U]` | P1 |
| Success clears pending-init timelock state and writes final tx-recovery config | `[U]` | P1 |
| Emits `TxRecoveryInitializationFinalized(recoveryAddress,timelockDurationSeconds)` matching pending-init values used during finalization | `[EV]` | P1 |
| After cancellation, finalize reverts `NoTxRecoveryInitializationPending` even if cancelled timestamp would have expired | `[S]` | P1 |
| Harness-only state-mutation scenario: if downstream config write would revert, pending-init state remains unchanged (atomicity) | `[S]` | P1 |

---

### 6.3 `cancelInitializeTxRecovery`

| Test Case | Type | Priority |
|---|---|---|
| Clears `pendingRecoveryAddress`, `pendingTimelockDurationSeconds`, and `pendingTimestamp` and emits `TxRecoveryInitializationCancelled` | `[U][EV]` | P1 |
| Cancel is allowed both before and after timelock expiry, as long as finalization has not occurred | `[E]` | P1 |
| No pending init reverts `NoTxRecoveryInitializationPending` | `[N]` | P0 |
| After cancellation, a fresh initiate is allowed and uses a new admin-operation timelock timestamp | `[S]` | P1 |

---


### 6.5 `_clearPendingTxRecoveryInitTimelock` (private; harness-only)

| Test Case | Type | Priority |
|---|---|---|
| Clears `pendingRecoveryAddress`, `pendingTimelockDurationSeconds`, and `pendingTimestamp` to zero | `[U]` | P1 |
| Idempotent when fields are already zero | `[E]` | P2 |

---

### 6.6 `_validateTxRecoveryNotConfiguredOrRevert` (private; harness-only)

| Test Case | Type | Priority |
|---|---|---|
| Unconfigured state (`recoveryAddress=0` and `timelockDurationSeconds=0`) succeeds | `[U]` | P1 |
| `recoveryAddress!=0` and `timelockDurationSeconds=0` reverts `TransactionRecoveryAlreadyConfigured` | `[N]` | P0 |
| `recoveryAddress=0` and `timelockDurationSeconds!=0` reverts `TransactionRecoveryAlreadyConfigured` | `[N]` | P0 |
| `recoveryAddress!=0` and `timelockDurationSeconds!=0` reverts `TransactionRecoveryAlreadyConfigured` | `[N]` | P0 |

---

### 6.7 `_validateTxRecoveryParamsOrRevert` (private; harness-only)

| Test Case | Type | Priority |
|---|---|---|
| `recoveryAddress=0` reverts `InvalidTxRecoveryAddress` | `[N]` | P0 |
| Timelock below minimum reverts `InvalidTimelockDuration` | `[N]` | P0 |
| Timelock above maximum reverts `InvalidTimelockDuration` | `[N]` | P0 |
| Non-zero address + timelock at min boundary (`2 days`) succeeds | `[E]` | P1 |
| Non-zero address + timelock within boundary (`2 days` < x < `30 days`) succeeds | `[E]` | P1 |
| Non-zero address + timelock at max boundary (`30 days`) succeeds | `[E]` | P1 |

---

## Cross-File Fuzz Tests

| Test Case | Type | Priority |
|---|---|---|
| Fuzz valid admin-operation timelock durations in `[2 days, 30 days]`: all admin-timelock initiation call sites compute `pendingTimestamp = start + duration` | `[F]` | P1 |
| Fuzz timestamps around expiry (`t-1`, `t`, `t+1`) for all finalize call sites using helper; behavior is revert/succeed/succeed respectively | `[F]` | P1 |
| Fuzz out-of-range admin-operation durations: initialization always reverts `InvalidTimelockDuration` | `[F]` | P0 |
| Fuzz deferred-init cancel/re-init cycles (guardian recovery + tx recovery): cancel always zeroes pending init fields and re-init always computes a fresh `pendingTimestamp` from the new start time | `[F]` | P1 |
| Fuzz partially configured recovery states for currently-private `_validate*NotConfiguredOrRevert` helpers: any non-zero config field always reverts as already configured | `[F]` | P1 |

---

## Cross-File Invariants

| Invariant | Type | Priority |
|---|---|---|
| In any initialized organization, `adminOperationTimelockDurationSeconds` is always within `[2 days, 30 days]` | `[INV]` | P0 |
| No sequence of guardian/recovery operations can mutate `adminOperationTimelockDurationSeconds` post-initialization | `[INV]` | P0 |
| Admin-operation timelocked flows cannot be finalized in the same block they are initiated | `[INV]` | P0 |
| For deferred recovery-init states (guardian + tx): `pendingTimestamp == 0` implies pending init address and pending init timelock are also zero | `[INV]` | P0 |
| For deferred recovery-init states (guardian + tx): `pendingTimestamp != 0` implies pending init address is non-zero and pending init timelock is within `[2 days, 30 days]` | `[INV]` | P0 |
