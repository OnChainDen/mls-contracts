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

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOAT-IAOT-1 | Valid duration at minimum boundary (`2 days`) is accepted and stored | `[U]` | P1 |
| LOAT-IAOT-2 | Valid duration at maximum boundary (`30 days`) is accepted and stored | `[U]` | P1 |
| LOAT-IAOT-3 | Duration below minimum reverts `InvalidTimelockDuration` | `[N]` | P0 |
| LOAT-IAOT-4 | Duration above maximum reverts `InvalidTimelockDuration` | `[N]` | P0 |
| LOAT-IAOT-5 | Stored value matches exactly (no rounding/truncation) | `[U]` | P1 |
| LOAT-IAOT-6 | Harness-only: repeated calls overwrite stored duration (document raw library behavior; integration layer must prevent this) | `[E]` | P2 |

---

### 1.2 `getAdminOperationTimelockDurationSeconds`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOAT-GAOTDS-1 | Returns `0` in uninitialized harness state | `[E]` | P2 |
| LOAT-GAOTDS-2 | Returns configured duration after initialization | `[U]` | P1 |
| LOAT-GAOTDS-3 | Returns most recent value in harness-only repeated-init scenario | `[E]` | P2 |

---

### 1.3 `validateTimelockExpiredOrRevert`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOAT-VTEOR-1 | `block.timestamp < canFinalizeAtTimestamp` reverts `TimelockNotExpired` | `[N]` | P0 |
| LOAT-VTEOR-2 | Revert payload includes correct `canFinalizeAtTimestamp` and `currentTime` values | `[U]` | P1 |
| LOAT-VTEOR-3 | `block.timestamp == canFinalizeAtTimestamp` succeeds | `[E]` | P1 |
| LOAT-VTEOR-4 | `block.timestamp > canFinalizeAtTimestamp` succeeds | `[U]` | P1 |
| LOAT-VTEOR-5 | `canFinalizeAtTimestamp = 0` succeeds (helper semantics; callers must gate pending-state existence) | `[E]` | P2 |

---

### 1.4 `computeCanFinalizeAtTimestamp`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOAT-CCFAT-1 | Returns `block.timestamp + adminOperationTimelockDurationSeconds` | `[U]` | P1 |
| LOAT-CCFAT-2 | With duration at min boundary, computed timestamp is exactly `now + 2 days` | `[E]` | P1 |
| LOAT-CCFAT-3 | With duration at max boundary, computed timestamp is exactly `now + 30 days` | `[E]` | P1 |
| LOAT-CCFAT-4 | Uninitialized harness state (`duration=0`) returns `block.timestamp` (documented helper behavior) | `[E]` | P2 |

---

## File 2: `OrganizationAdminOperationTimelockBase.sol`

### 2.1 `adminOperationTimelockDurationSeconds`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| OAOTB-AOTDS-1 | Returns the value stored by `LibOrganizationAdminOperationTimelock` | `[U]` | P1 |
| OAOTB-AOTDS-2 | Callable by any address (no access control) | `[U]` | P3 |
| OAOTB-AOTDS-3 | Returns expected value through `OrganizationImplementation` after successful initialization | `[I]` | P1 |

---

## File 3: `LibOrganizationInitialization.sol` (timelock-specific integration)

### 3.1 `initialize`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOI-INIT-1 | Valid `adminOperationTimelockDurationSeconds` is persisted and readable from base getter | `[I]` | P0 |
| LOI-INIT-2 | `OrganizationInitialized` event includes the exact configured admin-operation timelock value | `[EV]` | P1 |
| LOI-INIT-3 | Timelock below min reverts initialization with `InvalidTimelockDuration` | `[N]` | P0 |
| LOI-INIT-4 | Timelock above max reverts initialization with `InvalidTimelockDuration` | `[N]` | P0 |
| LOI-INIT-5 | Invalid timelock causes full initialization revert (no partial persisted org state) | `[S]` | P0 |
| LOI-INIT-6 | If a later initialization step reverts (for example, invalid guardian), admin-operation timelock state write is rolled back atomically | `[S]` | P0 |
| LOI-INIT-7 | Second initialize attempt reverts (`AlreadyInitialized`) and does not change timelock value | `[N]` | P0 |

---

## File 4: `LibOrganizationGuardian.sol` (admin-operation timelock call sites)

### 4.1 `initiateGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOG-IGU-1 | Sets `pendingGuardianUpdateTimestamp = block.timestamp + adminOperationTimelockDurationSeconds` | `[I]` | P0 |
| LOG-IGU-2 | `GuardianUpdateInitiated(..., canFinalizeAtTimestamp)` emits the same timestamp persisted in storage | `[EV]` | P1 |
| LOG-IGU-3 | Same-block finalize attempt reverts (`TimelockNotExpired`) | `[S]` | P0 |

