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

**Harness Prerequisite (private functions):**
- For direct unit tests of private helpers, temporarily change the target helpers to `internal` and expose them via a harness contract.
**Private helpers in scope:**
- `LibOrganizationAdmin._getAdminOperationHash`
- `LibOrganizationAccountTransaction._computeInitiatorHashFromParams`
- `LibOrganizationAccountTransaction._computeReviewHashFromParams`
- `LibOrganizationAccountSignature._getInitiatorSignatureHash`
- `LibOrganizationAccountSignature._getReviewSignatureHash`

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
| 37 | Cross-org replay: signatures valid on org A fail on org B | [S] | P0 |
| 38 | Cross-chain replay: signatures valid on chain A fail on chain B | [S] | P0 |

---

## File 3: `LibOrganizationAccountTransaction.sol`

### 3.1 `_computeInitiatorHashFromParams` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 39 | Deterministic for identical params/data/isApproval | [U] | P1 |
| 40 | Changing `account` changes hash | [U] | P0 |
| 41 | Changing `to` changes hash | [U] | P0 |
| 42 | Changing `value` changes hash | [U] | P0 |
| 43 | Changing calldata `data` changes hash (`keccak256(data)` binding) | [S] | P0 |
| 44 | Changing `salt` changes hash | [S] | P0 |
| 45 | Changing `expirationTimestamp` changes hash | [U] | P1 |
| 46 | Changing `policyId` changes hash | [U] | P0 |
| 47 | `isApproval=true` vs `isApproval=false` changes hash | [S] | P0 |
| 48 | Changing `chainId` changes hash | [S] | P0 |
| 49 | Changing organization address changes hash | [S] | P0 |
| 50 | Empty `data` is valid and deterministic | [E] | P1 |
| 51 | Golden vector matches manual typed-data hash for documented `InitiateAccountTransaction` field order | [U] | P1 |

### 3.2 `_computeReviewHashFromParams` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 52 | Includes all initiator-hash fields + `keccak256(initiatorSignature)` | [U] | P0 |
| 53 | Changing `initiatorSignature` changes review hash (approval-binding property) | [S] | P0 |
| 54 | `isApproval=true` vs `isApproval=false` changes review hash | [S] | P0 |
| 55 | Changing `chainId` or organization address changes review hash | [S] | P0 |
| 56 | Empty `initiatorSignature` is hashed as `keccak256("")` (no revert) | [E] | P1 |
| 57 | Golden vector matches manual typed-data hash for documented `ReviewAccountTransaction` field order | [U] | P1 |
| 58 | Review hash is distinct from initiator hash for same logical transaction inputs | [S] | P0 |

### 3.3 `validateTransactionApprovalOrRevert` + `validateTransactionRejectionOrRevert` (EIP-712 binding behavior)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 59 | Approval path accepts initiator signature signed over initiator hash with `isApproval=true` | [U] | P0 |
| 60 | Approval path rejects initiator signature signed over `isApproval=false` hash | [S] | P0 |
| 61 | Rejection path requires original initiator signature tied to approval hash (`isApproval=true`) | [S] | P0 |
| 62 | Rejection review signatures must be over rejection review hash (`isApproval=false`) | [S] | P0 |
| 63 | Approval review signatures cannot be replayed to authorize rejection (and vice versa) | [S] | P0 |
| 64 | Changing initiator signature invalidates reviewer signatures because review hash changes | [S] | P0 |
| 65 | Cross-org replay: transaction signatures valid on org A fail on org B | [S] | P0 |
| 66 | Cross-chain replay: transaction signatures valid on chain A fail on chain B | [S] | P0 |

---

## File 4: `LibOrganizationAccountSignature.sol`

