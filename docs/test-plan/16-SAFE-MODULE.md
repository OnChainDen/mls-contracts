# 16 — Safe Module Integration Test Plan

**Files Under Test:**
- `src/safe-module/SafeExecutorModule.sol`
- `src/safe-module/BatchedTransaction.sol`
- `src/organization/libraries/LibOrganizationAccountSignature.sol` (Safe-module integration paths only)

**Out of Scope in This Plan:**
- Interface files (`ISafeExecutorModule.sol`, `IBatchedTransaction.sol`)
- Storage libraries

**Harness Prerequisite (private functions):**
- For direct unit tests of private helpers, temporarily change private functions in scope to `internal` and expose them through a harness contract.
- Private helpers in scope for this SAFE-module integration plan:
  - `LibOrganizationAccountSignature._isValidGuardianSignature`
  - `LibOrganizationAccountSignature._validatePolicyBasedSignature`
  - `LibOrganizationAccountSignature._isERC1271SignatureAllowedByPolicy`
  - `LibOrganizationAccountSignature._getInitiatorSignatureHash`
  - `LibOrganizationAccountSignature._getReviewSignatureHash`
- `LibOrganizationAccountSignature._validateRecoverySignature` is intentionally out of scope here (covered in account-signature and tx-recovery plans).

---

## 1. SafeExecutorModule.sol

### 1.1 `constructor`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| SEM-CON-1 | Sets `SAFE` immutable correctly | [U] | P1 |
| SEM-CON-2 | Sets `AUTHORIZED_EXECUTOR` immutable correctly | [U] | P1 |
| SEM-CON-3 | Sets `BATCHED_TRANSACTION` immutable correctly | [U] | P1 |
| SEM-CON-4 | `safe == address(0)` — reverts `SafeAddressCannotBeZero` | [N] | P0 |
| SEM-CON-5 | `authorizedExecutor == address(0)` — reverts `ExecutorAddressCannotBeZero` | [N] | P0 |
| SEM-CON-6 | `batchedTransaction == address(0)` — reverts `BatchedTransactionAddressCannotBeZero` | [N] | P0 |
| SEM-CON-7 | Multiple invalid params — deterministic revert precedence (`safe` check first) | [E] | P2 |
| SEM-CON-8 | **Desired behavior hardening:** reject non-contract `safe` address (misconfiguration protection) | [S] | P1 |
| SEM-CON-9 | **Desired behavior hardening:** reject non-contract `batchedTransaction` address | [S] | P1 |
| SEM-CON-10 | **Desired behavior hardening:** reject contract `authorizedExecutor` (docs require Authorized Executor EOA) | [S] | P1 |
| SEM-CON-11 | **Desired behavior hardening:** reject `safe == batchedTransaction` configuration | [S] | P1 |

---

### 1.2 `executeOnBehalf`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| SEM-EOB-1 | Non-authorized caller — reverts `UnauthorizedCaller(caller, AUTHORIZED_EXECUTOR)` | [N] | P0 |
| SEM-EOB-2 | Non-authorized caller + `to == SAFE` — still reverts `UnauthorizedCaller` (auth check first) | [S] | P0 |
| SEM-EOB-3 | Authorized caller + `to == SAFE` — reverts `CannotCallSafe` | [S] | P0 |
| SEM-EOB-4 | Successful call path invokes `Safe.execTransactionFromModule` exactly once | [U] | P1 |
| SEM-EOB-5 | Forwards exact `to` argument to Safe | [U] | P1 |
| SEM-EOB-6 | Forwards exact `data` bytes to Safe | [U] | P1 |
| SEM-EOB-7 | Always forwards `value = 0` | [S] | P0 |
| SEM-EOB-8 | `to != BATCHED_TRANSACTION` uses operation `CALL (0)` | [U] | P0 |
| SEM-EOB-9 | `to == BATCHED_TRANSACTION` uses operation `DELEGATECALL (1)` | [S] | P0 |
| SEM-EOB-10 | Returns `true` on successful Safe module execution | [U] | P1 |
| SEM-EOB-11 | Safe returns `false` — reverts `ExecutionFailed` | [N] | P0 |
| SEM-EOB-12 | Downstream target reverts (Safe reports failure) — module reverts `ExecutionFailed` | [N] | P0 |
| SEM-EOB-13 | Safe call reverts unexpectedly — execution reverts (never returns success) | [E] | P1 |
| SEM-EOB-14 | Target that requires non-zero `msg.value` cannot be executed (enforces no-ETH-transfer policy) | [S] | P0 |
| SEM-EOB-15 | Module not enabled on actual Safe — execution fails | [I] | P0 |
| SEM-EOB-16 | Multiple sequential successful calls are independent and deterministic | [U] | P1 |
| SEM-EOB-17 | Non-batch target observes `msg.sender == SAFE` (not module/executor) | [I] | P0 |
| SEM-EOB-18 | `to == BATCHED_TRANSACTION` with valid packed batch executes sub-transactions successfully | [I] | P0 |
| SEM-EOB-19 | `to == BATCHED_TRANSACTION` with sub-transaction targeting Safe fails atomically (module reverts) | [I][S] | P0 |
| SEM-EOB-20 | Safe revert reason/data from `execTransactionFromModule` is bubbled (not remapped to `ExecutionFailed`) | [E] | P1 |
| SEM-EOB-21 | `to == BATCHED_TRANSACTION`: sub-transaction targets observe `msg.sender == SAFE` (delegatecall context preserved) | [I][S] | P0 |
| SEM-EOB-22 | **Desired behavior hardening:** reject `to == address(0)` (fail closed on invalid target) | [S] | P1 |
| SEM-EOB-23 | **Desired behavior hardening:** reject non-contract `to` targets (EOA/no-code) to prevent silent no-op calls | [S] | P1 |

