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

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Sets `SAFE` immutable correctly | [U] | P1 |
| 2 | Sets `AUTHORIZED_EXECUTOR` immutable correctly | [U] | P1 |
| 3 | Sets `BATCHED_TRANSACTION` immutable correctly | [U] | P1 |
| 4 | `safe == address(0)` — reverts `SafeAddressCannotBeZero` | [N] | P0 |
| 5 | `authorizedExecutor == address(0)` — reverts `ExecutorAddressCannotBeZero` | [N] | P0 |
| 6 | `batchedTransaction == address(0)` — reverts `BatchedTransactionAddressCannotBeZero` | [N] | P0 |
| 7 | Multiple invalid params — deterministic revert precedence (`safe` check first) | [E] | P2 |
| 8 | **Desired behavior hardening:** reject non-contract `safe` address (misconfiguration protection) | [S] | P1 |
| 9 | **Desired behavior hardening:** reject non-contract `batchedTransaction` address | [S] | P1 |
| 10 | **Desired behavior hardening:** reject contract `authorizedExecutor` (docs require Authorized Executor EOA) | [S] | P1 |
| 11 | **Desired behavior hardening:** reject `safe == batchedTransaction` configuration | [S] | P1 |

---

### 1.2 `executeOnBehalf`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 12 | Non-authorized caller — reverts `UnauthorizedCaller(caller, AUTHORIZED_EXECUTOR)` | [N] | P0 |
| 13 | Non-authorized caller + `to == SAFE` — still reverts `UnauthorizedCaller` (auth check first) | [S] | P0 |
| 14 | Authorized caller + `to == SAFE` — reverts `CannotCallSafe` | [S] | P0 |
| 15 | Successful call path invokes `Safe.execTransactionFromModule` exactly once | [U] | P1 |
| 16 | Forwards exact `to` argument to Safe | [U] | P1 |
| 17 | Forwards exact `data` bytes to Safe | [U] | P1 |
| 18 | Always forwards `value = 0` | [S] | P0 |
| 19 | `to != BATCHED_TRANSACTION` uses operation `CALL (0)` | [U] | P0 |
| 20 | `to == BATCHED_TRANSACTION` uses operation `DELEGATECALL (1)` | [S] | P0 |
| 21 | Returns `true` on successful Safe module execution | [U] | P1 |
| 22 | Safe returns `false` — reverts `ExecutionFailed` | [N] | P0 |
| 23 | Downstream target reverts (Safe reports failure) — module reverts `ExecutionFailed` | [N] | P0 |
| 24 | Safe call reverts unexpectedly — execution reverts (never returns success) | [E] | P1 |
| 25 | Target that requires non-zero `msg.value` cannot be executed (enforces no-ETH-transfer policy) | [S] | P0 |
| 26 | Module not enabled on actual Safe — execution fails | [I] | P0 |
| 27 | Multiple sequential successful calls are independent and deterministic | [U] | P1 |
| 28 | Non-batch target observes `msg.sender == SAFE` (not module/executor) | [I] | P0 |
| 29 | `to == BATCHED_TRANSACTION` with valid packed batch executes sub-transactions successfully | [I] | P0 |
| 30 | `to == BATCHED_TRANSACTION` with sub-transaction targeting Safe fails atomically (module reverts) | [I][S] | P0 |
| 31 | Safe revert reason/data from `execTransactionFromModule` is bubbled (not remapped to `ExecutionFailed`) | [E] | P1 |
| 32 | `to == BATCHED_TRANSACTION`: sub-transaction targets observe `msg.sender == SAFE` (delegatecall context preserved) | [I][S] | P0 |
| 33 | **Desired behavior hardening:** reject `to == address(0)` (fail closed on invalid target) | [S] | P1 |
| 34 | **Desired behavior hardening:** reject non-contract `to` targets (EOA/no-code) to prevent silent no-op calls | [S] | P1 |

---