### 4.1 `_getInitiatorSignatureHash` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 67 | Deterministic for identical inputs | [U] | P1 |
| 68 | Changing `account` changes hash | [U] | P0 |
| 69 | Changing message `hash` changes hash | [U] | P0 |
| 70 | Changing `policyId` changes hash | [U] | P0 |
| 71 | Changing `expirationTimestamp` changes hash | [U] | P1 |
| 72 | Changing `chainId` changes hash | [S] | P0 |
| 73 | Changing organization address changes hash | [S] | P0 |
| 74 | Golden vector matches manual typed-data hash for documented `InitiateSignatureValidation` field order | [U] | P1 |
| 75 | Output equals manual struct hash wrapped via `LibOrganizationEIP712.computeTypedDataHash` | [U] | P1 |

### 4.2 `_getReviewSignatureHash` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 76 | Includes initiator fields plus `keccak256(initiatorSignature)` | [U] | P0 |
| 77 | Changing `initiatorSignature` changes review hash | [S] | P0 |
| 78 | Changing `chainId` or organization address changes review hash | [S] | P0 |
| 79 | Empty `initiatorSignature` is hashed as `keccak256("")` | [E] | P1 |
| 80 | Golden vector matches manual typed-data hash for documented `ReviewSignatureValidation` field order | [U] | P1 |
| 81 | Review hash is distinct from initiator hash for same request | [S] | P0 |
| 82 | Output equals manual struct hash wrapped via `LibOrganizationEIP712.computeTypedDataHash` | [U] | P1 |

### 4.3 `_validatePolicyBasedSignature` (EIP-712 usage behavior)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 83 | Guardian signature must be over review hash (signature over initiator hash is rejected) | [S] | P0 |
| 84 | Reviewer signatures (manual policy) must be over review hash, not initiator hash | [S] | P0 |
| 85 | Mutating `initiatorSignature` in payload invalidates guardian/reviewer signatures via hash binding | [S] | P0 |
| 86 | Mutating signed fields (`account`, `hash`, `policyId`, `expirationTimestamp`) invalidates authorization | [S] | P0 |
| 87 | Cross-org replay: policy-based ERC-1271 signatures valid on org A fail on org B | [S] | P0 |
| 88 | Cross-chain replay: policy-based ERC-1271 signatures valid on chain A fail on chain B | [S] | P0 |

---

## Cross-File Message-Type Isolation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 89 | Signature for `AdminOperation` hash cannot authorize `InitiateAccountTransaction` flow | [S] | P0 |
| 90 | Signature for `InitiateAccountTransaction` hash cannot authorize `ReviewAccountTransaction` flow | [S] | P0 |
| 91 | Signature for `InitiateSignatureValidation` hash cannot authorize `ReviewSignatureValidation` flow | [S] | P0 |
| 92 | Account-transaction signatures cannot be replayed in ERC-1271 signature validation flow (and vice versa) | [S] | P0 |
| 93 | For the same seeded inputs, all message-type hashes remain distinct because typehash + field layouts differ | [S] | P0 |

---

## Fuzz Tests

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 94 | Random valid inputs: each EIP-712 helper is deterministic (same inputs => same hash) | 1000 | P1 |
| 95 | Random single-field mutation in each struct always changes hash | 1000 | P0 |
| 96 | Random `(chainId, organization)` combinations isolate domains for fixed `structHash` | 1000 | P0 |
| 97 | Random `initiatorSignature` bytes always alter review hashes (tx + ERC-1271 helpers) | 1000 | P0 |
| 98 | Random cross-flow replay attempts (wrong message type hash) are always rejected | 1000 | P0 |
| 99 | Random vectors: helper output always matches independent manual EIP-712 reference encoder | 1000 | P1 |

---

## Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 100 | **Domain determinism:** for fixed `(chainId, organization)`, domain separator is stable | P1 |
| 101 | **Prefix compliance:** typed-data hash is always `keccak256("\x19\x01" || domain || structHash)` | P1 |
| 102 | **Cross-domain isolation:** same struct hash is never valid across different organizations/chains | P0 |
| 103 | **Message-type separation:** system-defined EIP-712 type hashes stay unique and non-interchangeable | P0 |

---

## Summary

| Category | Tests | Priority Focus |
|----------|-------|----------------|
| File/function unit + security cases | 93 | P0/P1 |
| Fuzz tests | 6 | P0/P1 |
| Invariants | 4 | P0/P1 |
| **Total** | **103** | |