---

### 1.3 `isValidSignature`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| SEM-IVS-1 | Valid EOA signature from `AUTHORIZED_EXECUTOR` over `hash` — returns ERC-1271 magic value | [U] | P0 |
| SEM-IVS-2 | Valid EOA signature from non-authorized signer — returns invalid value | [N] | P0 |
| SEM-IVS-3 | Signature created for different hash — returns invalid value | [S] | P0 |
| SEM-IVS-4 | Empty signature — returns invalid value (no revert) | [E] | P0 |
| SEM-IVS-5 | Malformed EOA length/signature bytes — returns invalid value (no revert) | [E] | P0 |
| SEM-IVS-6 | Invalid `v` byte (not 0/27/28) — returns invalid value | [N] | P1 |
| SEM-IVS-7 | High-`s` malleable EOA signature — returns invalid value | [S] | P0 |
| SEM-IVS-8 | ERC-1271 formatted signature where recovered signer != `AUTHORIZED_EXECUTOR` — returns invalid value | [N] | P1 |
| SEM-IVS-9 | Malformed nested ERC-1271 signature payload — returns invalid value (no revert) | [E] | P1 |
| SEM-IVS-10 | Deterministic output: same `(hash, signature)` always returns same value | [U] | P2 |
| SEM-IVS-11 | Function is `view` and does not mutate state | [U] | P2 |
| SEM-IVS-12 | Valid authorized signature is accepted for both EOA `v=27` and `v=28` encodings | [U] | P1 |
| SEM-IVS-13 | Nested ERC-1271 signer contract that reverts on `isValidSignature` yields invalid value (no revert) | [E][S] | P0 |
| SEM-IVS-14 | Nested ERC-1271 signer contract that returns malformed/truncated data yields invalid value (no revert) | [E][S] | P0 |

---

## 2. BatchedTransaction.sol

### 2.1 `execute` — Valid Batch Behavior

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| BT-EVB-1 | Empty `transactions` bytes — succeeds as no-op | [E] | P1 |
| BT-EVB-2 | Single packed transaction executes successfully | [U] | P0 |
| BT-EVB-3 | Multiple packed transactions execute in encoded order | [U] | P0 |
| BT-EVB-4 | Repeated calls to same target preserve order and cumulative state | [U] | P1 |
| BT-EVB-5 | Zero-length calldata sub-transaction is valid (fallback/receive path) | [E] | P1 |
| BT-EVB-6 | Mixed targets within one batch execute correctly | [U] | P1 |
| BT-EVB-7 | Direct call mode (non-delegatecall) works and target sees `msg.sender == BatchedTransaction` | [E] | P2 |
| BT-EVB-8 | Direct call mode still enforces self-target blocking (`to == address(this)`) | [S] | P1 |
| BT-EVB-9 | Delegatecall mode sub-calls see `msg.sender ==` delegatecaller (Safe), not `BatchedTransaction` | [I] | P0 |

---

