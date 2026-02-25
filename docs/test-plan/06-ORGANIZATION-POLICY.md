# 06 — Organization Policy Test Plan (By File and Function)

**Goal:** Validate desired organization policy behavior. This plan intentionally includes tests that may fail on current code to expose bugs and undesired behavior.

**In scope (this plan):**
- `src/organization/base/OrganizationPolicyBase.sol`
- `src/organization/libraries/LibOrganizationPolicy.sol`
- `src/organization/libraries/policy/LibPolicyInitiator.sol`
- `src/organization/libraries/policy/LibPolicyApproval.sol`
- `src/organization/libraries/policy/LibPolicyDestination.sol`
- `src/organization/libraries/policy/LibPolicyTokenTransfer.sol`
- `src/organization/libraries/policy/LibPolicyContractInteraction.sol`
- `src/organization/libraries/policy/LibPolicyParameterConstraints.sol`
- `src/organization/libraries/policy/LibPolicyRateLimits.sol`
- `src/organization/libraries/LibOrganizationAccountTransaction.sol` (policy-coupled execution paths)
- `src/organization/libraries/LibOrganizationAccountSignature.sol` (policy-coupled ERC-1271 paths)

**Out of scope**
- `src/interfaces/organization/IOrganizationPolicy.sol`
- `src/organization/libraries/storage/LibOrganizationPolicyStorage.sol`

**Private function coverage requirement:** This plan includes direct tests for functions currently marked `private`. During test implementation, temporarily switch those functions to `internal` and expose them through harness contracts, then restore intended production visibility.

Legend: `[U]` unit, `[N]` negative, `[S]` security, `[E]` edge, `[EV]` event, `[F]` fuzz, `[I]` invariant.

---

## 1. File: `src/organization/base/OrganizationPolicyBase.sol`

### 1.1 `setPolicies(bytes32 newPoliciesRoot, string ipfsCid, AdminAuthParams authParams)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| OPB-SET-1 | Guardian + valid admin auth updates root and emits `PoliciesUpdated` | [U][EV] | P0 |
| OPB-SET-2 | Non-guardian caller reverts with guardian access control error | [N][S] | P0 |
| OPB-SET-3 | Insufficient/invalid admin signatures revert via admin auth validation | [N][S] | P0 |
| OPB-SET-4 | Expired `authParams` reverts | [N] | P0 |
| OPB-SET-5 | Replay with same nonce/salt reverts | [S] | P0 |
| OPB-SET-6 | Tampering `newPoliciesRoot` after signing invalidates auth and reverts | [S] | P0 |
| OPB-SET-7 | Tampering `ipfsCid` after signing invalidates auth and reverts (hash-bound payload) | [S] | P0 |
| OPB-SET-8 | `newPoliciesRoot == bytes32(0)` is allowed and clears policy tree | [E] | P0 |
| OPB-SET-9 | Empty `ipfsCid` is allowed (still emits event) | [E] | P1 |
| OPB-SET-10 | Failed auth attempt must not consume nonce (same salt can later succeed with valid signatures) | [S] | P0 |
| OPB-SET-11 | Transition check: set valid non-zero root `R1` then clear to `bytes32(0)`; previously valid `getPolicyUsage` proof must revert `PolicyVerificationFailed` (no stale-root reads) | [E][S] | P0 |
| OPB-SET-12 | Hardening transition: set `R1`, clear to `0`, then set `R2`; proofs from `R1` must fail while proofs from `R2` succeed | [E][S] | P0 |

### 1.2 `policiesRoot()`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| OPB-ROOT-1 | Returns `bytes32(0)` before any successful `setPolicies` | [U] | P3 |
| OPB-ROOT-2 | Returns latest root after one and multiple updates | [U] | P3 |

### 1.3 `getPolicyUsage(...)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| OPB-USAGE-1 | Valid policy proof returns current usage from rate-limit storage | [U] | P1 |
| OPB-USAGE-2 | Invalid policy proof reverts `PolicyVerificationFailed(policyId)` | [N][S] | P0 |
| OPB-USAGE-3 | Wrong `policyId` for otherwise-valid policy proof reverts `PolicyVerificationFailed` | [N][S] | P0 |
| OPB-USAGE-4 | `policiesRoot == 0` rejects non-empty policy via `PolicyVerificationFailed` | [N] | P0 |
| OPB-USAGE-5 | Policy with no active rate limit returns `0` usage | [U] | P1 |
| OPB-USAGE-6 | Usage is key-scoped correctly by account/destination/initiator scope configuration | [U] | P1 |
| OPB-USAGE-7 | Usage reflects window rollover (old window not counted in new window) | [U][E] | P1 |
| OPB-USAGE-8 | View call does not mutate state | [I] | P2 |
| OPB-USAGE-9 | Root-rotation read guard: set valid root `R1`, confirm read with `R1` proof succeeds, set different non-zero root `R2`, then same read with stale `R1` proof reverts `PolicyVerificationFailed` while `R2` proof succeeds | [E][S] | P0 |

---

## 2. File: `src/organization/libraries/LibOrganizationPolicy.sol`

### 2.1 `setPolicies(bytes32 newPoliciesRoot, string ipfsCid)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOP-SET-1 | Writes `policiesRoot` exactly to `newPoliciesRoot` | [U] | P0 |
| LOP-SET-2 | Emits `PoliciesUpdated(newPoliciesRoot, ipfsCid)` with exact args | [EV] | P1 |
| LOP-SET-3 | Repeated write of same root/CID is idempotent and still emits event | [E] | P2 |

