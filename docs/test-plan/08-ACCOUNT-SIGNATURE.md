# 08 — Account Signature (ERC-1271) Test Plan

**Files Under Test:**
- `src/account/AccountImplementation.sol`
- `src/organization/base/OrganizationAccountSignatureBase.sol`
- `src/organization/libraries/LibOrganizationAccountSignature.sol`

**Private Function Testability Plan (Global):**
All `private` functions in the files under test will be refactored to `internal` for testing and exposed via test harness contracts.

| File | Private functions to convert to `internal` for harness testing |
|---|---|
| `AccountImplementation.sol` | None |
| `OrganizationAccountSignatureBase.sol` | None |
| `LibOrganizationAccountSignature.sol` | `_validateRecoverySignature`, `_validatePolicyBasedSignature`, `_isValidGuardianSignature`, `_isERC1271SignatureAllowedByPolicy`, `_getInitiatorSignatureHash`, `_getReviewSignatureHash` |

---

## File 1: OrganizationAccountSignatureBase.sol

### 1.1 `isValidSignatureForAccount`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OASB-ISFA-1 | `msg.sender != account` — reverts `AccountNotDeployedByOrganization` | [N] | P0 |
| OASB-ISFA-2 | Account not deployed by this organization — reverts `AccountNotDeployedByOrganization` | [N] | P0 |
| OASB-ISFA-3 | **Desired Behavior:** `anySourceAccount=true` in policy does NOT bypass org-account gate — non-org account still reverts `AccountNotDeployedByOrganization` | [S] | P0 |
| OASB-ISFA-4 | `msg.sender == account` AND account deployed by org — delegates to `LibOrganizationAccountSignature.isValidSignature` | [U] | P0 |
| OASB-ISFA-5 | Returns magic value when library returns magic | [U] | P0 |
| OASB-ISFA-6 | Returns invalid value when library returns invalid | [U] | P0 |
| OASB-ISFA-7 | Function is `view` — no state changes | [U] | P1 |

---

## File 2: LibOrganizationAccountSignature.sol

### 2.1 `isValidSignature` (type routing)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-IVS-1 | Empty signature (length 0) — returns `ERC1271_INVALID_VALUE` | [N] | P0 |
| LOAS-IVS-2 | Type prefix `0x00` (Recovery) — routes to `_validateRecoverySignature` | [U] | P0 |
| LOAS-IVS-3 | Type prefix `0x01` (Policy) — routes to `_validatePolicyBasedSignature` | [U] | P0 |
| LOAS-IVS-4 | Unknown type prefix `0x02` — returns `ERC1271_INVALID_VALUE` | [N] | P0 |
| LOAS-IVS-5 | Unknown type prefix `0xFF` — returns `ERC1271_INVALID_VALUE` | [N] | P0 |
| LOAS-IVS-6 | Signature with only type byte (length 1): `0x00` recovery prefix returns invalid; `0x01` policy prefix reverts during policy decode | [E] | P0 |
| LOAS-IVS-7 | Type byte extracted from `signature[0]` — first byte determines routing | [U] | P1 |

---

### 2.2 `_validateRecoverySignature`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-VRS-1 | Recovery enabled AND valid recovery signature — returns magic value | [U] | P0 |
| LOAS-VRS-2 | Recovery not enabled for Tx/ERC-1271 — returns invalid value | [N] | P0 |
| LOAS-VRS-3 | Recovery enabled but invalid signature (wrong signer) — returns invalid value | [N] | P0 |
| LOAS-VRS-4 | Recovery not configured (no recovery address set) — returns invalid value | [N] | P0 |
| LOAS-VRS-5 | Wrong recovery address signs — returns invalid value | [N] | P0 |
| LOAS-VRS-6 | Recovery signature with valid EOA signature — accepted | [U] | P0 |
| LOAS-VRS-7 | Recovery signature with valid ERC-1271 (smart contract) signature — accepted | [U] | P0 |
| LOAS-VRS-8 | **Desired Behavior:** Malformed recovery signature bytes (bad length/encoding) — returns invalid value (no revert) | [N][S] | P0 |

---

