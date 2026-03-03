# 18 — EIP-712 Signatures Test Plan

**Scope:** EIP-712 domain separation, type hashes, typed-data hash construction, and hash usage in admin/account transaction/account signature authorization paths.

**Desired Behavior Source of Truth:**
- `README.md` (Signatures section)
- `docs/SIGNATURES.md` (EIP-712 domain + signed message type definitions)

**Out of Scope (tested elsewhere):**
- Interface files
- Storage library files

**Files Under Test:**
- `src/organization/libraries/LibOrganizationEIP712.sol`
- `src/organization/libraries/LibOrganizationAdmin.sol`
- `src/organization/libraries/LibOrganizationAccountTransaction.sol`
- `src/organization/libraries/LibOrganizationAccountSignature.sol`

**Harness Prerequisite (private -> internal in test branch):**
- For direct unit tests of helper internals, change currently-`private` helpers to `internal` and expose them via harness wrappers.
**Private helpers in scope:**
- `LibOrganizationAdmin._areAdminSignaturesValid`
- `LibOrganizationAdmin._getAdminOperationHash`
- `LibOrganizationAccountTransaction._validateAutoApproveRejectionOrRevert`
- `LibOrganizationAccountTransaction._validateManualConfirmationOrRevert`
- `LibOrganizationAccountTransaction._computeInitiatorHashFromParams`
- `LibOrganizationAccountTransaction._computeReviewHashFromParams`
- `LibOrganizationAccountSignature._validateRecoverySignature`
- `LibOrganizationAccountSignature._validatePolicyBasedSignature`
- `LibOrganizationAccountSignature._isValidGuardianSignature`
- `LibOrganizationAccountSignature._isERC1271SignatureAllowedByPolicy`
- `LibOrganizationAccountSignature._getInitiatorSignatureHash`
- `LibOrganizationAccountSignature._getReviewSignatureHash`

**Out of EIP-712 Scope (covered elsewhere):**
- `LibOrganizationAccountTransaction._validateAndUpdateRateLimitOrRevert` (covered in `08-ACCOUNT-TRANSACTION.md`)

---

## Legend

- `[U]` Unit
- `[S]` Security / replay-focused scenario
- `[N]` Negative path
- `[E]` Edge case
- `[F]` Fuzz
- `[I]` Invariant

---

## File 1: `LibOrganizationEIP712.sol`

### 1.1 Type Hash Constants

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | `EIP712_DOMAIN_TYPEHASH` equals keccak256 of `EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)` | [U] | P1 |
| 2 | `ADMIN_OPERATION_TYPEHASH` equals keccak256 of documented `AdminOperation(...)` type string | [U] | P1 |
| 3 | `INITIATE_ACCOUNT_TRANSACTION_TYPEHASH` equals keccak256 of documented `InitiateAccountTransaction(...)` type string | [U] | P1 |
| 4 | `REVIEW_ACCOUNT_TRANSACTION_TYPEHASH` equals keccak256 of documented `ReviewAccountTransaction(...)` type string | [U] | P1 |
| 5 | `INITIATE_SIGNATURE_VALIDATION_TYPEHASH` equals keccak256 of documented `InitiateSignatureValidation(...)` type string | [U] | P1 |
| 6 | `REVIEW_SIGNATURE_VALIDATION_TYPEHASH` equals keccak256 of documented `ReviewSignatureValidation(...)` type string | [U] | P1 |
| 7 | All six type hashes are unique (no collisions in system-defined message types) | [S] | P1 |

### 1.2 `getDomainSeparator`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 8 | Domain encodes name `MLSWalletOrganization` | [U] | P1 |
| 9 | Domain encodes version `1` | [U] | P1 |
| 10 | Domain encodes current `block.chainid` | [S] | P0 |
| 11 | Domain encodes `address(this)` as verifying contract | [S] | P0 |
| 12 | Deterministic for same chain + same contract across repeated calls | [U] | P1 |
| 13 | Changing chain ID changes domain separator | [S] | P0 |
| 14 | Same chain, different organization address changes domain separator | [S] | P0 |
| 15 | Output equals manual reference `keccak256(abi.encode(...))` using documented fields/order | [U] | P1 |

### 1.3 `computeTypedDataHash`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 16 | Output equals `keccak256("\x19\x01" || domainSeparator || structHash)` | [U] | P1 |
| 17 | Output equals OpenZeppelin `MessageHashUtils.toTypedDataHash(getDomainSeparator(), structHash)` | [U] | P1 |
| 18 | Changing `structHash` changes final typed-data hash | [U] | P1 |
| 19 | Same `structHash` on different organizations produces different output | [S] | P0 |
| 20 | Same `structHash` on different chains produces different output | [S] | P0 |
| 21 | `structHash = bytes32(0)` is handled deterministically (no revert) | [E] | P2 |