### 2.2 `isPolicyInOrg(uint256 policyId, Policy policy, bytes32[] proof)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOP-MERKLE-1 | Valid policy + valid proof returns `true` | [U] | P0 |
| LOP-MERKLE-2 | Invalid proof returns `false` | [N] | P0 |
| LOP-MERKLE-3 | Wrong `policyId` with valid proof for a different leaf returns `false` | [S] | P0 |
| LOP-MERKLE-4 | Changing any field in `Policy` invalidates proof | [S] | P0 |
| LOP-MERKLE-5 | Empty proof works only for single-leaf tree case | [E] | P1 |
| LOP-MERKLE-6 | Proof order matters (reordered siblings fail) | [S] | P0 |
| LOP-MERKLE-7 | `policiesRoot == 0` fails for normal policies | [N] | P0 |
| LOP-MERKLE-8 | Deterministic behavior across repeated calls with same inputs | [U] | P2 |
| LOP-MERKLE-9 | Leaf hashing uses double-hash construction (validated through known vectors) | [S] | P0 |

### 2.3 `isTransactionAllowedByPolicy(...)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOP-TX-1 | Invalid policy proof returns `false` before any downstream validation | [S] | P0 |
| LOP-TX-2 | Source account mismatch returns `false` | [N] | P0 |
| LOP-TX-3 | Unauthorized initiator returns `false` | [N][S] | P0 |
| LOP-TX-4 | `TransactionType.TokenTransfers`: non-token transaction returns `false` | [U] | P0 |
| LOP-TX-5 | `TransactionType.TokenTransfers`: valid transfer + matching token/amount/destination returns `true` | [U] | P0 |
| LOP-TX-6 | `TransactionType.TokenTransfers`: disallowed token or destination returns `false` | [N] | P0 |
| LOP-TX-7 | `TransactionType.ContractInteractions`: token transfer input returns `false` | [U] | P0 |
| LOP-TX-8 | `TransactionType.ContractInteractions`: valid destination + function proof + constraints returns `true` | [U] | P0 |
| LOP-TX-9 | `TransactionType.ContractInteractions`: function proof mismatch returns `false` | [N] | P0 |
| LOP-TX-10 | `TransactionType.ContractInteractions`: parameter constraint mismatch returns `false` | [N] | P0 |
| LOP-TX-11 | `TransactionType.Any`: destination allowed returns `true` | [U] | P0 |
| LOP-TX-12 | `TransactionType.Any`: destination disallowed returns `false` | [N] | P0 |
| LOP-TX-13 | `TransactionType.Signatures` must not authorize account transactions (returns `false`) | [S] | P0 |
| LOP-TX-14 | Unknown/invalid transaction enum fails closed (`false`) | [S] | P0 |
| LOP-TX-15 | **Desired behavior:** malformed constraints payload fails closed (`false`) rather than bubbling unexpected revert | [S] | P0 |
| LOP-TX-16 | **Desired behavior:** malformed token-transfer calldata fails closed (`false`) in policy-validation path | [S] | P0 |
| LOP-TX-17 | No partial success: all required sub-checks must pass for `true` | [U] | P0 |
| LOP-TX-18 | Deterministic result for same inputs and unchanged state | [U] | P2 |
| LOP-TX-19 | Single-policy-tree case: empty `policyProof` is accepted when `policiesRoot` equals the computed policy leaf (otherwise-valid transaction returns `true`) | [E] | P1 |
| LOP-TX-20 | Single-destination-tree case (`DestinationType.CustomList`): empty `destinationProof` is accepted when destination root equals destination leaf (otherwise-valid transaction returns `true`) | [E] | P1 |
| LOP-TX-21 | `TransactionType.TokenTransfers`: ERC-20 `transfer` selector with calldata `< 68` bytes is rejected (`false`) | [S] | P0 |
| LOP-TX-22 | `TransactionType.TokenTransfers`: ERC-20-like calldata with non-zero top-level `value` is rejected (`false`) | [S] | P0 |
| LOP-TX-23 | `TransactionType.TokenTransfers`: ERC-20 `approve(address,uint256)` calldata with `value == 0` is rejected (`false`) | [S] | P0 |
| LOP-TX-24 | `TransactionType.TokenTransfers`: ERC-20 `transferFrom(address,address,uint256)` calldata with `value == 0` is rejected (`false`) | [S] | P0 |
| LOP-TX-25 | `TransactionType.TokenTransfers`: selector-only calldata (`transfer` selector, 4 bytes total) is rejected (`false`) | [S] | P0 |
| LOP-TX-26 | `TransactionType.TokenTransfers`: calldata shorter than selector (`data.length < 4`) is rejected (`false`) | [S] | P0 |
| LOP-TX-27 | `TransactionType.TokenTransfers`: zero-data zero-value transaction is rejected (`false`) | [E][S] | P0 |
| LOP-TX-28 | Fuzz: `TransactionType.TokenTransfers` rejects random non-`transfer` selectors (68-byte payload, `value == 0`) | [F][S] | P1 |

### 2.4 `isSourceAccountAllowedByPolicy(Policy policy, address sourceAccount, bytes32[] sourceAccountProof)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOP-SRC-1 | `anySourceAccount == true` returns `true` | [U] | P0 |
| LOP-SRC-2 | Specific-source mode: valid account proof returns `true` | [U] | P0 |
| LOP-SRC-3 | Specific-source mode: invalid proof returns `false` | [N] | P0 |
| LOP-SRC-4 | Specific-source mode: proof for different account returns `false` | [S] | P0 |
| LOP-SRC-5 | Unknown source-account root in specific-source mode fails closed | [N] | P1 |
| LOP-SRC-6 | Empty proof only valid for single-leaf source-account tree case | [E] | P1 |

### 2.5 Wrapper passthroughs (`areApprovalsValid`, `computeTimeWindow`, `getCurrentUsage`, `isInitiatorAuthorized`, `getRequiredApprovals`, `getActualDestination`, `computeUsageKey`, `checkAndUpdateRateLimit`)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOP-WRAP-1 | Each wrapper returns exactly the delegated library result for representative success cases | [U] | P1 |
| LOP-WRAP-2 | Wrapper bubbles delegated custom errors unchanged (approval signer/order/group errors) | [N] | P0 |
| LOP-WRAP-3 | Wrapper bubbles delegated signature decoding errors unchanged | [N][S] | P0 |
| LOP-WRAP-4 | `checkAndUpdateRateLimit` wrapper mutates usage only when delegated result is `true` | [U] | P1 |