### 2.2 `execute` — Security and Failure Behavior

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| BT-ESF-1 | Delegatecall context: sub-transaction targeting delegatecaller (`address(this)` == Safe) reverts `CannotCallSafe` | [S] | P0 |
| BT-ESF-2 | Self-target appears in later sub-transaction — entire batch reverts | [S] | P0 |
| BT-ESF-3 | Any sub-transaction revert causes entire batch revert | [S] | P0 |
| BT-ESF-4 | First sub-call success + second sub-call revert => first sub-call side effects are rolled back | [S] | P0 |
| BT-ESF-5 | First sub-call success + second `CannotCallSafe` => first sub-call side effects are rolled back | [S] | P0 |
| BT-ESF-6 | Payable target receives `msg.value == 0` for every sub-call | [S] | P0 |
| BT-ESF-7 | Sub-call requiring positive `msg.value` fails and reverts whole batch | [S] | P0 |
| BT-ESF-8 | Batch cannot transfer ETH from delegatecaller balance via encoded sub-transactions | [S] | P0 |
| BT-ESF-9 | All sub-transactions are executed as `CALL` (no per-subtx delegatecall path) | [S] | P1 |
| BT-ESF-10 | No partial completion is observable after any failure (all-or-nothing) | [S] | P0 |
| BT-ESF-11 | Failed execution never returns success=true (no silent partial failure) | [S] | P0 |
| BT-ESF-12 | **Desired behavior hardening:** sub-transaction with `to == address(0)` reverts (invalid target) | [S] | P1 |
| BT-ESF-13 | **Desired behavior hardening:** sub-transaction to non-contract address (EOA/no-code) reverts | [S] | P1 |

---

### 2.3 `execute` — Malformed Encoding and Bounds

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| BT-EMB-1 | Trailing bytes shorter than one 28-byte header — **desired behavior:** revert invalid encoding | [E][S] | P0 |
| BT-EMB-2 | Declared `dataLength` larger than remaining bytes — **desired behavior:** revert invalid encoding | [E][S] | P0 |
| BT-EMB-3 | Malformed first transaction causes revert before any external call executes | [S] | P0 |
| BT-EMB-4 | Malformed later transaction reverts and rolls back earlier successful sub-calls | [S] | P0 |
| BT-EMB-5 | Valid transaction + trailing garbage bytes — **desired behavior:** revert (strict parser) | [E] | P1 |
| BT-EMB-6 | Exact boundary case: header-only entry with `dataLength=0` is accepted | [E] | P1 |
| BT-EMB-7 | Extremely large declared `dataLength` with short payload reverts safely | [S] | P0 |
| BT-EMB-8 | Offset/length confusion cannot bypass self-call block (`CannotCallSafe`) | [S] | P0 |
| BT-EMB-9 | Malformed payload must not silently succeed using zero-padded calldata | [S] | P0 |

---

## 3. LibOrganizationAccountSignature.sol (Safe Module Integration Subset)

> **Prerequisite for private-function testing:**  
> `_isValidGuardianSignature`, `_validatePolicyBasedSignature`, `_isERC1271SignatureAllowedByPolicy`,
> `_getInitiatorSignatureHash`, and `_getReviewSignatureHash` are currently `private`.  
> For direct tests, convert them to `internal` and expose them through a harness contract.

### 3.1 `_isValidGuardianSignature`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-IVGS-1 | Guardian direct signature (recovered signer == guardian) returns `true` | [U] | P0 |
| LOAS-IVGS-2 | Enabled Safe module + valid module-based signature returns `true` | [I] | P0 |
| LOAS-IVGS-3 | Valid module signature from non-enabled module returns `false` | [S] | P0 |
| LOAS-IVGS-4 | Module enabled on another Safe (not guardian Safe) returns `false` | [S] | P0 |
| LOAS-IVGS-5 | Module inner signature signed by wrong executor returns `false` | [N] | P0 |
| LOAS-IVGS-6 | Malformed module inner signature returns `false` (no revert) | [E] | P0 |
| LOAS-IVGS-7 | Guardian contract that reverts on `isModuleEnabled` staticcall returns `false` gracefully | [E] | P0 |
| LOAS-IVGS-8 | Guardian contract that returns truncated data (`<32 bytes`) or malformed data (not `true` or `false`) for `isModuleEnabled` returns `false` | [E] | P0 |
| LOAS-IVGS-9 | Guardian is EOA and recovered signer is not guardian returns `false` gracefully | [E] | P0 |
| LOAS-IVGS-10 | Module rotation behavior: old module disabled/new module enabled => old `false`, new `true` immediately | [I][S] | P0 |