### 2.3 `_validatePolicyBasedSignature`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-VPBS-1 | ABI decoding of `signatureData` into `(policyId, expirationTimestamp, initiatorSignature, reviewSignatures, guardianSignature, proofs)` | [U] | P0 |
| LOAS-VPBS-2 | Expired (`block.timestamp > expirationTimestamp`) — returns invalid value | [N] | P0 |
| LOAS-VPBS-3 | Expiration at exactly `block.timestamp` — succeeds (strict `>` comparison) | [E] | P0 |
| LOAS-VPBS-4 | Expiration at `block.timestamp + 1` — succeeds (strict `>` comparison) | [E] | P0 |
| LOAS-VPBS-5 | Empty initiator signature (length 0) — returns invalid value | [N] | P0 |
| LOAS-VPBS-6 | Invalid initiator signature (`tryRecoverSigner` fails) — returns invalid value | [N] | P0 |
| LOAS-VPBS-7 | Invalid guardian signature — returns invalid value | [N] | P0 |
| LOAS-VPBS-8 | Policy not allowed by `_isERC1271SignatureAllowedByPolicy` — returns invalid value | [N] | P0 |
| LOAS-VPBS-9 | AutoApprove policy with valid initiator + guardian — returns magic value | [U] | P0 |
| LOAS-VPBS-10 | ManualApproval policy with valid initiator + guardian + sufficient review signatures — returns magic value | [U] | P0 |
| LOAS-VPBS-11 | ManualApproval policy with insufficient review signatures — returns invalid value | [N] | P0 |
| LOAS-VPBS-12 | ManualApproval policy with invalid review signatures (wrong message hash) — returns invalid value | [N] | P0 |
| LOAS-VPBS-13 | Review hash includes `initiatorSignature` — different initiator sigs produce different review hashes (binding) | [S] | P0 |
| LOAS-VPBS-14 | Representative authorization/policy failure cases (expired, empty initiator, unauthorized initiator) return invalid value | [E] | P0 |
| LOAS-VPBS-15 | Malformed policy `signatureData` (ABI decode failure) — reverts | [N] | P0 |
| LOAS-VPBS-16 | Initiator signature from an authorized ERC-1271 member contract — accepted | [U] | P0 |
| LOAS-VPBS-17 | ManualApproval policy with authorized ERC-1271 reviewer signatures meeting threshold — returns magic value | [U] | P0 |
| LOAS-VPBS-18 | ManualApproval policy with `approverType=Member` and valid designated reviewer signature — returns magic value | [U] | P0 |
| LOAS-VPBS-19 | Unknown/invalid `PolicyType` value reverts during enum decoding | [N] | P0 |
| LOAS-VPBS-20 | **Desired Behavior:** Malformed packed `reviewSignatures` bytes — returns invalid value (never reverts) | [N][S] | P0 |
| LOAS-VPBS-21 | **Desired Behavior:** Duplicate or out-of-order reviewer signers — returns invalid value (never reverts) | [S] | P0 |
| LOAS-VPBS-22 | **Desired Behavior:** Unauthorized reviewer signer — returns invalid value (never reverts) | [S] | P0 |
| LOAS-VPBS-23 | **Desired Behavior:** Approver group does not exist — returns invalid value (never reverts) | [S] | P0 |
| LOAS-VPBS-24 | **Desired Behavior:** Same valid packed signature can be verified repeatedly before expiration — always returns magic (no nonce/state consumption) | [S] | P0 |

---

### 2.4 `_isValidGuardianSignature`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-IVGS-1 | Guardian is EOA: recovered signer matches guardian address — returns true | [U] | P0 |
| LOAS-IVGS-2 | Guardian is EOA: recovered signer does not match guardian — returns false | [N] | P0 |
| LOAS-IVGS-3 | Guardian is Safe: recovered signer is an enabled module on the Safe — returns true | [U] | P0 |
| LOAS-IVGS-4 | Guardian is Safe: recovered signer is NOT an enabled module — returns false | [N] | P0 |
| LOAS-IVGS-5 | Guardian is Safe: guardian address itself signs (ERC-1271 from Safe) — returns true (direct match) | [U] | P0 |
| LOAS-IVGS-6 | Malformed guardian signature (`tryRecoverSigner` fails) — returns false | [N] | P0 |
| LOAS-IVGS-7 | Guardian is non-Safe contract: `isModuleEnabled()` staticcall reverts — returns false (graceful) | [E] | P0 |
| LOAS-IVGS-8 | Guardian contract returns truncated data (`< 32 bytes`) from `isModuleEnabled()` — returns false | [E] | P0 |
| LOAS-IVGS-9 | Guardian contract returns `false` from `isModuleEnabled()` — returns false | [N] | P0 |
| LOAS-IVGS-10 | Guardian is EOA: staticcall to `isModuleEnabled()` on EOA fails gracefully — returns false | [E] | P0 |
| LOAS-IVGS-11 | Module check uses low-level `staticcall` (no Safe interface imported); unexpected non-boolean return data reverts during bool decode | [E] | P1 |

---