### 2.6 `_computePolicyLeaf(uint256 policyId, Policy policy)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOP-LEAF-1 | Golden vector: known policy input produces expected leaf hash | [U] | P0 |
| LOP-LEAF-2 | Same `(policyId, policy)` always yields same leaf | [U] | P1 |
| LOP-LEAF-3 | Changing `policyId` or any policy field changes leaf | [U][S] | P0 |
| LOP-LEAF-4 | Leaf equals `keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))))` and not single-hash variant | [S] | P0 |

---

## 3. File: `src/organization/libraries/policy/LibPolicyInitiator.sol`

### 3.1 `isInitiatorAuthorized(Policy policy, address initiatorAddress)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPI-1 | Member-typed initiator: exact configured member + org membership returns `true` | [U] | P0 |
| LPI-2 | Member-typed initiator: non-matching address returns `false` | [N] | P0 |
| LPI-3 | Member-typed initiator: matching address but not org member returns `false` | [S] | P0 |
| LPI-4 | Group-typed initiator: existing group member returns `true` | [U] | P0 |
| LPI-5 | Group-typed initiator: existing group non-member returns `false` | [N] | P0 |
| LPI-6 | Group-typed initiator: non-existent group returns `false` | [N] | P0 |
| LPI-7 | **Desired behavior:** `anyInitiator == true` still requires initiator to be an organization member | [S] | P0 |
| LPI-8 | Zero-address initiator fails closed | [N][S] | P1 |
| LPI-9 | Unknown/invalid initiator enum fails closed (`false`) | [S] | P0 |

---

## 4. File: `src/organization/libraries/policy/LibPolicyApproval.sol`

### 4.1 `areApprovalsValid(Policy policy, bytes signatures, bytes32 messageHash)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPA-1 | Empty `signatures` returns `false` | [N] | P0 |
| LPA-2 | Member approver: authorized member signature returns `true` | [U] | P0 |
| LPA-3 | Member approver: non-authorized signer reverts `UnauthorizedApprovalSigner` | [N][S] | P0 |
| LPA-4 | Member approver: signer not in org reverts `UnauthorizedApprovalSigner` | [N][S] | P0 |
| LPA-5 | Group approver: threshold `N` with exactly `N` valid sorted signatures returns `true` | [U] | P0 |
| LPA-6 | Group approver: threshold `1` with `2` valid sorted signatures returns `true` (more-than-threshold accepted) | [U][E] | P1 |
| LPA-7 | Group approver: fewer than threshold valid signatures returns `false` | [N] | P0 |
| LPA-8 | Group approver: signer in org but not in approver group reverts `UnauthorizedApprovalSigner` | [N][S] | P0 |
| LPA-9 | Group approver: non-existent group reverts `GroupDoesNotExist` | [N] | P0 |
| LPA-10 | Duplicate signer reverts `DuplicateOrOutOfOrderSigner` | [S] | P0 |
| LPA-11 | Out-of-order signer sequence reverts `DuplicateOrOutOfOrderSigner` | [S] | P0 |
| LPA-12 | Malformed packed signature data bubbles signature recovery revert | [N][S] | P0 |
| LPA-13 | Mixed EOA + ERC-1271 signers (sorted by signer address) are supported | [U][S] | P0 |
| LPA-14 | Early-exit behavior: threshold met before trailing malformed bytes still returns `true` (trailing bytes are not parsed) | [E][S] | P1 |
| LPA-15 | **Desired behavior:** group threshold `0` is invalid and should fail closed (false or explicit revert) | [S] | P0 |
| LPA-16 | Deterministic output for same inputs and unchanged membership/group state | [U] | P2 |

### 4.2 `getRequiredApprovals(Policy policy)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPA-REQ-1 | Member approver type always returns `1` | [U] | P0 |
| LPA-REQ-2 | Group approver type returns configured `approvalThreshold` | [U] | P0 |
| LPA-REQ-3 | Member approver ignores `approvalThreshold` field | [E] | P1 |
| LPA-REQ-4 | Unknown/invalid approver type fails closed in caller usage | [S] | P1 |

### 4.3 `_isSignerAuthorizedForPolicy(Policy policy, address signerAddress)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPA-AUTH-1 | Non-member signer returns `false` regardless of approver config | [S] | P0 |
| LPA-AUTH-2 | Member approver type returns `true` only for configured `approverMember` | [U] | P0 |
| LPA-AUTH-3 | Group approver type returns `true` only for members of `approverGroupId` | [U] | P0 |
| LPA-AUTH-4 | Group approver type returns `false` for non-group member | [N] | P0 |
| LPA-AUTH-5 | Unknown/invalid approver type returns `false` | [S] | P0 |
| LPA-AUTH-6 | Zero-address signer returns `false` | [N] | P1 |

---

## 5. File: `src/organization/libraries/policy/LibPolicyDestination.sol`

### 5.1 `getActualDestination(address to, bytes data, uint256 value)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPD-GAD-1 | Native transfer (`data.length == 0`, `value > 0`) returns `to` | [U] | P0 |
| LPD-GAD-2 | Contract interaction (non-token calldata) returns `to` | [U] | P0 |
| LPD-GAD-3 | ERC-20 transfer calldata returns token recipient extracted from calldata | [U] | P0 |
| LPD-GAD-4 | ERC-20 transfer selector + non-zero native `value` is treated as non-token interaction and returns `to` | [E] | P1 |
| LPD-GAD-5 | Zero-value empty-data transaction returns `to` (not a transfer, but destination is still `to`) | [E] | P2 |
| LPD-GAD-6 | **Desired behavior:** malformed transfer calldata fails closed without ambiguous destination | [S] | P1 |
| LPD-GAD-7 | ERC-20 `transfer` selector with calldata `< 68` bytes is treated as non-token interaction and returns `to` | [E] | P1 |