---

### 3.2 `_validatePolicyBasedSignature` (Guardian Module Path)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-VPBS-1 | AutoApprove policy + valid initiator + valid enabled-module guardian signature => magic value | [I] | P0 |
| LOAS-VPBS-2 | Same request with module disabled => invalid value | [S] | P0 |
| LOAS-VPBS-3 | ManualApproval policy still requires valid review signatures even with valid module guardian signature | [S] | P0 |
| LOAS-VPBS-4 | ManualApproval with insufficient/invalid review signatures => invalid value | [N] | P0 |
| LOAS-VPBS-5 | Guardian signature is bound to review hash (changing initiator signature invalidates guardian signature) | [S] | P0 |
| LOAS-VPBS-6 | Guardian signature over wrong message hash => invalid value | [S] | P0 |
| LOAS-VPBS-7 | Malformed ABI-encoded policy payload — **desired behavior:** return invalid value (never revert) | [E][S] | P0 |
| LOAS-VPBS-8 | Policy non-applicability or unauthorized initiator => invalid value even with valid module guardian signature | [S] | P0 |
| LOAS-VPBS-9 | `expirationTimestamp == block.timestamp` is accepted (strict `>` expiry check) | [E] | P1 |
| LOAS-VPBS-10 | AutoApprove policy ignores `reviewSignatures` payload (guardian + initiator remain sufficient) | [E][U] | P1 |
| LOAS-VPBS-11 | **Desired behavior:** downstream reviewer-validation revert is mapped to invalid value (never reverts outward) | [S] | P0 |

---

### 3.3 `_isERC1271SignatureAllowedByPolicy` (Guardian Module Path Dependencies)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-IESABP-1 | Policy not found in org policy tree => returns `false` | [S] | P0 |
| LOAS-IESABP-2 | Policy `transactionType != Signatures` => returns `false` | [N] | P0 |
| LOAS-IESABP-3 | Source account not allowed by policy => returns `false` | [N] | P0 |
| LOAS-IESABP-4 | Initiator not authorized by policy => returns `false` | [N] | P0 |
| LOAS-IESABP-5 | All checks pass (policy in tree + signature tx type + source account + initiator authorized) => returns `true` | [U] | P0 |

---

### 3.4 `_getInitiatorSignatureHash` (Guardian Module Path Dependencies)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-GISH-1 | Deterministic output for identical `(account, hash, policyId, expirationTimestamp)` | [U] | P1 |
| LOAS-GISH-2 | Mutating any signed field (`account`, `hash`, `policyId`, `expirationTimestamp`) changes hash | [S] | P0 |
| LOAS-GISH-3 | Hash is domain-bound: changing `chainId` or organization address changes output | [S] | P0 |
| LOAS-GISH-4 | Golden-vector test matches documented EIP-712 `InitiateSignatureValidation` field order | [U] | P1 |

---

### 3.5 `_getReviewSignatureHash` (Guardian Module Path Dependencies)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-GRSH-1 | Includes `keccak256(initiatorSignature)` in hash computation | [U] | P0 |
| LOAS-GRSH-2 | Changing `initiatorSignature` changes review hash (guardian/reviewer binding property) | [S] | P0 |
| LOAS-GRSH-3 | Hash is domain-bound: changing `chainId` or organization address changes output | [S] | P0 |
| LOAS-GRSH-4 | Review hash is distinct from initiator hash for same logical request fields | [S] | P0 |

---