### 1.3 `isValidSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 35 | Valid EOA signature from `AUTHORIZED_EXECUTOR` over `hash` — returns ERC-1271 magic value | [U] | P0 |
| 36 | Valid EOA signature from non-authorized signer — returns invalid value | [N] | P0 |
| 37 | Signature created for different hash — returns invalid value | [S] | P0 |
| 38 | Empty signature — returns invalid value (no revert) | [E] | P0 |
| 39 | Malformed EOA length/signature bytes — returns invalid value (no revert) | [E] | P0 |
| 40 | Invalid `v` byte (not 0/27/28) — returns invalid value | [N] | P1 |
| 41 | High-`s` malleable EOA signature — returns invalid value | [S] | P0 |
| 42 | ERC-1271 formatted signature where recovered signer != `AUTHORIZED_EXECUTOR` — returns invalid value | [N] | P1 |
| 43 | Malformed nested ERC-1271 signature payload — returns invalid value (no revert) | [E] | P1 |
| 44 | Deterministic output: same `(hash, signature)` always returns same value | [U] | P2 |
| 45 | Function is `view` and does not mutate state | [U] | P2 |
| 46 | Valid authorized signature is accepted for both EOA `v=27` and `v=28` encodings | [U] | P1 |
| 47 | Nested ERC-1271 signer contract that reverts on `isValidSignature` yields invalid value (no revert) | [E][S] | P0 |
| 48 | Nested ERC-1271 signer contract that returns malformed/truncated data yields invalid value (no revert) | [E][S] | P0 |

---

## 2. BatchedTransaction.sol

### 2.1 `execute` — Valid Batch Behavior

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 49 | Empty `transactions` bytes — succeeds as no-op | [E] | P1 |
| 50 | Single packed transaction executes successfully | [U] | P0 |
| 51 | Multiple packed transactions execute in encoded order | [U] | P0 |
| 52 | Repeated calls to same target preserve order and cumulative state | [U] | P1 |
| 53 | Zero-length calldata sub-transaction is valid (fallback/receive path) | [E] | P1 |
| 54 | Mixed targets within one batch execute correctly | [U] | P1 |
| 55 | Direct call mode (non-delegatecall) works and target sees `msg.sender == BatchedTransaction` | [E] | P2 |
| 56 | Direct call mode still enforces self-target blocking (`to == address(this)`) | [S] | P1 |
| 57 | Delegatecall mode sub-calls see `msg.sender ==` delegatecaller (Safe), not `BatchedTransaction` | [I] | P0 |

---

### 2.2 `execute` — Security and Failure Behavior

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 58 | Delegatecall context: sub-transaction targeting delegatecaller (`address(this)` == Safe) reverts `CannotCallSafe` | [S] | P0 |
| 59 | Self-target appears in later sub-transaction — entire batch reverts | [S] | P0 |
| 60 | Any sub-transaction revert causes entire batch revert | [S] | P0 |
| 61 | First sub-call success + second sub-call revert => first sub-call side effects are rolled back | [S] | P0 |
| 62 | First sub-call success + second `CannotCallSafe` => first sub-call side effects are rolled back | [S] | P0 |
| 63 | Payable target receives `msg.value == 0` for every sub-call | [S] | P0 |
| 64 | Sub-call requiring positive `msg.value` fails and reverts whole batch | [S] | P0 |
| 65 | Batch cannot transfer ETH from delegatecaller balance via encoded sub-transactions | [S] | P0 |
| 66 | All sub-transactions are executed as `CALL` (no per-subtx delegatecall path) | [S] | P1 |
| 67 | No partial completion is observable after any failure (all-or-nothing) | [S] | P0 |
| 68 | Failed execution never returns success=true (no silent partial failure) | [S] | P0 |
| 69 | **Desired behavior hardening:** sub-transaction with `to == address(0)` reverts (invalid target) | [S] | P1 |
| 70 | **Desired behavior hardening:** sub-transaction to non-contract address (EOA/no-code) reverts | [S] | P1 |

---