### 2.5 `_isERC1271SignatureAllowedByPolicy`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-IESABP-1 | Policy not in org (invalid Merkle proof) — returns false | [S] | P0 |
| LOAS-IESABP-2 | Policy `transactionType != Signatures` (is `TokenTransfers`) — returns false | [N] | P0 |
| LOAS-IESABP-3 | Policy `transactionType != Signatures` (is `ContractInteractions`) — returns false | [N] | P0 |
| LOAS-IESABP-4 | Policy `transactionType == Any` — returns false (must be exactly `Signatures`) | [S] | P0 |
| LOAS-IESABP-5 | Source account not allowed by policy (specific account, wrong account) — returns false | [N] | P0 |
| LOAS-IESABP-6 | Policy with `anySourceAccount=true` — bypasses source-account proof check (org-account deployment validation is enforced by `isValidSignatureForAccount`) | [U] | P0 |
| LOAS-IESABP-7 | Initiator not authorized by policy — returns false | [N] | P0 |
| LOAS-IESABP-8 | All four checks pass — returns true | [U] | P0 |
| LOAS-IESABP-9 | Checks are sequential: `isPolicyInOrg` checked first, short-circuits on failure | [U] | P1 |
| LOAS-IESABP-10 | Empty `sourceAccountProof` with policy requiring specific source accounts — returns false | [S] | P0 |
| LOAS-IESABP-11 | **Desired Behavior:** `anyInitiator=true` still enforces "Any Member" semantics — non-member initiator returns false | [S] | P0 |
| LOAS-IESABP-12 | `initiatorType=Group` with existing group and initiator in group — returns true | [U] | P0 |
| LOAS-IESABP-13 | `initiatorType=Group` with non-existent group — returns false | [N] | P0 |

---

### 2.6 `_getInitiatorSignatureHash`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-GISH-1 | Different organizations (`address(this)`) — produce different hashes | [S] | P0 |
| LOAS-GISH-2 | Different accounts — produce different hashes | [U] | P0 |
| LOAS-GISH-3 | Different message hashes — produce different hashes | [U] | P0 |
| LOAS-GISH-4 | Different `policyId` values — produce different hashes | [U] | P0 |
| LOAS-GISH-5 | Different `expirationTimestamp` values — produce different hashes | [U] | P0 |
| LOAS-GISH-6 | Different `block.chainid` values — produce different hashes | [S] | P0 |
| LOAS-GISH-7 | Uses `INITIATE_SIGNATURE_VALIDATION_TYPEHASH` in struct hash | [U] | P1 |
| LOAS-GISH-8 | Uses `toTypedDataHash` with domain separator | [U] | P1 |
| LOAS-GISH-9 | Deterministic: same inputs always produce same hash | [U] | P0 |
| LOAS-GISH-10 | Golden test: known inputs → known hash (precomputed off-chain) | [U] | P0 |

---

### 2.7 `_getReviewSignatureHash`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-GRSH-1 | Different organizations (`address(this)`) — produce different review hashes | [S] | P0 |
| LOAS-GRSH-2 | Different accounts — produce different review hashes | [U] | P0 |
| LOAS-GRSH-3 | Different message hashes — produce different review hashes | [U] | P0 |
| LOAS-GRSH-4 | Different `policyId` values — produce different review hashes | [U] | P0 |
| LOAS-GRSH-5 | Different `expirationTimestamp` values — produce different review hashes | [U] | P0 |
| LOAS-GRSH-6 | Different `block.chainid` values — produce different review hashes | [S] | P0 |
| LOAS-GRSH-7 | Additionally includes `keccak256(initiatorSignature)` | [S] | P0 |
| LOAS-GRSH-8 | Different initiator signatures → different review hashes | [S] | P0 |
| LOAS-GRSH-9 | Uses `REVIEW_SIGNATURE_VALIDATION_TYPEHASH` (distinct from initiator typehash) | [U] | P1 |
| LOAS-GRSH-10 | Uses `toTypedDataHash` with domain separator | [U] | P1 |
| LOAS-GRSH-11 | Deterministic: same inputs always produce same hash | [U] | P0 |
| LOAS-GRSH-12 | Golden test: known inputs → known hash (precomputed off-chain) | [U] | P0 |

---

