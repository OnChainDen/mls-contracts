# 08 — Account Signature (ERC-1271) Test Plan

**Files Under Test:**
- `src/organization/base/OrganizationAccountSignatureBase.sol`
- `src/organization/libraries/LibOrganizationAccountSignature.sol`

**Private Function Testability Plan (Global):**
All `private` functions in the files under test will be refactored to `internal` for testing and exposed via test harness contracts.

| File | Private functions to convert to `internal` for harness testing |
|---|---|
| `OrganizationAccountSignatureBase.sol` | None |
| `LibOrganizationAccountSignature.sol` | `_validateRecoverySignature`, `_validatePolicyBasedSignature`, `_isValidGuardianSignature`, `_isERC1271SignatureAllowedByPolicy`, `_getInitiatorSignatureHash`, `_getReviewSignatureHash` |

---

## File 1: OrganizationAccountSignatureBase.sol

### 1.1 `isValidSignatureForAccount`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | `msg.sender != account` — reverts `AccountNotDeployedByOrganization` | [N] | P0 |
| 2 | Account not deployed by this organization — reverts `AccountNotDeployedByOrganization` | [N] | P0 |
| 3 | **Desired Behavior:** `anySourceAccount=true` in policy does NOT bypass org-account gate — non-org account still reverts `AccountNotDeployedByOrganization` | [S] | P0 |
| 4 | `msg.sender == account` AND account deployed by org — delegates to `LibOrganizationAccountSignature.isValidSignature` | [U] | P0 |
| 5 | Returns magic value when library returns magic | [U] | P0 |
| 6 | Returns invalid value when library returns invalid | [U] | P0 |
| 7 | Function is `view` — no state changes | [U] | P1 |

---

## File 2: LibOrganizationAccountSignature.sol

### 2.1 `isValidSignature` (type routing)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 7 | Empty signature (length 0) — returns `ERC1271_INVALID_VALUE` | [N] | P0 |
| 8 | Type prefix `0x00` (Recovery) — routes to `_validateRecoverySignature` | [U] | P0 |
| 9 | Type prefix `0x01` (Policy) — routes to `_validatePolicyBasedSignature` | [U] | P0 |
| 10 | Unknown type prefix `0x02` — returns `ERC1271_INVALID_VALUE` | [N] | P0 |
| 11 | Unknown type prefix `0xFF` — returns `ERC1271_INVALID_VALUE` | [N] | P0 |
| 12 | Signature with only type byte (length 1, no data after prefix) — routes correctly with empty `signatureData` | [E] | P0 |
| 13 | Type byte extracted from `signature[0]` — first byte determines routing | [U] | P1 |

---

### 2.2 `_validateRecoverySignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 14 | Recovery enabled AND valid recovery signature — returns magic value | [U] | P0 |
| 15 | Recovery not enabled for Tx/ERC-1271 — returns invalid value | [N] | P0 |
| 16 | Recovery enabled but invalid signature (wrong signer) — returns invalid value | [N] | P0 |
| 17 | Recovery not configured (no recovery address set) — returns invalid value | [N] | P0 |
| 18 | Wrong recovery address signs — returns invalid value | [N] | P0 |
| 19 | Recovery signature with valid EOA signature — accepted | [U] | P0 |
| 20 | Recovery signature with valid ERC-1271 (smart contract) signature — accepted | [U] | P0 |
| 87 | **Desired Behavior:** Malformed recovery signature bytes (bad length/encoding) — returns invalid value (no revert) | [N][S] | P0 |

---