### 2.3 `execute` — Malformed Encoding and Bounds

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 71 | Trailing bytes shorter than one 28-byte header — **desired behavior:** revert invalid encoding | [E][S] | P0 |
| 72 | Declared `dataLength` larger than remaining bytes — **desired behavior:** revert invalid encoding | [E][S] | P0 |
| 73 | Malformed first transaction causes revert before any external call executes | [S] | P0 |
| 74 | Malformed later transaction reverts and rolls back earlier successful sub-calls | [S] | P0 |
| 75 | Valid transaction + trailing garbage bytes — **desired behavior:** revert (strict parser) | [E] | P1 |
| 76 | Exact boundary case: header-only entry with `dataLength=0` is accepted | [E] | P1 |
| 77 | Extremely large declared `dataLength` with short payload reverts safely | [S] | P0 |
| 78 | Offset/length confusion cannot bypass self-call block (`CannotCallSafe`) | [S] | P0 |
| 79 | Malformed payload must not silently succeed using zero-padded calldata | [S] | P0 |

---

## 3. LibOrganizationAccountSignature.sol (Safe Module Integration Subset)

> **Prerequisite for private-function testing:**  
> `_isValidGuardianSignature`, `_validatePolicyBasedSignature`, `_isERC1271SignatureAllowedByPolicy`,
> `_getInitiatorSignatureHash`, and `_getReviewSignatureHash` are currently `private`.  
> For direct tests, convert them to `internal` and expose them through a harness contract.

### 3.1 `_isValidGuardianSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 80 | Guardian direct signature (recovered signer == guardian) returns `true` | [U] | P0 |
| 81 | Enabled Safe module + valid module-based signature returns `true` | [I] | P0 |
| 82 | Valid module signature from non-enabled module returns `false` | [S] | P0 |
| 83 | Module enabled on another Safe (not guardian Safe) returns `false` | [S] | P0 |
| 84 | Module inner signature signed by wrong executor returns `false` | [N] | P0 |
| 85 | Malformed module inner signature returns `false` (no revert) | [E] | P0 |
| 86 | Guardian contract that reverts on `isModuleEnabled` staticcall returns `false` gracefully | [E] | P0 |
| 87 | Guardian contract that returns truncated data (`<32 bytes`) for `isModuleEnabled` returns `false` | [E] | P0 |
| 88 | Guardian is EOA and recovered signer is not guardian returns `false` gracefully | [E] | P0 |
| 89 | Module rotation behavior: old module disabled/new module enabled => old `false`, new `true` immediately | [I][S] | P0 |

---

### 3.2 `_validatePolicyBasedSignature` (Guardian Module Path)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 90 | AutoApprove policy + valid initiator + valid enabled-module guardian signature => magic value | [I] | P0 |
| 91 | Same request with module disabled => invalid value | [S] | P0 |
| 92 | ManualApproval policy still requires valid review signatures even with valid module guardian signature | [S] | P0 |
| 93 | ManualApproval with insufficient/invalid review signatures => invalid value | [N] | P0 |
| 94 | Guardian signature is bound to review hash (changing initiator signature invalidates guardian signature) | [S] | P0 |
| 95 | Guardian signature over wrong message hash => invalid value | [S] | P0 |
| 96 | Malformed ABI-encoded policy payload — **desired behavior:** return invalid value (never revert) | [E][S] | P0 |
| 97 | Policy non-applicability or unauthorized initiator => invalid value even with valid module guardian signature | [S] | P0 |
| 98 | `expirationTimestamp == block.timestamp` is accepted (strict `>` expiry check) | [E] | P1 |
| 99 | AutoApprove policy ignores `reviewSignatures` payload (guardian + initiator remain sufficient) | [E][U] | P1 |
| 100 | **Desired behavior:** downstream reviewer-validation revert is mapped to invalid value (never reverts outward) | [S] | P0 |

---

### 3.3 `_isERC1271SignatureAllowedByPolicy` (Guardian Module Path Dependencies)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 101 | Policy not found in org policy tree => returns `false` | [S] | P0 |
| 102 | Policy `transactionType != Signatures` => returns `false` | [N] | P0 |
| 103 | Source account not allowed by policy => returns `false` | [N] | P0 |
| 104 | Initiator not authorized by policy => returns `false` | [N] | P0 |
| 105 | All checks pass (policy in tree + signature tx type + source account + initiator authorized) => returns `true` | [U] | P0 |