### 5.2 `isDestinationAllowedByPolicy(...)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPD-ALW-1 | `DestinationType.Any` always returns `true` (proof/root ignored) | [U] | P0 |
| LPD-ALW-2 | `CustomList`: native transfer destination with valid proof returns `true` | [U] | P0 |
| LPD-ALW-3 | `CustomList`: native transfer destination with invalid proof returns `false` | [N] | P0 |
| LPD-ALW-4 | `CustomList`: ERC-20 transfer checks recipient (not token contract) | [U][S] | P0 |
| LPD-ALW-5 | `CustomList`: contract interaction checks `to` contract address | [U] | P0 |
| LPD-ALW-6 | Proof for one destination cannot authorize a different destination | [S] | P0 |
| LPD-ALW-7 | Unknown/invalid destination enum fails closed (`false`) | [S] | P0 |
| LPD-ALW-8 | Empty proof only valid for single-leaf destination tree case | [E] | P1 |
| LPD-ALW-9 | Deterministic result for same inputs | [U] | P2 |
| LPD-ALW-10 | `CustomList`: ERC-20 `transfer` selector with calldata `< 68` bytes checks `to` (token contract) as destination; proof for encoded recipient does not authorize | [S] | P0 |
| LPD-ALW-11 | `CustomList`: ERC-20-like calldata with non-zero top-level `value` checks `to` (token contract) as destination; proof for transfer recipient does not authorize | [S] | P0 |
| LPD-ALW-12 | `CustomList`: `approve(address,uint256)` interaction checks `to`; proof for encoded spender does not authorize | [S] | P0 |
| LPD-ALW-13 | `CustomList`: `transferFrom(address,address,uint256)` interaction checks `to`; proof for encoded `from`/`to` parameters does not authorize | [S] | P0 |
| LPD-ALW-14 | `CustomList`: selector-only `transfer` calldata checks `to`; proof for intended recipient does not authorize | [S] | P0 |
| LPD-ALW-15 | `CustomList`: calldata shorter than selector (`data.length < 4`) checks `to`; proof for unrelated address does not authorize | [S] | P1 |
| LPD-ALW-16 | `CustomList`: zero-data zero-value transaction checks `to`; proof for unrelated address does not authorize | [E][S] | P1 |

---

## 6. File: `src/organization/libraries/policy/LibPolicyTokenTransfer.sol`

### 6.1 `isTokenTransferAllowedByPolicy(...)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPT-1 | Valid token + amount + destination returns `true` | [U] | P0 |
| LPT-2 | Disallowed token returns `false` | [N] | P0 |
| LPT-3 | Amount above threshold returns `false` | [N] | P0 |
| LPT-4 | Destination not allowed returns `false` | [N] | P0 |
| LPT-5 | `anyToken == true` allows both native and ERC-20 token addresses | [U] | P0 |
| LPT-6 | Specific native-token policy (`tokenAddress == address(0)`) allows only native transfers | [U] | P1 |
| LPT-7 | Specific ERC-20 token policy allows only that token contract | [U] | P0 |
| LPT-8 | No short-circuit bypass: all three checks must pass | [S] | P0 |
| LPT-9 | **Desired behavior:** non-token-transfer calldata is rejected (`false`) in this function (fail closed) | [S] | P0 |

### 6.2 `_isTokenAllowedByPolicy(Policy policy, address to, bytes data)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPT-TKN-1 | `anyToken == true` returns `true` | [U] | P0 |
| LPT-TKN-2 | Native transfer uses `address(0)` token identity | [U] | P1 |
| LPT-TKN-3 | ERC-20 transfer uses `to` as token contract identity | [U] | P0 |
| LPT-TKN-4 | Non-matching configured token returns `false` | [N] | P0 |
| LPT-TKN-5 | Deterministic output for identical inputs | [U] | P2 |

### 6.3 `_isTokenAmountAllowedByPolicy(Policy policy, bytes data, uint256 value)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPT-AMT-1 | `hasAmountThreshold == false` always returns `true` | [U] | P0 |
| LPT-AMT-2 | Amount below threshold returns `true` | [U] | P0 |
| LPT-AMT-3 | **Desired behavior:** amount exactly equal to threshold is allowed (inclusive max) | [S] | P0 |
| LPT-AMT-4 | Amount above threshold returns `false` | [N] | P0 |
| LPT-AMT-5 | Threshold `0`: only zero-amount transfer should pass (desired) | [E] | P1 |
| LPT-AMT-6 | Native amount extraction uses `value` | [U] | P1 |
| LPT-AMT-7 | **Desired behavior:** malformed ERC-20 amount calldata fails closed (`false`) without unexpected revert | [S] | P0 |
| LPT-AMT-8 | **Desired behavior:** non-transfer selector calldata with threshold enabled fails closed (`false`) | [S] | P0 |

---

## 7. File: `src/organization/libraries/policy/LibPolicyContractInteraction.sol`

### 7.1 `isContractInteractionAllowedByPolicy(...)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPCI-1 | Valid destination + valid function proof + valid params returns `true` | [U] | P0 |
| LPCI-2 | Destination disallowed returns `false` | [N] | P0 |
| LPCI-3 | Function disallowed returns `false` | [N] | P0 |
| LPCI-4 | Parameter constraints mismatch returns `false` | [N] | P0 |
| LPCI-5 | `anyFunction == true` bypasses function proof check but still enforces destination + params | [U][S] | P0 |
| LPCI-6 | Empty `constraints` can be valid if function leaf was built with empty constraints hash | [E] | P1 |
| LPCI-7 | Same selector with different constraints hash must not validate against old proof | [S] | P0 |
| LPCI-8 | Data shorter than selector length is rejected when function filtering is required | [N] | P0 |
| LPCI-9 | **Desired behavior:** malformed constraints payload fails closed (`false`) instead of unexpected revert | [S] | P0 |

### 7.2 `_isFunctionAllowedByPolicy(...)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPCI-FN-1 | `anyFunction == true` returns `true` regardless of proof/data | [U] | P0 |
| LPCI-FN-2 | `anyFunction == false` + `data.length < 4` returns `false` | [N] | P0 |
| LPCI-FN-3 | Valid `(selector, constraintsHash)` proof returns `true` | [U] | P0 |
| LPCI-FN-4 | Invalid proof returns `false` | [N] | P0 |
| LPCI-FN-5 | Selector tampering invalidates previously valid proof | [S] | P0 |
| LPCI-FN-6 | Constraints bytes tampering invalidates proof via changed `constraintsHash` | [S] | P0 |