### 2.3 `_validatePolicyBasedSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 21 | ABI decoding of `signatureData` into `(policyId, expirationTimestamp, initiatorSignature, reviewSignatures, guardianSignature, proofs)` | [U] | P0 |
| 22 | Expired (`block.timestamp > expirationTimestamp`) — returns invalid value | [N] | P0 |
| 23 | Expiration at exactly `block.timestamp` — succeeds (strict `>` comparison) | [E] | P0 |
| 24 | Expiration at `block.timestamp + 1` — succeeds (strict `>` comparison) | [E] | P0 |
| 25 | Empty initiator signature (length 0) — returns invalid value | [N] | P0 |
| 26 | Invalid initiator signature (`tryRecoverSigner` fails) — returns invalid value | [N] | P0 |
| 27 | Invalid guardian signature — returns invalid value | [N] | P0 |
| 28 | Policy not allowed by `_isERC1271SignatureAllowedByPolicy` — returns invalid value | [N] | P0 |
| 29 | AutoApprove policy with valid initiator + guardian — returns magic value | [U] | P0 |
| 30 | ManualApproval policy with valid initiator + guardian + sufficient review signatures — returns magic value | [U] | P0 |
| 31 | ManualApproval policy with insufficient review signatures — returns invalid value | [N] | P0 |
| 32 | ManualApproval policy with invalid review signatures (wrong message hash) — returns invalid value | [N] | P0 |
| 33 | Review hash includes `initiatorSignature` — different initiator sigs produce different review hashes (binding) | [S] | P0 |
| 34 | All failure cases return invalid value (never reverts) — function is graceful | [E] | P0 |
| 35 | **Desired Behavior:** Malformed policy `signatureData` (ABI decode failure) — returns invalid value (never reverts) | [S] | P0 |
| 36 | Initiator signature from an authorized ERC-1271 member contract — accepted | [U] | P0 |
| 37 | ManualApproval policy with authorized ERC-1271 reviewer signatures meeting threshold — returns magic value | [U] | P0 |
| 38 | ManualApproval policy with `approverType=Member` and valid designated reviewer signature — returns magic value | [U] | P0 |
| 39 | **Desired Behavior:** Unknown/invalid `PolicyType` value fails closed — returns invalid value | [S] | P0 |
| 40 | **Desired Behavior:** Malformed packed `reviewSignatures` bytes — returns invalid value (never reverts) | [N][S] | P0 |
| 41 | **Desired Behavior:** Duplicate or out-of-order reviewer signers — returns invalid value (never reverts) | [S] | P0 |
| 42 | **Desired Behavior:** Unauthorized reviewer signer — returns invalid value (never reverts) | [S] | P0 |
| 43 | **Desired Behavior:** Approver group does not exist — returns invalid value (never reverts) | [S] | P0 |
| 44 | **Desired Behavior:** Same valid packed signature can be verified repeatedly before expiration — always returns magic (no nonce/state consumption) | [S] | P0 |

---

### 2.4 `_isValidGuardianSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 34 | Guardian is EOA: recovered signer matches guardian address — returns true | [U] | P0 |
| 35 | Guardian is EOA: recovered signer does not match guardian — returns false | [N] | P0 |
| 36 | Guardian is Safe: recovered signer is an enabled module on the Safe — returns true | [U] | P0 |
| 37 | Guardian is Safe: recovered signer is NOT an enabled module — returns false | [N] | P0 |
| 38 | Guardian is Safe: guardian address itself signs (ERC-1271 from Safe) — returns true (direct match) | [U] | P0 |
| 39 | Malformed guardian signature (`tryRecoverSigner` fails) — returns false | [N] | P0 |
| 40 | Guardian is non-Safe contract: `isModuleEnabled()` staticcall reverts — returns false (graceful) | [E] | P0 |
| 41 | Guardian contract returns truncated data (`< 32 bytes`) from `isModuleEnabled()` — returns false | [E] | P0 |
| 42 | Guardian contract returns `false` from `isModuleEnabled()` — returns false | [N] | P0 |
| 43 | Guardian is EOA: staticcall to `isModuleEnabled()` on EOA fails gracefully — returns false | [E] | P0 |
| 44 | Module check uses low-level `staticcall` (no Safe interface imported) — does not revert on unexpected return data | [E] | P1 |

---

### 2.5 `_isERC1271SignatureAllowedByPolicy`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 45 | Policy not in org (invalid Merkle proof) — returns false | [S] | P0 |
| 46 | Policy `transactionType != Signatures` (is `TokenTransfers`) — returns false | [N] | P0 |
| 47 | Policy `transactionType != Signatures` (is `ContractInteractions`) — returns false | [N] | P0 |
| 48 | Policy `transactionType == Any` — returns false (must be exactly `Signatures`) | [S] | P0 |
| 49 | Source account not allowed by policy (specific account, wrong account) — returns false | [N] | P0 |
| 50 | Policy with `anySourceAccount=true` — bypasses source-account proof check (org-account deployment validation is enforced by `isValidSignatureForAccount`) | [U] | P0 |
| 51 | Initiator not authorized by policy — returns false | [N] | P0 |
| 52 | All four checks pass — returns true | [U] | P0 |
| 53 | Checks are sequential: `isPolicyInOrg` checked first, short-circuits on failure | [U] | P1 |
| 54 | Empty `sourceAccountProof` with policy requiring specific source accounts — returns false | [S] | P0 |
| 98 | **Desired Behavior:** `anyInitiator=true` still enforces "Any Member" semantics — non-member initiator returns false | [S] | P0 |
| 99 | `initiatorType=Group` with existing group and initiator in group — returns true | [U] | P0 |
| 100 | `initiatorType=Group` with non-existent group — returns false | [N] | P0 |

---