---

## File 2: `LibOrganizationAdmin.sol`

### 2.1 `_getAdminOperationHash` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 22 | Deterministic for identical inputs | [U] | P1 |
| 23 | Changing `operationType` changes hash | [S] | P0 |
| 24 | Changing `operationData` changes hash (`keccak256(operationData)` binding) | [S] | P0 |
| 25 | Changing `salt` changes hash | [S] | P0 |
| 26 | Changing `expirationTimestamp` changes hash | [U] | P1 |
| 27 | `isApproval=true` vs `isApproval=false` produces different hash | [S] | P0 |
| 28 | Changing `chainId` changes hash | [S] | P0 |
| 29 | Changing organization address changes hash | [S] | P0 |
| 30 | Empty `operationData` is valid and deterministic (`keccak256("")` path) | [E] | P1 |
| 31 | Golden vector matches manual typed-data hash for documented `AdminOperation` field order | [U] | P1 |

### 2.2 `validateAdminAuthAndConsumeNonceOrRevert` (EIP-712 binding behavior)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 32 | Valid signatures over `_getAdminOperationHash(..., isApproval=true)` authorize execution path | [U] | P0 |
| 33 | Signatures created with `isApproval=false` cannot authorize `isApproval=true` path | [S] | P0 |
| 34 | Signatures are bound to `operationType` (cannot replay across admin operations) | [S] | P0 |
| 35 | Signatures are bound to exact `operationData` bytes (mutated payload fails) | [S] | P0 |
| 36 | Signatures are bound to `expirationTimestamp` (same payload with different expiration fails) | [S] | P0 |
| 37 | Expiration at exactly `block.timestamp` is accepted (strict `>` check) | [E] | P0 |
| 38 | Signatures are bound to `salt` (same operation, different salt fails) | [S] | P0 |
| 39 | Cross-org replay: signatures valid on org A fail on org B | [S] | P0 |
| 40 | Cross-chain replay: signatures valid on chain A fail on chain B | [S] | P0 |

### 2.3 `_areAdminSignaturesValid` (private -> internal via harness, EIP-712 hash enforcement)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 41 | Exactly-threshold valid admin signatures over the provided operation hash returns `true` | [U] | P0 |
| 42 | Reusing the same signatures against a different operation hash is rejected (never treated as valid authorization) | [S] | P0 |
| 43 | Mixed EOA + ERC-1271 admin signatures are validated against the same EIP-712 operation hash | [U] | P0 |

---

## File 3: `LibOrganizationAccountTransaction.sol`

### 3.1 `_computeInitiatorHashFromParams` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 44 | Deterministic for identical params/data/isApproval | [U] | P1 |
| 45 | Changing `account` changes hash | [U] | P0 |
| 46 | Changing `to` changes hash | [U] | P0 |
| 47 | Changing `value` changes hash | [U] | P0 |
| 48 | Changing calldata `data` changes hash (`keccak256(data)` binding) | [S] | P0 |
| 49 | Changing `salt` changes hash | [S] | P0 |
| 50 | Changing `expirationTimestamp` changes hash | [U] | P1 |
| 51 | Changing `policyId` changes hash | [U] | P0 |
| 52 | `isApproval=true` vs `isApproval=false` changes hash | [S] | P0 |
| 53 | Changing `chainId` changes hash | [S] | P0 |
| 54 | Changing organization address changes hash | [S] | P0 |
| 55 | Empty `data` is valid and deterministic | [E] | P1 |
| 56 | Golden vector matches manual typed-data hash for documented `InitiateAccountTransaction` field order | [U] | P1 |

### 3.2 `_computeReviewHashFromParams` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 57 | Includes all initiator-hash fields + `keccak256(initiatorSignature)` | [U] | P0 |
| 58 | Changing `initiatorSignature` changes review hash (approval-binding property) | [S] | P0 |
| 59 | `isApproval=true` vs `isApproval=false` changes review hash | [S] | P0 |
| 60 | Changing `chainId` or organization address changes review hash | [S] | P0 |
| 61 | Empty `initiatorSignature` is hashed as `keccak256("")` (no revert) | [E] | P1 |
| 62 | Golden vector matches manual typed-data hash for documented `ReviewAccountTransaction` field order | [U] | P1 |
| 63 | Review hash is distinct from initiator hash for same logical transaction inputs | [S] | P0 |

