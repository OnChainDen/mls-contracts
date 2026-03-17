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

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOEIP-THC-1 | `EIP712_DOMAIN_TYPEHASH` equals keccak256 of `EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)` | [U] | P1 |
| LOEIP-THC-2 | `ADMIN_OPERATION_TYPEHASH` equals keccak256 of documented `AdminOperation(...)` type string | [U] | P1 |
| LOEIP-THC-3 | `INITIATE_ACCOUNT_TRANSACTION_TYPEHASH` equals keccak256 of documented `InitiateAccountTransaction(...)` type string | [U] | P1 |
| LOEIP-THC-4 | `REVIEW_ACCOUNT_TRANSACTION_TYPEHASH` equals keccak256 of documented `ReviewAccountTransaction(...)` type string | [U] | P1 |
| LOEIP-THC-5 | `INITIATE_SIGNATURE_VALIDATION_TYPEHASH` equals keccak256 of documented `InitiateSignatureValidation(...)` type string | [U] | P1 |
| LOEIP-THC-6 | `REVIEW_SIGNATURE_VALIDATION_TYPEHASH` equals keccak256 of documented `ReviewSignatureValidation(...)` type string | [U] | P1 |
| LOEIP-THC-7 | All six type hashes are unique (no collisions in system-defined message types) | [S] | P1 |

### 1.2 `getDomainSeparator`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOEIP-GDS-1 | Domain encodes name `MLSWalletOrganization` | [U] | P1 |
| LOEIP-GDS-2 | Domain encodes version `1` | [U] | P1 |
| LOEIP-GDS-3 | Domain encodes current `block.chainid` | [S] | P0 |
| LOEIP-GDS-4 | Domain encodes `address(this)` as verifying contract | [S] | P0 |
| LOEIP-GDS-5 | Deterministic for same chain + same contract across repeated calls | [U] | P1 |
| LOEIP-GDS-6 | Changing chain ID changes domain separator | [S] | P0 |
| LOEIP-GDS-7 | Same chain, different organization address changes domain separator | [S] | P0 |
| LOEIP-GDS-8 | Output equals manual reference `keccak256(abi.encode(...))` using documented fields/order | [U] | P1 |

### 1.3 `computeTypedDataHash`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOEIP-CTDH-1 | Output equals `keccak256("\x19\x01" || domainSeparator || structHash)` | [U] | P1 |
| LOEIP-CTDH-2 | Output equals OpenZeppelin `MessageHashUtils.toTypedDataHash(getDomainSeparator(), structHash)` | [U] | P1 |
| LOEIP-CTDH-3 | Changing `structHash` changes final typed-data hash | [U] | P1 |
| LOEIP-CTDH-4 | Same `structHash` on different organizations produces different output | [S] | P0 |
| LOEIP-CTDH-5 | Same `structHash` on different chains produces different output | [S] | P0 |
| LOEIP-CTDH-6 | `structHash = bytes32(0)` is handled deterministically (no revert) | [E] | P2 |

---

## File 2: `LibOrganizationAdmin.sol`

### 2.1 `_getAdminOperationHash` (private -> internal via harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOADM-GAOH-1 | Deterministic for identical inputs | [U] | P1 |
| LOADM-GAOH-2 | Changing `operationType` changes hash | [S] | P0 |
| LOADM-GAOH-3 | Changing `operationData` changes hash (`keccak256(operationData)` binding) | [S] | P0 |
| LOADM-GAOH-4 | Changing `salt` changes hash | [S] | P0 |
| LOADM-GAOH-5 | Changing `expirationTimestamp` changes hash | [U] | P1 |
| LOADM-GAOH-6 | `isApproval=true` vs `isApproval=false` produces different hash | [S] | P0 |
| LOADM-GAOH-7 | Changing `chainId` changes hash | [S] | P0 |
| LOADM-GAOH-8 | Changing organization address changes hash | [S] | P0 |
| LOADM-GAOH-9 | Empty `operationData` is valid and deterministic (`keccak256("")` path) | [E] | P1 |
| LOADM-GAOH-10 | Golden vector matches manual typed-data hash for documented `AdminOperation` field order | [U] | P1 |