### 7.3 `_computeFunctionLeaf(bytes4 selector, bytes32 constraintsHash)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPCI-LEAF-1 | Golden vector: known selector/hash produces expected leaf | [U] | P0 |
| LPCI-LEAF-2 | Deterministic for same inputs | [U] | P1 |
| LPCI-LEAF-3 | Changing selector or constraintsHash changes leaf | [S] | P0 |
| LPCI-LEAF-4 | Leaf uses double-hash construction, not single-hash | [S] | P0 |

---

## 8. File: `src/organization/libraries/policy/LibPolicyParameterConstraints.sol`

### 8.1 `areParametersAllowedByConstraints(bytes parameterConstraints, bytes data)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPPC-1 | Empty `parameterConstraints` bytes returns `true` | [U] | P0 |
| LPPC-2 | ABI-encoded empty constraints array returns `true` | [U] | P1 |
| LPPC-3 | Single valid constraint passes | [U] | P0 |
| LPPC-4 | Multiple constraints all passing returns `true` | [U] | P0 |
| LPPC-5 | Any one failing constraint returns `false` | [N] | P0 |
| LPPC-6 | **Desired behavior:** malformed `parameterConstraints` encoding fails closed (`false`) rather than revert | [S] | P0 |
| LPPC-7 | **Desired behavior:** malformed `comparisonData` inside a constraint fails closed (`false`) | [S] | P0 |
| LPPC-8 | Deterministic output for identical constraints and calldata | [U] | P2 |

### 8.2 `_processConstraints(ParameterConstraint[] constraints, bytes data)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPPC-PROC-1 | Correctly advances calldata head offset across mixed head-slot counts | [U] | P0 |
| LPPC-PROC-2 | `paramCalldataHeadSlotCount == 0` returns `false` | [N] | P0 |
| LPPC-PROC-3 | Data shorter than required head size returns `false` | [N] | P0 |
| LPPC-PROC-4 | Multi-constraint processing stops and returns `false` at first failing constraint | [U] | P1 |
| LPPC-PROC-5 | Array/struct constraints with `Any` can span multiple head slots without decode errors | [E] | P1 |
| LPPC-PROC-6 | No out-of-bounds reads on fuzzed offset/head-size combinations | [F][S] | P0 |
| LPPC-PROC-8 | **Desired behavior:** primitive parameter types with `paramCalldataHeadSlotCount > 1` fail closed (`false`) rather than allowing shifted-offset interpretation | [S] | P0 |

### 8.3 `_isParameterAllowedByConstraint(...)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPPC-DISP-1 | `ConstraintType.Any` returns `true` for all supported parameter types | [U] | P0 |
| LPPC-DISP-2 | Unsupported constraint type for parameter kind fails closed (`false`) | [S] | P0 |
| LPPC-DISP-3 | `ParamType.Array` with non-`Any` constraint returns `false` | [N] | P0 |
| LPPC-DISP-4 | `ParamType.Struct` with non-`Any` constraint returns `false` | [N] | P0 |
| LPPC-DISP-5 | Unknown/invalid `ParamType` returns `false` | [S] | P0 |
| LPPC-DISP-6 | Address `OneOf` path validates Merkle proof against decoded root | [U] | P0 |
| LPPC-DISP-7 | Bytes/string path uses dynamic offset and content hashing correctly | [U] | P0 |
| LPPC-DISP-8 | **Desired behavior:** invalid dynamic offset fails closed (`false`) | [S] | P0 |
| LPPC-DISP-9 | Unknown/invalid `ConstraintType` value fails closed (`false`) for all supported `ParamType` dispatch paths | [S] | P0 |

### 8.4 `_isBoolParameterAllowedByConstraint(...)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPPC-BOOL-1 | Exact `true` with canonical bool word `1` returns `true` | [U] | P0 |
| LPPC-BOOL-2 | Exact `false` with canonical bool word `0` returns `true` | [U] | P0 |
| LPPC-BOOL-3 | Exact mismatch returns `false` | [N] | P0 |
| LPPC-BOOL-4 | Non-`Exact` constraint type returns `false` | [N] | P0 |
| LPPC-BOOL-5 | **Desired behavior:** non-canonical non-zero bool word (not `1`) fails closed (`false`) | [S] | P0 |
| LPPC-BOOL-6 | **Desired behavior:** malformed `comparisonData` fails closed (`false`) instead of bubbling decode revert | [S] | P0 |

### 8.5 `_isUintParameterAllowedByConstraint(...)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPPC-UINT-1 | Exact match returns `true`; exact mismatch returns `false` | [U][N] | P0 |
| LPPC-UINT-2 | Range constraint is inclusive at `min` and `max` boundaries | [U] | P0 |
| LPPC-UINT-3 | Out-of-range value returns `false` | [N] | P0 |
| LPPC-UINT-4 | Range with `min > max` fails closed (`false`) | [E] | P0 |
| LPPC-UINT-5 | Unsupported `ConstraintType.OneOf` for Uint returns `false` | [N] | P0 |
| LPPC-UINT-6 | **Desired behavior:** malformed `comparisonData` fails closed (`false`) instead of bubbling decode revert | [S] | P0 |

### 8.6 `_isIntParameterAllowedByConstraint(...)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPPC-INT-1 | Exact match for positive and negative values returns `true` | [U] | P0 |
| LPPC-INT-2 | Exact mismatch returns `false` | [N] | P0 |
| LPPC-INT-3 | Range constraint is inclusive for signed values (including negative-to-positive windows) | [U] | P0 |
| LPPC-INT-4 | Out-of-range value returns `false` | [N] | P0 |
| LPPC-INT-5 | Range with `min > max` fails closed (`false`) | [E] | P0 |
| LPPC-INT-6 | Unsupported `ConstraintType.OneOf` for Int returns `false` | [N] | P0 |
| LPPC-INT-7 | **Desired behavior:** malformed `comparisonData` fails closed (`false`) instead of bubbling decode revert | [S] | P0 |