---

### 4.2 `finalizeGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOG-FGU-1 | Before pending timestamp reverts `TimelockNotExpired` | `[N]` | P0 |
| LOG-FGU-2 | At exact pending timestamp succeeds | `[E]` | P1 |
| LOG-FGU-3 | After pending timestamp succeeds | `[U]` | P1 |
| LOG-FGU-4 | Success sets `isGuardianUpdateReadyForAcceptance = true` while preserving pending guardian + pending timestamp until accept/cancel | `[U]` | P1 |
| LOG-FGU-5 | After cancellation, finalize reverts `NoPendingGuardianUpdate` even if previous timestamp has passed | `[S]` | P1 |
| LOG-FGU-6 | After accepting new guardian, finalize reverts `NoPendingGuardianUpdate` even if previous timestamp has passed | `[S]` | P1 |

---

### 4.3 `cancelGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOG-CGU-1 | Before timelock expiry, cancel clears pending guardian timestamp to `0` and emits `GuardianUpdateCancelled` with the cancelled pending guardian | `[U][EV]` | P1 |
| LOG-CGU-2 | After timelock expiry (but before acceptance), cancel still succeeds and clears pending timelock state | `[E]` | P1 |
| LOG-CGU-3 | Cancelling a finalized-but-not-yet-accepted update resets `isGuardianUpdateReadyForAcceptance` to `false` | `[U]` | P1 |
| LOG-CGU-4 | After cancellation, re-initiation computes a fresh `canFinalizeAtTimestamp = newStart + adminOperationTimelockDurationSeconds` (no stale timestamp reuse) | `[S]` | P1 |

---

## File 5: `LibOrganizationGuardianRecovery.sol` (timelock-relevant paths)

### 5.1 `initiateInitializeGuardianRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOGR-IIGR-1 | Deferred-init pending timestamp uses **admin-operation** timelock (`now + adminOperationTimelockDurationSeconds`) | `[I]` | P0 |
| LOGR-IIGR-2 | Deferred-init pending timestamp does **not** use guardian-recovery timelock duration input | `[S]` | P0 |
| LOGR-IIGR-3 | Stores `pendingRecoveryAddress` and `pendingTimelockDurationSeconds` exactly as requested for finalize/cancel operation-data binding | `[U]` | P1 |
| LOGR-IIGR-4 | `GuardianRecoveryInitializationInitiated(..., canFinalizeAtTimestamp)` emits the same pending timestamp stored in state | `[EV]` | P1 |
| LOGR-IIGR-5 | Same-block finalize attempt reverts (TimelockNotExpired) | [S] | P0 |

---

### 5.2 `finalizeInitializeGuardianRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOGR-FIGR-1 | Before pending timestamp reverts `TimelockNotExpired` | `[N]` | P0 |
| LOGR-FIGR-2 | At exact pending timestamp succeeds | `[E]` | P1 |
| LOGR-FIGR-3 | After pending timestamp succeeds | `[U]` | P1 |
| LOGR-FIGR-4 | Success clears pending-init timelock state and writes final recovery config | `[U]` | P1 |
| LOGR-FIGR-5 | Emits `GuardianRecoveryInitializationFinalized(recoveryAddress,timelockDurationSeconds)` matching pending-init values used during finalization | `[EV]` | P1 |
| LOGR-FIGR-6 | After cancellation, finalize reverts `NoGuardianRecoveryInitializationPending` even if cancelled timestamp would have expired | `[S]` | P1 |
| LOGR-FIGR-7 | Harness-only state-mutation scenario: if downstream config write would revert, pending-init state remains unchanged (atomicity) | `[S]` | P1 |

---

### 5.3 `cancelInitializeGuardianRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOGR-CIGR-1 | Clears `pendingRecoveryAddress`, `pendingTimelockDurationSeconds`, and `pendingTimestamp` and emits `GuardianRecoveryInitializationCancelled` | `[U][EV]` | P1 |
| LOGR-CIGR-2 | Cancel is allowed both before and after timelock expiry, as long as finalization has not occurred | `[E]` | P1 |
| LOGR-CIGR-3 | No pending init reverts `NoGuardianRecoveryInitializationPending` | `[N]` | P0 |
| LOGR-CIGR-4 | After cancellation, a fresh initiate is allowed and uses a new admin-operation timelock timestamp | `[S]` | P1 |

---