### 2.2 `validateAdminAuthAndConsumeNonceOrRevert` (EIP-712 binding behavior)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOADM-VAACNOR-1 | Valid signatures over `_getAdminOperationHash(..., isApproval=true)` authorize execution path | [U] | P0 |
| LOADM-VAACNOR-2 | Signatures created with `isApproval=false` cannot authorize `isApproval=true` path | [S] | P0 |
| LOADM-VAACNOR-3 | Signatures are bound to `operationType` (cannot replay across admin operations) | [S] | P0 |
| LOADM-VAACNOR-4 | Signatures are bound to exact `operationData` bytes (mutated payload fails) | [S] | P0 |
| LOADM-VAACNOR-5 | Signatures are bound to `expirationTimestamp` (same payload with different expiration fails) | [S] | P0 |
| LOADM-VAACNOR-6 | Expiration at exactly `block.timestamp` is accepted (strict `>` check) | [E] | P0 |
| LOADM-VAACNOR-7 | Signatures are bound to `salt` (same operation, different salt fails) | [S] | P0 |
| LOADM-VAACNOR-8 | Cross-org replay: signatures valid on org A fail on org B | [S] | P0 |
| LOADM-VAACNOR-9 | Cross-chain replay: signatures valid on chain A fail on chain B | [S] | P0 |

### 2.3 `_areAdminSignaturesValid` (private -> internal via harness, EIP-712 hash enforcement)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOADM-AASV-1 | Exactly-threshold valid admin signatures over the provided operation hash returns `true` | [U] | P0 |
| LOADM-AASV-2 | Reusing the same signatures against a different operation hash is rejected (never treated as valid authorization) - test for both EOA signatures and ERC1271 contract signatures  | [S] | P0 |
| LOADM-AASV-3 | Mixed EOA + ERC-1271 admin signatures are validated against the same EIP-712 operation hash | [U] | P0 |

---

## File 3: `LibOrganizationAccountTransaction.sol`

### 3.1 `_computeInitiatorHashFromParams` (private -> internal via harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOACT-CIHFP-1 | Deterministic for identical params/data/isApproval | [U] | P1 |
| LOACT-CIHFP-2 | Changing `account` changes hash | [U] | P0 |
| LOACT-CIHFP-3 | Changing `to` changes hash | [U] | P0 |
| LOACT-CIHFP-4 | Changing `value` changes hash | [U] | P0 |
| LOACT-CIHFP-5 | Changing calldata `data` changes hash (`keccak256(data)` binding) | [S] | P0 |
| LOACT-CIHFP-6 | Changing `salt` changes hash | [S] | P0 |
| LOACT-CIHFP-7 | Changing `expirationTimestamp` changes hash | [U] | P1 |
| LOACT-CIHFP-8 | Changing `policyId` changes hash | [U] | P0 |
| LOACT-CIHFP-9 | `isApproval=true` vs `isApproval=false` changes hash | [S] | P0 |
| LOACT-CIHFP-10 | Changing `chainId` changes hash | [S] | P0 |
| LOACT-CIHFP-11 | Changing organization address changes hash | [S] | P0 |
| LOACT-CIHFP-12 | Empty `data` is valid and deterministic | [E] | P1 |
| LOACT-CIHFP-13 | Golden vector matches manual typed-data hash for documented `InitiateAccountTransaction` field order | [U] | P1 |

### 3.2 `_computeReviewHashFromParams` (private -> internal via harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOACT-CRHFP-1 | Includes all initiator-hash fields + `keccak256(initiatorSignature)` | [U] | P0 |
| LOACT-CRHFP-2 | Changing `initiatorSignature` changes review hash (approval-binding property) | [S] | P0 |
| LOACT-CRHFP-3 | `isApproval=true` vs `isApproval=false` changes review hash | [S] | P0 |
| LOACT-CRHFP-4 | Changing `chainId` or organization address changes review hash | [S] | P0 |
| LOACT-CRHFP-5 | Empty `initiatorSignature` is hashed as `keccak256("")` (no revert) | [E] | P1 |
| LOACT-CRHFP-6 | Golden vector matches manual typed-data hash for documented `ReviewAccountTransaction` field order | [U] | P1 |
| LOACT-CRHFP-7 | Review hash is distinct from initiator hash for same logical transaction inputs | [S] | P0 |

### 3.3 `validateTransactionApprovalOrRevert` + `validateTransactionRejectionOrRevert` (EIP-712 binding behavior)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOACT-VTAORVTROR-1 | Approval path accepts initiator signature signed over initiator hash with `isApproval=true` | [U] | P0 |
| LOACT-VTAORVTROR-2 | Approval path rejects initiator signature signed over `isApproval=false` hash | [S] | P0 |
| LOACT-VTAORVTROR-3 | Rejection path requires original initiator signature tied to approval hash (`isApproval=true`) | [S] | P0 |
| LOACT-VTAORVTROR-4 | Rejection review signatures must be over rejection review hash (`isApproval=false`) | [S] | P0 |
| LOACT-VTAORVTROR-5 | Approval review signatures cannot be replayed to authorize rejection (and vice versa) | [S] | P0 |
| LOACT-VTAORVTROR-6 | Changing initiator signature invalidates reviewer signatures because review hash changes | [S] | P0 |
| LOACT-VTAORVTROR-7 | Cross-org replay: transaction signatures valid on org A fail on org B | [S] | P0 |
| LOACT-VTAORVTROR-8 | Cross-chain replay: transaction signatures valid on chain A fail on chain B | [S] | P0 |
| LOACT-VTAORVTROR-9 | Approval path accepts signatures when `expirationTimestamp == block.timestamp` (strict `>` check) | [E] | P0 |
| LOACT-VTAORVTROR-10 | Rejection path accepts signatures when `expirationTimestamp == block.timestamp` (strict `>` check) | [E] | P0 |
| LOACT-VTAORVTROR-11 | Transaction signatures are bound to `salt` (same tx fields with different salt fails) | [S] | P0 |