### 8.7 `_isAddressParameterAllowedByConstraint(...)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPPC-ADDR-1 | Exact match returns `true`; exact mismatch returns `false` | [U][N] | P0 |
| LPPC-ADDR-2 | `OneOf`: valid Merkle proof against configured root returns `true` | [U] | P0 |
| LPPC-ADDR-3 | `OneOf`: invalid proof/root mismatch returns `false` | [N][S] | P0 |
| LPPC-ADDR-4 | Unsupported `ConstraintType.Range` for Address returns `false` | [N] | P0 |
| LPPC-ADDR-5 | Dirty upper 96 bits in `bytes32` param head do not alter extracted lower-160 address behavior | [E] | P1 |
| LPPC-ADDR-6 | **Desired behavior:** malformed `comparisonData` fails closed (`false`) instead of bubbling decode revert | [S] | P0 |

### 8.8 `_isFixedBytesParameterAllowedByConstraint(...)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPPC-FBYTES-1 | Exact bytes32 match returns `true`; mismatch returns `false` | [U][N] | P0 |
| LPPC-FBYTES-2 | Fixed-size bytes values (e.g., bytes1..bytes31) enforce correct ABI left-aligned comparison semantics | [E] | P1 |
| LPPC-FBYTES-3 | Non-`Exact` constraint type returns `false` | [N] | P0 |
| LPPC-FBYTES-4 | **Desired behavior:** malformed `comparisonData` fails closed (`false`) instead of bubbling decode revert | [S] | P0 |

### 8.9 `_isBytesOrStringParameterAllowedByConstraint(...)` *(private; harness target)*

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPPC-BYSTR-1 | Exact hash match for dynamic bytes returns `true`; mismatch returns `false` | [U][N] | P0 |
| LPPC-BYSTR-2 | Exact hash match for string returns `true`; mismatch returns `false` | [U][N] | P0 |
| LPPC-BYSTR-3 | Empty dynamic value (length `0`) is handled correctly | [E] | P1 |
| LPPC-BYSTR-4 | Large dynamic values are parsed and hashed correctly | [E] | P1 |
| LPPC-BYSTR-5 | Offset beyond calldata length returns `false` | [N][S] | P0 |
| LPPC-BYSTR-6 | Declared length extending beyond calldata returns `false` | [N][S] | P0 |
| LPPC-BYSTR-7 | Non-`Exact` constraint type returns `false` | [N] | P0 |
| LPPC-BYSTR-8 | **Desired behavior:** offset that points into ABI head region fails closed (`false`) | [S] | P0 |
| LPPC-BYSTR-9 | **Desired behavior:** arithmetic overflow in offset/length math fails closed (`false`) without panic revert | [S] | P0 |
| LPPC-BYSTR-10 | **Desired behavior:** malformed `comparisonData` fails closed (`false`) instead of bubbling decode revert | [S] | P0 |

---

## 9. File: `src/organization/libraries/policy/LibPolicyRateLimits.sol`

### 9.1 `checkAndUpdateRateLimit(...)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPRL-UPD-1 | `limitType == RateLimitType.None` returns `true` and does not write usage | [U] | P0 |
| LPRL-UPD-2 | `timeIntervalHours == 0` returns `true` and does not write usage | [U] | P0 |
| LPRL-UPD-3 | Usage below limit returns `true` and writes updated usage | [U] | P0 |
| LPRL-UPD-4 | Usage exactly at limit returns `true` and writes updated usage | [U] | P0 |
| LPRL-UPD-5 | Usage above limit returns `false` and does not update usage | [N] | P0 |
| LPRL-UPD-6 | Cumulative usage in same window is enforced | [U] | P0 |
| LPRL-UPD-7 | New time window resets effective usage budget | [U] | P0 |
| LPRL-UPD-8 | Scope-isolated entities do not share usage when configured `PerEntity` | [U] | P1 |
| LPRL-UPD-9 | `usageAmount == 0` is a no-op success | [E] | P2 |
| LPRL-UPD-10 | **Desired behavior:** `currentUsage + usageAmount` overflow fails closed (`false`) rather than revert | [S] | P0 |
| LPRL-UPD-11 | `timeIntervalLimit == 0` and `usageAmount == 0` succeeds and keeps usage unchanged | [E] | P1 |
| LPRL-UPD-12 | `timeIntervalLimit == 0` and `usageAmount > 0` returns `false` and does not mutate usage | [N] | P0 |
| LPRL-UPD-13 | **Desired behavior:** unknown/invalid `RateLimitType` fails closed (`false`) and does not write usage | [S] | P0 |

### 9.2 `computeTimeWindow(Policy policy)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPRL-WIN-1 | `timeIntervalHours == 0` returns `0` | [U] | P0 |
| LPRL-WIN-2 | Computes `block.timestamp / (hours * 3600)` exactly | [U] | P0 |
| LPRL-WIN-3 | Window increments exactly on boundary timestamp | [E] | P1 |
| LPRL-WIN-4 | Supports max `uint16` hour interval without arithmetic issues | [E] | P1 |

### 9.3 `getCurrentUsage(...)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPRL-GET-1 | Returns `0` when no active time-interval limit | [U] | P0 |
| LPRL-GET-2 | Returns tracked usage for current window/key | [U] | P1 |
| LPRL-GET-3 | Usage from other windows is not returned | [U] | P1 |
| LPRL-GET-4 | Usage from other scoped keys is not returned | [U] | P1 |

### 9.4 `computeUsageKey(...)`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LPRL-KEY-1 | All scopes `AcrossAll` ignores account/destination/initiator differences | [U] | P0 |
| LPRL-KEY-2 | `sourceScope == PerEntity` separates usage by account | [U] | P0 |
| LPRL-KEY-3 | `destinationScope == PerEntity` separates usage by destination | [U] | P0 |
| LPRL-KEY-4 | `initiatorScope == PerEntity` separates usage by initiator | [U] | P0 |
| LPRL-KEY-5 | Different `policyId` always yields different keys | [S] | P0 |
| LPRL-KEY-6 | Mixed scope combinations produce expected collisions/separations | [U] | P1 |
| LPRL-KEY-7 | Deterministic output for identical inputs | [U] | P2 |
| LPRL-KEY-8 | Invalid `RateLimitScope` value in any scope dimension fails closed by treating that dimension as `AcrossAll` | [S] | P1 |