## 3. Fuzz Tests

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| AS-FUZ-1 | Fuzz: Random hashes with valid policy signature — returns magic value | [F] | P0 |
| AS-FUZ-2 | Fuzz: Random type prefixes (not `0x00`/`0x01`) — always returns invalid value | [F] | P0 |
| AS-FUZ-3 | Fuzz: Random expiration timestamps — future pass, past fail | [F] | P0 |
| AS-FUZ-4 | Fuzz: Random policyIds with valid Merkle proofs — signature validation succeeds | [F] | P0 |
| AS-FUZ-5 | Fuzz: Random guardian EOA private keys — guardian signature always accepted when signer matches | [F] | P0 |
| AS-FUZ-6 | Fuzz: Random review signer counts below threshold — always returns invalid | [F] | P0 |
| AS-FUZ-7 | Fuzz: Random recovery address signatures — valid signer returns magic, wrong signer returns invalid | [F] | P0 |
| AS-FUZ-8 | Fuzz: Random initiator signatures — all produce different review hashes (uniqueness) | [F] | P0 |
| AS-FUZ-9 | Fuzz: Random accounts — policy with `anySourceAccount=true` always allows, specific account rejects others | [F] | P0 |
| AS-FUZ-10 | Fuzz: Random message hashes — changing `hash` always changes both initiator hash and review hash (review hash computed with the same initiator signature captured earlier in the test) | [F][S] | P0 |
| AS-FUZ-11 | Fuzz: Random malformed policy-based payloads for type `0x01` with undersized ABI heads — reverts | [F] | P0 |
| AS-FUZ-12 | Fuzz: Random authorized signer mixes (EOA/ERC-1271) for initiator/reviewers — outcome depends on policy authorization, not signer encoding | [F] | P0 |

---

## 4. Invariant Tests

| ID | Invariant | Priority |
|---|-----------|----------|
| AS-INV-1 | **Type prefix exclusivity**: Only `0x00` and `0x01` type prefixes ever produce `ERC1271_MAGIC_VALUE` | P0 |
| AS-INV-2 | **Payload-class behavior**: representative non-policy payloads do not revert, while malformed policy payloads revert | P0 |
| AS-INV-3 | **Cross-org replay**: Signatures valid for org A are never valid for org B | P0 |
| AS-INV-4 | **Initiator binding**: Review hash always changes when initiator signature changes | P0 |
| AS-INV-5 | **No rate limits**: `isValidSignature` is `view` — no storage modifications ever occur | P0 |
| AS-INV-6 | **Cross-account replay**: Signatures valid for account A are never valid for account B within the same org | P0 |
| AS-INV-7 | **Stateless repeatability**: With fixed pre-expiration inputs, repeated `isValidSignature` calls always return the same result and never consume state | P0 |

---

## File 3: AccountImplementation.sol

### `isValidSignature`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| ACI-IVS-1 | Delegates exact `(account, hash, signature)` tuple to organization `isValidSignatureForAccount` | [U] | P0 |
| ACI-IVS-2 | Delegation preserves empty signature payloads | [E] | P0 |
| ACI-IVS-3 | Delegation preserves large signature payloads | [E] | P0 |
| ACI-IVS-4 | Organization returns magic value — account returns magic value | [U] | P0 |
| ACI-IVS-5 | Organization returns invalid value — account returns invalid value | [N] | P0 |
| ACI-IVS-6 | Organization returns custom non-magic `bytes4` — account returns same custom value | [E] | P1 |
| ACI-IVS-7 | Organization reverts with custom error — account does not revert and returns invalid value | [N] | P0 |
| ACI-IVS-8 | Organization reverts with reason string — account does not revert and returns invalid value | [N] | P0 |
| ACI-IVS-9 | Organization reverts with panic — account does not revert and returns invalid value | [N] | P0 |
| ACI-IVS-10 | Organization reverts with empty revert data — account does not revert and returns invalid value | [N] | P0 |
| ACI-IVS-11 | Organization returns empty data successfully — account returns invalid value | [E] | P0 |
| ACI-IVS-12 | Organization returns short data (`< 32` bytes) successfully — account returns invalid value | [E] | P0 |
| ACI-IVS-13 | Organization argument-guard revert (unexpected delegated args) — account does not revert and returns invalid value | [N] | P0 |
| ACI-IVS-14 | Fuzz: arbitrary callers and payloads while organization reverts — account never reverts and always returns invalid value | [F] | P0 |
| ACI-IVS-15 | Fuzz: exact delegated `(account, hash, signature)` tuple with arbitrary organization `bytes4` return — account returns same `bytes4` | [F] | P0 |
| ACI-IVS-16 | Fuzz: successful canonical 32-byte ABI encoding of organization `bytes4` return — account decodes and returns the same `bytes4` | [F] | P1 |
| ACI-IVS-17 | Fuzz: successful short return data (`< 32` bytes) with arbitrary payload bytes — account always returns invalid value | [F] | P0 |
| ACI-IVS-18 | Fuzz: organization revert mode variants (custom error, string, panic, empty revert data) with arbitrary callers/payloads — account always returns invalid value | [F] | P0 |

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
| `AccountImplementation.isValidSignature` | 18 | P0-P1 |
| **Total** | **129** | |