---

### 3.4 `_getInitiatorSignatureHash` (Guardian Module Path Dependencies)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 106 | Deterministic output for identical `(account, hash, policyId, expirationTimestamp)` | [U] | P1 |
| 107 | Mutating any signed field (`account`, `hash`, `policyId`, `expirationTimestamp`) changes hash | [S] | P0 |
| 108 | Hash is domain-bound: changing `chainId` or organization address changes output | [S] | P0 |
| 109 | Golden-vector test matches documented EIP-712 `InitiateSignatureValidation` field order | [U] | P1 |

---

### 3.5 `_getReviewSignatureHash` (Guardian Module Path Dependencies)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 110 | Includes `keccak256(initiatorSignature)` in hash computation | [U] | P0 |
| 111 | Changing `initiatorSignature` changes review hash (guardian/reviewer binding property) | [S] | P0 |
| 112 | Hash is domain-bound: changing `chainId` or organization address changes output | [S] | P0 |
| 113 | Review hash is distinct from initiator hash for same logical request fields | [S] | P0 |

---

## 4. End-to-End Integration Cases

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 114 | Full ERC-1271 flow: `Account.isValidSignature` accepts enabled-module Guardian signature from Authorized Executor | [I] | P0 |
| 115 | Disable module on Guardian Safe => equivalent module-style signatures become invalid without Organization config changes | [I][S] | P0 |
| 116 | Module rotation (`disable old` + `enable new`) => old signatures fail, new signatures pass immediately | [I][S] | P0 |
| 117 | Guardian direct signature path continues to work when module path is unavailable | [I] | P1 |
| 118 | Authorized Executor can execute Guardian-only Organization function via `SafeExecutorModule` | [I] | P0 |
| 119 | Unauthorized caller cannot execute Guardian-only Organization function via module | [I][S] | P0 |
| 120 | `SafeExecutorModule -> BatchedTransaction` cannot execute Safe management calls (owner/module/threshold mutation) | [I][S] | P0 |

---

## 5. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 121 | Fuzz `executeOnBehalf`: random targets (excluding `SAFE`) always choose `DELEGATECALL` iff `target == BATCHED_TRANSACTION` | [F] | P1 |
| 122 | Fuzz `executeOnBehalf`: random calldata is forwarded byte-for-byte to Safe | [F] | P1 |
| 123 | Fuzz `isValidSignature`: random malformed signatures never revert and never return magic unless signer is authorized | [F][S] | P0 |
| 124 | Fuzz valid packed batches: successful execution matches sequential-call semantics | [F] | P1 |
| 125 | Fuzz malformed packed batches: always revert and never partially apply state (**desired behavior**) | [F][S] | P0 |
| 126 | Fuzz self-target position in batch: any occurrence always causes atomic revert | [F][S] | P0 |
| 127 | Fuzz module enable/disable sequences: module-signature acceptance always matches current enabled set | [F][S] | P0 |
| 128 | Fuzz random inner module signatures: only correctly signed Authorized Executor signatures validate | [F][S] | P0 |

---

## 6. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 129 | Only `AUTHORIZED_EXECUTOR` can make `executeOnBehalf` succeed | P0 |
| 130 | `SafeExecutorModule` never instructs Safe to send non-zero value | P0 |
| 131 | `SafeExecutorModule` never allows direct `to == SAFE` execution | P0 |
| 132 | `BatchedTransaction` never allows a sub-call to delegatecaller `address(this)` | P0 |
| 133 | Batched execution is atomic: any failing sub-call leaves no persistent side effects | P0 |
| 134 | Guardian module signatures are accepted iff signer is Guardian directly or an enabled Guardian module | P0 |

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
| End-to-end integration | 7 | P0-P1 |
| Fuzz tests | 8 | P0-P1 |
| Invariant tests | 6 | P0 |
| **Total** | **134** | |