### 3.4 `_validateAutoApproveRejectionOrRevert` (private -> internal via harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOACT-VAAROR-1 | Rejection signer must sign the initiator-style hash with `isApproval=false` | [S] | P0 |
| LOACT-VAAROR-2 | A signature produced for `isApproval=true` cannot authorize auto-approve rejection | [S] | P0 |

### 3.5 `_validateManualConfirmationOrRevert` (private -> internal via harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOACT-VMCOR-1 | Reviewer approvals are validated against a review hash that binds `isApproval` + `keccak256(initiatorSignature)` | [S] | P0 |
| LOACT-VMCOR-2 | Keeping reviewer signatures fixed but mutating `initiatorSignature` causes rejection (binding enforced in helper) | [S] | P0 |

---

## File 4: `LibOrganizationAccountSignature.sol`

### 4.0 `isValidSignature` (routing behavior)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOACS-IVS-1 | Empty signature returns `ERC1271_INVALID_VALUE` (no revert) | [N] | P0 |
| LOACS-IVS-2 | Unknown type prefix (not `0x00` / `0x01`) returns `ERC1271_INVALID_VALUE` (no revert) | [N] | P0 |

### 4.1 `_getInitiatorSignatureHash` (private -> internal via harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOACS-GISH-1 | Deterministic for identical inputs | [U] | P1 |
| LOACS-GISH-2 | Changing `account` changes hash | [U] | P0 |
| LOACS-GISH-3 | Changing message `hash` changes hash | [U] | P0 |
| LOACS-GISH-4 | Changing `policyId` changes hash | [U] | P0 |
| LOACS-GISH-5 | Changing `expirationTimestamp` changes hash | [U] | P1 |
| LOACS-GISH-6 | Changing `chainId` changes hash | [S] | P0 |
| LOACS-GISH-7 | Changing organization address changes hash | [S] | P0 |
| LOACS-GISH-8 | Golden vector matches manual typed-data hash for documented `InitiateSignatureValidation` field order | [U] | P1 |
| LOACS-GISH-9 | Output equals manual struct hash wrapped via `LibOrganizationEIP712.computeTypedDataHash` | [U] | P1 |

### 4.2 `_getReviewSignatureHash` (private -> internal via harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOACS-GRSH-1 | Includes initiator fields plus `keccak256(initiatorSignature)` | [U] | P0 |
| LOACS-GRSH-2 | Changing `initiatorSignature` changes review hash | [S] | P0 |
| LOACS-GRSH-3 | Changing `chainId` or organization address changes review hash | [S] | P0 |
| LOACS-GRSH-4 | Empty `initiatorSignature` is hashed as `keccak256("")` | [E] | P1 |
| LOACS-GRSH-5 | Golden vector matches manual typed-data hash for documented `ReviewSignatureValidation` field order | [U] | P1 |
| LOACS-GRSH-6 | Review hash is distinct from initiator hash for same request | [S] | P0 |
| LOACS-GRSH-7 | Output equals manual struct hash wrapped via `LibOrganizationEIP712.computeTypedDataHash` | [U] | P1 |

### 4.3 `_validatePolicyBasedSignature` (EIP-712 usage behavior)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOACS-VPBS-1 | Guardian signature must be over review hash (signature over initiator hash is rejected) | [S] | P0 |
| LOACS-VPBS-2 | Reviewer signatures (manual policy) must be over review hash, not initiator hash | [S] | P0 |
| LOACS-VPBS-3 | Mutating `initiatorSignature` in payload invalidates guardian/reviewer signatures via hash binding | [S] | P0 |
| LOACS-VPBS-4 | Mutating signed fields (`account`, `hash`, `policyId`, `expirationTimestamp`) invalidates authorization | [S] | P0 |
| LOACS-VPBS-5 | Cross-org replay: policy-based ERC-1271 signatures valid on org A fail on org B | [S] | P0 |
| LOACS-VPBS-6 | Cross-chain replay: policy-based ERC-1271 signatures valid on chain A fail on chain B | [S] | P0 |
| LOACS-VPBS-7 | Expiration at exactly `block.timestamp` is accepted (strict `>` check) | [E] | P0 |
| LOACS-VPBS-8 | Signature with expiration  < `block.timestamp` returns ERC1271_INVALID_VALUE | [N] | P0 |
| LOACS-VPBS-9 | AutoApprove policy ignores reviewer signatures; valid initiator + guardian signatures remain sufficient | [U] | P0 |
| LOACS-VPBS-10 | Manual-approval malformed/unauthorized review signatures fail (return `ERC1271_INVALID_VALUE` or revert) | [N] | P0 |