---

## 10. Policy Integration Files

### 10.1 File: `src/organization/libraries/LibOrganizationAccountTransaction.sol`

#### `validateTransactionApprovalOrRevert(...)` and policy-coupled private helpers

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOAT-1 | If policy does not apply, reverts `PolicyDoesNotApply(policyId)` | [N][S] | P0 |
| LOAT-2 | Policy proof tampering causes rejection via `PolicyDoesNotApply` | [S] | P0 |
| LOAT-3 | `TransactionType.Signatures` policy cannot approve account transactions | [S] | P0 |
| LOAT-4 | Manual-approval policy with insufficient reviewer approvals reverts `InsufficientApprovals` | [N] | P0 |
| LOAT-5 | Manual-approval policy with valid threshold approvals succeeds | [U] | P0 |
| LOAT-6 | Auto-approve policy ignores reviewer signatures for approval path | [U] | P1 |
| LOAT-7 | Rate-limit exceeded reverts `RateLimitExceeded(policyId)` | [N] | P0 |
| LOAT-8 | For token-transfer policies, usage amount equals transfer amount (not fixed `1`) | [U][S] | P0 |
| LOAT-9 | For non-token policies, usage amount increments by `1` | [U] | P1 |
| LOAT-10 | Rate-limit destination keying uses actual recipient for ERC-20 transfers | [S] | P0 |
| LOAT-11 | Rejection path for auto-approve requires authorized initiator signature over rejection hash | [S] | P0 |
| LOAT-12 | Rejection path for manual-approval requires threshold approvals over rejection hash (`isApproval=false`) | [S] | P0 |
| LOAT-13 | Approval signatures cannot be replayed as rejection signatures (domain separation) | [S] | P0 |
| LOAT-14 | Private hash builders (`_computeInitiatorHashFromParams`, `_computeReviewHashFromParams`) are deterministic and bind all fields (`data`, `salt`, `policyId`, `isApproval`, `chainId`, initiator signature for review hash) | [U][S] | P0 |
| LOAT-15 | **Desired behavior:** for `TransactionType.Any` token transfers, rate-limit usage is count-based (`usageAmount = 1`), not token-amount-based | [S] | P0 |
| LOAT-16 | Pre-rate-limit validation failure (`PolicyDoesNotApply`) leaves rate-limit usage state unchanged | [S] | P0 |
| LOAT-17 | Pre-rate-limit validation failure (`InsufficientApprovals`) leaves rate-limit usage state unchanged | [S] | P0 |
| LOAT-18 | Root transition guard: after policy succeeds under `R1`, clearing root to `0` makes same transaction + old proofs revert `PolicyDoesNotApply` (no stale-root authorization) | [S] | P0 |
| LOAT-19 | Branch comparison: with identical transaction/policy inputs except `approval.policyType`, `AutoApprove` succeeds without reviewer signatures while `RequireManualApproval` reverts `InsufficientApprovals` | [U][S] | P0 |
| LOAT-20 | **Desired Behavior:** Invalid `approval.policyType` enum value in calldata/proofs fails closed (revert) and cannot silently bypass manual-approval checks | [N][S] | P0 |
| LOAT-21 | Branch comparison (inverted setup): with identical transaction/policy inputs except `approval.policyType`, `RequireManualApproval` succeeds with valid threshold reviewer approvals, and flipping to `AutoApprove` also succeeds with the same reviewer-signature payload (ignored by auto-approve path) | [U][S] | P1 |
| LOAT-22 | Rejection branch comparison: with identical rejection inputs except `approval.policyType`, `AutoApprove` succeeds with an authorized initiator rejection signature while `RequireManualApproval` reverts `InsufficientApprovals` for the same payload | [U][S] | P0 |
| LOAT-23 | Rejection branch comparison (inverted setup): with identical rejection inputs except `approval.policyType`, `RequireManualApproval` succeeds with valid reviewer approvals, while `AutoApprove` rejects the same reviewer-signature payload via `TransactionRejectionNotAllowed` (reviewer is not an authorized initiator) | [U][S] | P1 |
| LOAT-24 | Cross-chain replay protection (initiator): initiator signature signed for chain A cannot authorize the same transaction on chain B | [S] | P0 |
| LOAT-25 | Cross-chain replay protection (reviewers): reviewer approval/rejection signatures signed for chain A cannot be replayed on chain B when paired with a valid chain-B initiator signature | [S] | P0 |
| LOAT-26 | **Desired behavior:** invalid `rateLimit.limitType` enum value in calldata/proofs fails closed (revert) and cannot bypass rate-limit enforcement | [N][S] | P0 |
| LOAT-27 | Cross-organization replay protection (initiator): initiator signature signed for organization A cannot authorize the same transaction on organization B | [S] | P0 |
| LOAT-28 | Cross-organization replay protection (reviewers): reviewer approval/rejection signatures signed for organization A cannot be replayed on organization B when paired with a valid organization-B initiator signature | [S] | P0 |

### 10.2 File: `src/organization/libraries/LibOrganizationAccountSignature.sol`