### 3.3 `validateTransactionApprovalOrRevert` + `validateTransactionRejectionOrRevert` (EIP-712 binding behavior)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 64 | Approval path accepts initiator signature signed over initiator hash with `isApproval=true` | [U] | P0 |
| 65 | Approval path rejects initiator signature signed over `isApproval=false` hash | [S] | P0 |
| 66 | Rejection path requires original initiator signature tied to approval hash (`isApproval=true`) | [S] | P0 |
| 67 | Rejection review signatures must be over rejection review hash (`isApproval=false`) | [S] | P0 |
| 68 | Approval review signatures cannot be replayed to authorize rejection (and vice versa) | [S] | P0 |
| 69 | Changing initiator signature invalidates reviewer signatures because review hash changes | [S] | P0 |
| 70 | Cross-org replay: transaction signatures valid on org A fail on org B | [S] | P0 |
| 71 | Cross-chain replay: transaction signatures valid on chain A fail on chain B | [S] | P0 |
| 72 | Approval path accepts signatures when `expirationTimestamp == block.timestamp` (strict `>` check) | [E] | P0 |
| 73 | Rejection path accepts signatures when `expirationTimestamp == block.timestamp` (strict `>` check) | [E] | P0 |
| 74 | Transaction signatures are bound to `salt` (same tx fields with different salt fails) | [S] | P0 |

### 3.4 `_validateAutoApproveRejectionOrRevert` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 75 | Rejection signer must sign the initiator-style hash with `isApproval=false` | [S] | P0 |
| 76 | A signature produced for `isApproval=true` cannot authorize auto-approve rejection | [S] | P0 |

### 3.5 `_validateManualConfirmationOrRevert` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 77 | Reviewer approvals are validated against a review hash that binds `isApproval` + `keccak256(initiatorSignature)` | [S] | P0 |
| 78 | Keeping reviewer signatures fixed but mutating `initiatorSignature` causes rejection (binding enforced in helper) | [S] | P0 |

---

## File 4: `LibOrganizationAccountSignature.sol`

### 4.0 `isValidSignature` (routing + graceful invalid behavior)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 79 | Empty signature returns `ERC1271_INVALID_VALUE` (no revert) | [N] | P0 |
| 80 | Unknown type prefix (not `0x00` / `0x01`) returns `ERC1271_INVALID_VALUE` (no revert) | [N] | P0 |
| 81 | Malformed type-`0x01` payload (invalid ABI encoding) returns `ERC1271_INVALID_VALUE` instead of reverting | [N] | P0 |

### 4.1 `_getInitiatorSignatureHash` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 82 | Deterministic for identical inputs | [U] | P1 |
| 83 | Changing `account` changes hash | [U] | P0 |
| 84 | Changing message `hash` changes hash | [U] | P0 |
| 85 | Changing `policyId` changes hash | [U] | P0 |
| 86 | Changing `expirationTimestamp` changes hash | [U] | P1 |
| 87 | Changing `chainId` changes hash | [S] | P0 |
| 88 | Changing organization address changes hash | [S] | P0 |
| 89 | Golden vector matches manual typed-data hash for documented `InitiateSignatureValidation` field order | [U] | P1 |
| 90 | Output equals manual struct hash wrapped via `LibOrganizationEIP712.computeTypedDataHash` | [U] | P1 |

### 4.2 `_getReviewSignatureHash` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 91 | Includes initiator fields plus `keccak256(initiatorSignature)` | [U] | P0 |
| 92 | Changing `initiatorSignature` changes review hash | [S] | P0 |
| 93 | Changing `chainId` or organization address changes review hash | [S] | P0 |
| 94 | Empty `initiatorSignature` is hashed as `keccak256("")` | [E] | P1 |
| 95 | Golden vector matches manual typed-data hash for documented `ReviewSignatureValidation` field order | [U] | P1 |
| 96 | Review hash is distinct from initiator hash for same request | [S] | P0 |
| 97 | Output equals manual struct hash wrapped via `LibOrganizationEIP712.computeTypedDataHash` | [U] | P1 |