## 4. End-to-End Integration Cases

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| SMI-ETE-1 | Full ERC-1271 flow: `Account.isValidSignature` accepts enabled-module Guardian signature from Authorized Executor | [I] | P0 |
| SMI-ETE-2 | Disable module on Guardian Safe => equivalent module-style signatures become invalid without Organization config changes | [I][S] | P0 |
| SMI-ETE-3 | Module rotation (`disable old` + `enable new`) => old signatures fail, new signatures pass immediately | [I][S] | P0 |
| SMI-ETE-4 | Guardian direct signature path continues to work when module path is unavailable | [I] | P1 |
| SMI-ETE-5 | Authorized Executor can execute Guardian-only Organization function via `SafeExecutorModule` | [I] | P0 |
| SMI-ETE-6 | Unauthorized caller cannot execute Guardian-only Organization function via module | [I][S] | P0 |
| SMI-ETE-7 | `SafeExecutorModule -> BatchedTransaction` cannot execute Safe management calls (owner/module/threshold mutation) | [I][S] | P0 |
| SMI-ETE-8 | Safe v1.4.1 with module enabled: Authorized Executor runs one `SafeExecutorModule -> BatchedTransaction` call that executes `modifyMembers` (add members) then `modifyGroups` (create/add groups), and verifies members are immediately usable by groups with consistent final state | [I] | P0 |
| SMI-ETE-9 | Negative ordering + atomicity: same payload encoded as `modifyGroups` (add non-members) before `modifyMembers` reverts atomically and leaves both member/group state unchanged | [I][S] | P0 |
| SMI-ETE-10 | Replay resistance in batched admin flow: second execution reusing consumed admin-auth nonce/salt for either sub-call reverts and applies no partial state changes | [I][S] | P0 |
| SMI-ETE-11 | Execution gating: disabling `SafeExecutorModule` on Safe v1.4.1 or using a non-authorized executor both prevent multi-admin batch execution and leave organization state unchanged | [I][S] | P0 |

---

## 5. Fuzz Tests

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| SMI-FUZ-1 | Fuzz `executeOnBehalf`: random targets (excluding `SAFE`) always choose `DELEGATECALL` iff `target == BATCHED_TRANSACTION` | [F] | P1 |
| SMI-FUZ-2 | Fuzz `executeOnBehalf`: random calldata is forwarded byte-for-byte to Safe | [F] | P1 |
| SMI-FUZ-3 | Fuzz `isValidSignature`: random malformed signatures never revert and never return magic unless signer is authorized | [F][S] | P0 |
| SMI-FUZ-4 | Fuzz valid packed batches: successful execution matches sequential-call semantics | [F] | P1 |
| SMI-FUZ-5 | Fuzz malformed packed batches: always revert and never partially apply state (**desired behavior**) | [F][S] | P0 |
| SMI-FUZ-6 | Fuzz self-target position in batch: any occurrence always causes atomic revert | [F][S] | P0 |
| SMI-FUZ-7 | Fuzz module enable/disable sequences: module-signature acceptance always matches current enabled set | [F][S] | P0 |
| SMI-FUZ-8 | Fuzz random inner module signatures: only correctly signed Authorized Executor signatures validate | [F][S] | P0 |

---

## 6. Invariant Tests

| ID | Invariant | Priority |
|---|-----------|----------|
| SMI-INV-1 | Only `AUTHORIZED_EXECUTOR` can make `executeOnBehalf` succeed | P0 |
| SMI-INV-2 | `SafeExecutorModule` never instructs Safe to send non-zero value | P0 |
| SMI-INV-3 | `SafeExecutorModule` never allows direct `to == SAFE` execution | P0 |
| SMI-INV-4 | `BatchedTransaction` never allows a sub-call to delegatecaller `address(this)` | P0 |
| SMI-INV-5 | Batched execution is atomic: any failing sub-call leaves no persistent side effects | P0 |
| SMI-INV-6 | Guardian module signatures are accepted iff signer is Guardian directly or an enabled Guardian module | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `SafeExecutorModule.constructor` | 11 | P0-P2 |
| `SafeExecutorModule.executeOnBehalf` | 23 | P0-P1 |
| `SafeExecutorModule.isValidSignature` | 14 | P0-P2 |
| `BatchedTransaction.execute` (valid behavior) | 9 | P0-P2 |
| `BatchedTransaction.execute` (security/failure) | 13 | P0-P1 |
| `BatchedTransaction.execute` (malformed/bounds) | 9 | P0-P1 |
| `_isValidGuardianSignature` (safe-module subset) | 10 | P0 |
| `_validatePolicyBasedSignature` (safe-module subset) | 11 | P0-P1 |
| `_isERC1271SignatureAllowedByPolicy` (safe-module subset) | 5 | P0 |
| `_getInitiatorSignatureHash` (safe-module subset) | 4 | P0-P1 |
| `_getReviewSignatureHash` (safe-module subset) | 4 | P0 |
| End-to-end integration | 11 | P0-P1 |
| Fuzz tests | 8 | P0-P1 |
| Invariant tests | 6 | P0 |
| **Total** | **138** | |