### 4.4 `_isValidGuardianSignature` (private -> internal via harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOACS-IVGS-1 | Signature from Guardian address directly over the review hash is accepted | [U] | P0 |
| LOACS-IVGS-2 | Signature from an enabled Guardian module over the review hash is accepted | [U] | P0 |
| LOACS-IVGS-3 | Signature from a disabled module is rejected - test by validating a signature from an enabled module is seen as valid, then disable the module from the safe, and confirm that the signature is then seen as invalid | [S] | P0 |
| LOACS-IVGS-4 | Signature over a different message hash is rejected even when signer/module is otherwise valid | [S] | P0 |

### 4.5 `_isERC1271SignatureAllowedByPolicy` (private -> internal via harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOACS-IESABP-1 | Returns `true` only when policy is in tree, `transactionType=Signatures`, source account allowed, and initiator authorized | [U] | P0 |
| LOACS-IESABP-2 | Any failed predicate (policy missing, wrong transaction type, wrong account, unauthorized initiator) returns `false` | [N] | P0 |

### 4.6 `_validateRecoverySignature` (private -> internal via harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOACS-VRS-1 | Recovery-enabled valid recovery signature over raw `hash` returns `ERC1271_MAGIC_VALUE` | [U] | P0 |
| LOACS-VRS-2 | Recovery-disabled or wrong-signer recovery signature returns `ERC1271_INVALID_VALUE` | [N] | P0 |

---

## Cross-File Message-Type Isolation

| ID | Test Case | Type | Priority |
|---|---|---|---|
| E712-MTI-1 | Signature for `AdminOperation` hash cannot authorize `InitiateAccountTransaction` flow | [S] | P0 |
| E712-MTI-2 | Signature for `InitiateAccountTransaction` hash cannot authorize `ReviewAccountTransaction` flow | [S] | P0 |
| E712-MTI-3 | Signature for `InitiateSignatureValidation` hash cannot authorize `ReviewSignatureValidation` flow | [S] | P0 |
| E712-MTI-4 | Account-transaction signatures cannot be replayed in ERC-1271 signature validation flow (and vice versa) | [S] | P0 |
| E712-MTI-5 | For the same seeded inputs, all message-type hashes remain distinct because typehash + field layouts differ | [S] | P0 |
| E712-MTI-6 | Type-`0x00` recovery signatures cannot authorize type-`0x01` policy flow (and vice versa) | [S] | P0 |

---

## Fuzz Tests

| ID | Test Case | Runs | Priority |
|---|---|---|---|
| E712-FUZ-1 | Random valid inputs: each EIP-712 helper is deterministic (same inputs => same hash) | 1000 | P1 |
| E712-FUZ-2 | Random single-field mutation in each struct always changes hash | 1000 | P0 |
| E712-FUZ-3 | Random `(chainId, organization)` combinations isolate domains for fixed `structHash` | 1000 | P0 |
| E712-FUZ-4 | Random `initiatorSignature` bytes always alter review hashes (tx + ERC-1271 helpers) | 1000 | P0 |
| E712-FUZ-5 | Random cross-flow replay attempts (wrong message type hash) are always rejected | 1000 | P0 |
| E712-FUZ-6 | Random vectors: helper output always matches independent manual EIP-712 reference encoder | 1000 | P1 |

---

## Invariant Tests

| ID | Invariant | Priority |
|---|---|---|
| E712-INV-1 | **Domain determinism:** for fixed `(chainId, organization)`, domain separator is stable | P1 |
| E712-INV-2 | **Prefix compliance:** typed-data hash is always `keccak256("\x19\x01" || domain || structHash)` | P1 |
| E712-INV-3 | **Cross-domain isolation:** same struct hash is never valid across different organizations/chains | P0 |
| E712-INV-4 | **Message-type separation:** system-defined EIP-712 type hashes stay unique and non-interchangeable | P0 |

---

## Summary

| Category | Tests | Priority Focus |
|----------|-------|----------------|
| File/function unit + security cases | 120 | P0/P1 |
| Fuzz tests | 6 | P0/P1 |
| Invariants | 4 | P0/P1 |
| **Total** | **130** | |