### 4.3 `_validatePolicyBasedSignature` (EIP-712 usage behavior)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 98 | Guardian signature must be over review hash (signature over initiator hash is rejected) | [S] | P0 |
| 99 | Reviewer signatures (manual policy) must be over review hash, not initiator hash | [S] | P0 |
| 100 | Mutating `initiatorSignature` in payload invalidates guardian/reviewer signatures via hash binding | [S] | P0 |
| 101 | Mutating signed fields (`account`, `hash`, `policyId`, `expirationTimestamp`) invalidates authorization | [S] | P0 |
| 102 | Cross-org replay: policy-based ERC-1271 signatures valid on org A fail on org B | [S] | P0 |
| 103 | Cross-chain replay: policy-based ERC-1271 signatures valid on chain A fail on chain B | [S] | P0 |
| 104 | Expiration at exactly `block.timestamp` is accepted (strict `>` check) | [E] | P0 |
| 104 | Signature with expiration  < `block.timestamp` returns ERC1271_INVALID_VALUE | [N] | P0 |
| 105 | AutoApprove policy ignores reviewer signatures; valid initiator + guardian signatures remain sufficient | [U] | P0 |
| 106 | Manual-approval malformed/unauthorized review signatures fail (return `ERC1271_INVALID_VALUE` or revert) | [N] | P0 |

### 4.4 `_isValidGuardianSignature` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 107 | Signature from Guardian address directly over the review hash is accepted | [U] | P0 |
| 108 | Signature from an enabled Guardian module over the review hash is accepted | [U] | P0 |
| 109 | Signature from a disabled module is rejected - test by validating a signature from an enabled module is seen as valid, then disable the module from the safe, and confirm that the signature is then seen as invalid | [S] | P0 |
| 110 | Signature over a different message hash is rejected even when signer/module is otherwise valid | [S] | P0 |

### 4.5 `_isERC1271SignatureAllowedByPolicy` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 111 | Returns `true` only when policy is in tree, `transactionType=Signatures`, source account allowed, and initiator authorized | [U] | P0 |
| 112 | Any failed predicate (policy missing, wrong transaction type, wrong account, unauthorized initiator) returns `false` | [N] | P0 |

### 4.6 `_validateRecoverySignature` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 113 | Recovery-enabled valid recovery signature over raw `hash` returns `ERC1271_MAGIC_VALUE` | [U] | P0 |
| 114 | Recovery-disabled or wrong-signer recovery signature returns `ERC1271_INVALID_VALUE` | [N] | P0 |

---

## Cross-File Message-Type Isolation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 115 | Signature for `AdminOperation` hash cannot authorize `InitiateAccountTransaction` flow | [S] | P0 |
| 116 | Signature for `InitiateAccountTransaction` hash cannot authorize `ReviewAccountTransaction` flow | [S] | P0 |
| 117 | Signature for `InitiateSignatureValidation` hash cannot authorize `ReviewSignatureValidation` flow | [S] | P0 |
| 118 | Account-transaction signatures cannot be replayed in ERC-1271 signature validation flow (and vice versa) | [S] | P0 |
| 119 | For the same seeded inputs, all message-type hashes remain distinct because typehash + field layouts differ | [S] | P0 |
| 120 | Type-`0x00` recovery signatures cannot authorize type-`0x01` policy flow (and vice versa) | [S] | P0 |

---

## Fuzz Tests

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 121 | Random valid inputs: each EIP-712 helper is deterministic (same inputs => same hash) | 1000 | P1 |
| 122 | Random single-field mutation in each struct always changes hash | 1000 | P0 |
| 123 | Random `(chainId, organization)` combinations isolate domains for fixed `structHash` | 1000 | P0 |
| 124 | Random `initiatorSignature` bytes always alter review hashes (tx + ERC-1271 helpers) | 1000 | P0 |
| 125 | Random cross-flow replay attempts (wrong message type hash) are always rejected | 1000 | P0 |
| 126 | Random vectors: helper output always matches independent manual EIP-712 reference encoder | 1000 | P1 |
| 127 | Random malformed type-`0x01` payload bytes return `ERC1271_INVALID_VALUE` and never revert | 1000 | P0 |

---

## Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 128 | **Domain determinism:** for fixed `(chainId, organization)`, domain separator is stable | P1 |
| 129 | **Prefix compliance:** typed-data hash is always `keccak256("\x19\x01" || domain || structHash)` | P1 |
| 130 | **Cross-domain isolation:** same struct hash is never valid across different organizations/chains | P0 |
| 131 | **Message-type separation:** system-defined EIP-712 type hashes stay unique and non-interchangeable | P0 |
| 132 | **ERC-1271 graceful failure:** malformed policy-signature payloads return invalid value instead of reverting | P0 |

---

## Summary

| Category | Tests | Priority Focus |
|----------|-------|----------------|
| File/function unit + security cases | 120 | P0/P1 |
| Fuzz tests | 7 | P0/P1 |
| Invariants | 5 | P0/P1 |
| **Total** | **132** | |