### 5.4 `finalizeRecoveryGuardianUpdate`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOGR-FRGU-1 | Uses shared `validateTimelockExpiredOrRevert` semantics: before timestamp reverts | `[I]` | P1 |
| LOGR-FRGU-2 | Uses shared `validateTimelockExpiredOrRevert` semantics: at exact timestamp succeeds | `[E]` | P1 |
| LOGR-FRGU-3 | Uses shared `validateTimelockExpiredOrRevert` semantics: after timestamp succeeds | `[U]` | P1 |

---

### 5.5 `_clearPendingGuardianRecoveryInitTimelock` (private; harness-only)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOGR-CPGRIT-1 | Clears `pendingRecoveryAddress`, `pendingTimelockDurationSeconds`, and `pendingTimestamp` to zero | `[U]` | P1 |
| LOGR-CPGRIT-2 | Idempotent when fields are already zero | `[E]` | P2 |

---

### 5.6 `_validateGuardianRecoveryNotConfiguredOrRevert` (private; harness-only)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOGR-VGRNCOR-1 | Unconfigured state (`recoveryAddress=0` and `timelockDurationSeconds=0`) succeeds | `[U]` | P1 |
| LOGR-VGRNCOR-2 | `recoveryAddress!=0` and `timelockDurationSeconds=0` reverts `GuardianRecoveryAlreadyConfigured` | `[N]` | P0 |
| LOGR-VGRNCOR-3 | `recoveryAddress=0` and `timelockDurationSeconds!=0` reverts `GuardianRecoveryAlreadyConfigured` | `[N]` | P0 |
| LOGR-VGRNCOR-4 | `recoveryAddress!=0` and `timelockDurationSeconds!=0` reverts `GuardianRecoveryAlreadyConfigured` | `[N]` | P0 |

---

### 5.7 `_validateGuardianRecoveryParamsOrRevert` (private; harness-only)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOGR-VGRPOR-1 | `recoveryAddress=0` reverts `InvalidGuardianRecoveryAddress` | `[N]` | P0 |
| LOGR-VGRPOR-2 | Timelock below minimum reverts `InvalidTimelockDuration` | `[N]` | P0 |
| LOGR-VGRPOR-3 | Timelock above maximum reverts `InvalidTimelockDuration` | `[N]` | P0 |
| LOGR-VGRPOR-4 | Non-zero address + timelock at min boundary (`2 days`) succeeds | `[E]` | P1 |
| LOGR-VGRPOR-5 | Non-zero address + timelock within boundary (`2 days` < x < `30 days`) succeeds | `[S]` | P1 |
| LOGR-VGRPOR-6 | Non-zero address + timelock at max boundary (`30 days`) succeeds | `[E]` | P1 |

---

## File 6: `LibOrganizationTxRecovery.sol` (timelock-relevant paths)

### 6.1 `initiateInitializeTxRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-IITR-1 | Deferred-init pending timestamp uses **admin-operation** timelock (`now + adminOperationTimelockDurationSeconds`) | `[I]` | P0 |
| LOTR-IITR-2 | Deferred-init pending timestamp does **not** use tx-recovery timelock duration input | `[S]` | P0 |
| LOTR-IITR-3 | Stores `pendingRecoveryAddress` and `pendingTimelockDurationSeconds` exactly as requested for finalize/cancel operation-data binding | `[U]` | P1 |
| LOTR-IITR-4 | `TxRecoveryInitializationInitiated(..., canFinalizeAtTimestamp)` emits the same pending timestamp stored in state | `[EV]` | P1 |
| LOTR-IITR-5 | Same-block finalize attempt reverts (TimelockNotExpired) | [S] | P0 |


---

### 6.2 `finalizeInitializeTxRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-FITR-1 | Before pending timestamp reverts `TimelockNotExpired` | `[N]` | P0 |
| LOTR-FITR-2 | At exact pending timestamp succeeds | `[E]` | P1 |
| LOTR-FITR-3 | After pending timestamp succeeds | `[U]` | P1 |
| LOTR-FITR-4 | Success clears pending-init timelock state and writes final tx-recovery config | `[U]` | P1 |
| LOTR-FITR-5 | Emits `TxRecoveryInitializationFinalized(recoveryAddress,timelockDurationSeconds)` matching pending-init values used during finalization | `[EV]` | P1 |
| LOTR-FITR-6 | After cancellation, finalize reverts `NoTxRecoveryInitializationPending` even if cancelled timestamp would have expired | `[S]` | P1 |
| LOTR-FITR-7 | Harness-only state-mutation scenario: if downstream config write would revert, pending-init state remains unchanged (atomicity) | `[S]` | P1 |

---