#### `isValidSignature(...)` and policy-coupled private helpers

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOAS-1 | Policy-based signature with valid policy, guardian auth, initiator auth, and approvals returns ERC-1271 magic value | [U] | P0 |
| LOAS-2 | Expired policy-based request returns invalid value | [N] | P0 |
| LOAS-3 | Missing or invalid initiator signature returns invalid value | [N] | P0 |
| LOAS-4 | Invalid guardian signature returns invalid value | [N][S] | P0 |
| LOAS-5 | Enabled guardian module signature is accepted as guardian authorization | [U][S] | P0 |
| LOAS-6 | Guardian module signature from a signer that is not enabled on the guardian Safe returns invalid value | [N][S] | P0 |
| LOAS-7 | Guardian is not a Safe; module-signer authorization path fails closed and returns invalid value | [N][S] | P0 |
| LOAS-8 | Guardian `isModuleEnabled` response malformed/too short fails closed and returns invalid value | [N][S] | P0 |
| LOAS-9 | Policy proof invalid returns invalid value | [N][S] | P0 |
| LOAS-10 | Non-`TransactionType.Signatures` policy returns invalid value | [S] | P0 |
| LOAS-11 | Source account not allowed by policy returns invalid value | [N][S] | P0 |
| LOAS-12 | Unauthorized initiator returns invalid value | [N][S] | P0 |
| LOAS-13 | Auto-approve signature policy succeeds without reviewer signatures once guardian + initiator checks pass | [U] | P0 |
| LOAS-14 | Manual-approval signature policy requires valid reviewer approvals; insufficient approvals return invalid value | [N] | P0 |
| LOAS-15 | Reviewer approvals are bound to initiator signature (`reviewHash` includes `keccak256(initiatorSignature)`) | [S] | P0 |
| LOAS-16 | Private helper `_isERC1271SignatureAllowedByPolicy` fails closed for any failed sub-check | [S] | P0 |
| LOAS-17 | Private hash builders (`_getInitiatorSignatureHash`, `_getReviewSignatureHash`) are deterministic and field-bound | [U][S] | P1 |
| LOAS-18 | **Desired behavior:** malformed policy `signatureData` payload returns ERC-1271 invalid value (fail closed) and does not revert | [S] | P0 |
| LOAS-19 | **Desired behavior:** manual-approval reviewer signatures that would trigger approval-validation reverts (e.g., duplicate/out-of-order/unauthorized signer) return invalid value and do not revert | [S] | P0 |
| LOAS-20 | Root transition guard: after policy-based signature succeeds under `R1`, clearing root to `0` makes same signature payload + old proofs return ERC-1271 invalid value | [S] | P0 |
| LOAS-21 | Branch comparison: with identical signature payload except `approval.policyType` and empty `reviewSignatures`, `AutoApprove` returns ERC-1271 magic value while `RequireManualApproval` returns ERC-1271 invalid value | [U][S] | P0 |
| LOAS-22 | Branch comparison (inverted setup): with identical signature payload except `approval.policyType` and valid reviewer approvals, `RequireManualApproval` returns ERC-1271 magic value and flipping to `AutoApprove` also returns magic value with the same reviewer-signature payload (ignored by auto-approve path) | [U][S] | P1 |
| LOAS-23 | Cross-chain replay protection (initiator): policy-based initiator signature signed for chain A returns ERC-1271 invalid value on chain B | [S] | P0 |
| LOAS-24 | Cross-chain replay protection (guardian/reviewers): guardian and reviewer signatures signed for chain A return ERC-1271 invalid value on chain B when paired with a valid chain-B initiator signature | [S] | P0 |
| LOAS-25 | Empty top-level signature bytes (`signature.length == 0`) returns ERC-1271 invalid value | [N] | P0 |
| LOAS-26 | Unknown signature type prefix (not `0x00` recovery or `0x01` policy) returns ERC-1271 invalid value | [N][S] | P0 |
| LOAS-27 | Invalid `approval.policyType` enum value in provided policy proof fails closed and returns ERC-1271 invalid value | [N][S] | P0 |
| LOAS-28 | Cross-organization replay protection (initiator): policy-based initiator signature signed for organization A returns ERC-1271 invalid value on organization B | [S] | P0 |
| LOAS-29 | Cross-organization replay protection (guardian/reviewers): guardian and reviewer signatures signed for organization A return ERC-1271 invalid value on organization B when paired with a valid organization-B initiator signature | [S] | P0 |

---

## 11. Cross-File Fuzz and Invariants

### 11.1 Fuzz Tests

| ID | Test Case | Type | Priority |
|---|---|---|---|
| POL-F-1 | Random policy structs + policy IDs: any single-field mutation invalidates original policy proof | [F][S] | P0 |
| POL-F-2 | Random source account proofs: only correct account/root/proof tuples pass | [F] | P0 |
| POL-F-3 | Random destination proofs across native/ERC20/contract-call shapes validate only exact actual destination | [F][S] | P0 |
| POL-F-4 | Random function selector + constraints payloads: proof valid only for exact `(selector, constraintsHash)` pair | [F][S] | P0 |
| POL-F-5 | Random signature bundles: duplicates/out-of-order signers always revert in approval validation | [F][S] | P0 |
| POL-F-6 | Random rate-limit scopes: observed key-collision behavior matches scope model | [F] | P1 |
| POL-F-7 | Random dynamic bytes/string constraints: out-of-bounds offsets/lengths fail closed | [F][S] | P0 |

### 11.2 Invariants

| ID | Invariant | Priority |
|---|---|---|
| POL-I-1 | Policy root changes only through `setPolicies` | P0 |
| POL-I-2 | Policy leaf and function leaf hashing always use double-hash construction | P0 |
| POL-I-3 | Invalid policy proof can never authorize a transaction/signature | P0 |
| POL-I-4 | For active time window and usage key, usage is monotonic non-decreasing on successful updates | P0 |
| POL-I-5 | Exceeded rate limit never mutates usage | P0 |
| POL-I-6 | Manual-approval policies can never pass with fewer than required valid approvals | P0 |
| POL-I-7 | Unknown enum values for `ApproverType`, `DestinationType`, `ConstraintType`, `ParamType`, `RateLimitType`, and `RateLimitScope` fail closed across policy validation paths | P0 |
| POL-I-8 | **Desired behavior:** `anyInitiator` does not authorize non-members | P0 |
| POL-I-9 | **Desired behavior:** token amount threshold acts as inclusive max (`<=`) | P0 |
| POL-I-10 | **Desired behavior:** malformed constraint payloads fail closed without unexpected reverts in policy-check paths | P0 |