### 2.6 `_getInitiatorSignatureHash`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 55 | Different organizations (`address(this)`) — produce different hashes | [S] | P0 |
| 56 | Different accounts — produce different hashes | [U] | P0 |
| 57 | Different message hashes — produce different hashes | [U] | P0 |
| 58 | Different `policyId` values — produce different hashes | [U] | P0 |
| 59 | Different `expirationTimestamp` values — produce different hashes | [U] | P0 |
| 60 | Different `block.chainid` values — produce different hashes | [S] | P0 |
| 61 | Uses `INITIATE_SIGNATURE_VALIDATION_TYPEHASH` in struct hash | [U] | P1 |
| 62 | Uses `toTypedDataHash` with domain separator | [U] | P1 |
| 63 | Deterministic: same inputs always produce same hash | [U] | P0 |
| 64 | Golden test: known inputs → known hash (precomputed off-chain) | [U] | P0 |

---

### 2.7 `_getReviewSignatureHash`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 65 | Different organizations (`address(this)`) — produce different review hashes | [S] | P0 |
| 105 | Different accounts — produce different review hashes | [U] | P0 |
| 106 | Different message hashes — produce different review hashes | [U] | P0 |
| 107 | Different `policyId` values — produce different review hashes | [U] | P0 |
| 108 | Different `expirationTimestamp` values — produce different review hashes | [U] | P0 |
| 109 | Different `block.chainid` values — produce different review hashes | [S] | P0 |
| 66 | Additionally includes `keccak256(initiatorSignature)` | [S] | P0 |
| 67 | Different initiator signatures → different review hashes | [S] | P0 |
| 68 | Uses `REVIEW_SIGNATURE_VALIDATION_TYPEHASH` (distinct from initiator typehash) | [U] | P1 |
| 69 | Uses `toTypedDataHash` with domain separator | [U] | P1 |
| 70 | Deterministic: same inputs always produce same hash | [U] | P0 |
| 71 | Golden test: known inputs → known hash (precomputed off-chain) | [U] | P0 |

---

## 3. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 72 | Fuzz: Random hashes with valid policy signature — returns magic value | [F] | P0 |
| 73 | Fuzz: Random type prefixes (not `0x00`/`0x01`) — always returns invalid value | [F] | P0 |
| 74 | Fuzz: Random expiration timestamps — future pass, past fail | [F] | P0 |
| 75 | Fuzz: Random policyIds with valid Merkle proofs — signature validation succeeds | [F] | P0 |
| 76 | Fuzz: Random guardian EOA private keys — guardian signature always accepted when signer matches | [F] | P0 |
| 77 | Fuzz: Random review signer counts below threshold — always returns invalid | [F] | P0 |
| 78 | Fuzz: Random recovery address signatures — valid signer returns magic, wrong signer returns invalid | [F] | P0 |
| 79 | Fuzz: Random initiator signatures — all produce different review hashes (uniqueness) | [F] | P0 |
| 80 | Fuzz: Random accounts — policy with `anySourceAccount=true` always allows, specific account rejects others | [F] | P0 |
| 81 | Fuzz: Random message hashes — changing `hash` always changes both initiator hash and review hash (review hash computed with the same initiator signature captured earlier in the test) | [F][S] | P0 |
| 101 | Fuzz: Random malformed policy-based payloads for type `0x01` — always returns invalid value (never reverts) | [F][S] | P0 |
| 102 | Fuzz: Random authorized signer mixes (EOA/ERC-1271) for initiator/reviewers — outcome depends on policy authorization, not signer encoding | [F] | P0 |

---

## 4. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 82 | **Type prefix exclusivity**: Only `0x00` and `0x01` type prefixes ever produce `ERC1271_MAGIC_VALUE` | P0 |
| 83 | **Never reverts**: `isValidSignature` always returns a value (magic or invalid), never reverts | P0 |
| 84 | **Cross-org replay**: Signatures valid for org A are never valid for org B | P0 |
| 85 | **Initiator binding**: Review hash always changes when initiator signature changes | P0 |
| 86 | **No rate limits**: `isValidSignature` is `view` — no storage modifications ever occur | P0 |
| 103 | **Cross-account replay**: Signatures valid for account A are never valid for account B within the same org | P0 |
| 104 | **Stateless repeatability**: With fixed pre-expiration inputs, repeated `isValidSignature` calls always return the same result and never consume state | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `isValidSignatureForAccount` | 7 | P0-P1 |
| `isValidSignature` (type routing) | 7 | P0-P1 |
| `_validateRecoverySignature` | 8 | P0 |
| `_validatePolicyBasedSignature` | 24 | P0 |
| `_isValidGuardianSignature` | 11 | P0-P1 |
| `_isERC1271SignatureAllowedByPolicy` | 13 | P0-P1 |
| `_getInitiatorSignatureHash` | 10 | P0-P1 |
| `_getReviewSignatureHash` | 12 | P0-P1 |
| Fuzz tests | 12 | P0 |
| Invariant tests | 7 | P0 |
| **Total** | **111** | |