### 6.3 `cancelInitializeTxRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-CITR-1 | Clears `pendingRecoveryAddress`, `pendingTimelockDurationSeconds`, and `pendingTimestamp` and emits `TxRecoveryInitializationCancelled` | `[U][EV]` | P1 |
| LOTR-CITR-2 | Cancel is allowed both before and after timelock expiry, as long as finalization has not occurred | `[E]` | P1 |
| LOTR-CITR-3 | No pending init reverts `NoTxRecoveryInitializationPending` | `[N]` | P0 |
| LOTR-CITR-4 | After cancellation, a fresh initiate is allowed and uses a new admin-operation timelock timestamp | `[S]` | P1 |

---


### 6.5 `_clearPendingTxRecoveryInitTimelock` (private; harness-only)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-CPTRIT-1 | Clears `pendingRecoveryAddress`, `pendingTimelockDurationSeconds`, and `pendingTimestamp` to zero | `[U]` | P1 |
| LOTR-CPTRIT-2 | Idempotent when fields are already zero | `[E]` | P2 |

---

### 6.6 `_validateTxRecoveryNotConfiguredOrRevert` (private; harness-only)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-VTRNCOR-1 | Unconfigured state (`recoveryAddress=0` and `timelockDurationSeconds=0`) succeeds | `[U]` | P1 |
| LOTR-VTRNCOR-2 | `recoveryAddress!=0` and `timelockDurationSeconds=0` reverts `TransactionRecoveryAlreadyConfigured` | `[N]` | P0 |
| LOTR-VTRNCOR-3 | `recoveryAddress=0` and `timelockDurationSeconds!=0` reverts `TransactionRecoveryAlreadyConfigured` | `[N]` | P0 |
| LOTR-VTRNCOR-4 | `recoveryAddress!=0` and `timelockDurationSeconds!=0` reverts `TransactionRecoveryAlreadyConfigured` | `[N]` | P0 |

---

### 6.7 `_validateTxRecoveryParamsOrRevert` (private; harness-only)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-VTRPOR-1 | `recoveryAddress=0` reverts `InvalidTxRecoveryAddress` | `[N]` | P0 |
| LOTR-VTRPOR-2 | Timelock below minimum reverts `InvalidTimelockDuration` | `[N]` | P0 |
| LOTR-VTRPOR-3 | Timelock above maximum reverts `InvalidTimelockDuration` | `[N]` | P0 |
| LOTR-VTRPOR-4 | Non-zero address + timelock at min boundary (`2 days`) succeeds | `[E]` | P1 |
| LOTR-VTRPOR-5 | Non-zero address + timelock within boundary (`2 days` < x < `30 days`) succeeds | `[S]` | P1 |
| LOTR-VTRPOR-6 | Non-zero address + timelock at max boundary (`30 days`) succeeds | `[E]` | P1 |

---

## Cross-File Fuzz Tests

| ID | Test Case | Type | Priority |
|---|---|---|---|
| AOT-FUZ-1 | Fuzz valid admin-operation timelock durations in `[2 days, 30 days]`: all admin-timelock initiation call sites compute `pendingTimestamp = start + duration` | `[F]` | P1 |
| AOT-FUZ-2 | Fuzz timestamps around expiry (`t-1`, `t`, `t+1`) for all finalize call sites using helper; behavior is revert/succeed/succeed respectively | `[F]` | P1 |
| AOT-FUZ-3 | Fuzz out-of-range admin-operation durations: initialization always reverts `InvalidTimelockDuration` | `[F]` | P0 |
| AOT-FUZ-4 | Fuzz deferred-init cancel/re-init cycles (guardian recovery + tx recovery): cancel always zeroes pending init fields and re-init always computes a fresh `pendingTimestamp` from the new start time | `[F]` | P1 |
| AOT-FUZ-5 | Fuzz partially configured recovery states for currently-private `_validate*NotConfiguredOrRevert` helpers: any non-zero config field always reverts as already configured | `[F]` | P1 |

---

## Cross-File Invariants

| ID | Invariant | Type | Priority |
|---|---|---|---|
| AOT-INV-1 | In any initialized organization, `adminOperationTimelockDurationSeconds` is always within `[2 days, 30 days]` | `[INV]` | P0 |
| AOT-INV-2 | No sequence of guardian/recovery operations can mutate `adminOperationTimelockDurationSeconds` post-initialization | `[INV]` | P0 |
| AOT-INV-3 | Admin-operation timelocked flows cannot be finalized in the same block they are initiated | `[INV]` | P0 |
| AOT-INV-4 | For deferred recovery-init states (guardian + tx): `pendingTimestamp == 0` implies pending init address and pending init timelock are also zero | `[INV]` | P0 |
| AOT-INV-5 | For deferred recovery-init states (guardian + tx): `pendingTimestamp != 0` implies pending init address is non-zero and pending init timelock is within `[2 days, 30 days]` | `[INV]` | P0 |
