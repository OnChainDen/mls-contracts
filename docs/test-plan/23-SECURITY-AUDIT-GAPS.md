# 23 — Security Audit Gap Analysis

**Scope:** Additional tests identified through security auditor review of all source files against existing test plan. These tests cover attack vectors, edge cases, and security properties that were missing from the original plan.

**Test File(s):** Distributed across existing test files. Critical gaps are flagged with `[AUDIT]` prefix.

---

## 1. Signature Binding & Replay Attacks

### 1.1 Initiator-Review Signature Binding (`LibOrganizationAccountTransaction.sol`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | [AUDIT] Modifying initiator signature bytes (append/truncate) invalidates all collected review signatures | [S] | P0 |
| 2 | [AUDIT] Two different valid initiator signatures for same tx produce different review hashes | [S] | P0 |
| 3 | [AUDIT] Review signature collected for initiator A cannot validate for initiator B (same tx params) | [S] | P0 |

### 1.2 Approval/Rejection Nonce Isolation (`LibOrganizationAdmin.sol`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 4 | [AUDIT] Approving admin operation consumes nonce — rejection with isApproval=false and same params uses SAME nonce and reverts | [S] | P0 |
| 5 | [AUDIT] Rejecting first, then approving same operation — second call reverts NonceAlreadyUsed | [S] | P0 |

---

## 2. Rate Limit Edge Cases (`LibOrganizationAccountTransaction.sol`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 6 | [AUDIT] Zero-value transaction (usageAmount=0): does not consume rate limit budget | [E] | P0 |
| 7 | [AUDIT] ERC-20 transfer rate limit tracks actual recipient address (from calldata), not token contract address | [S] | P0 |
| 8 | [AUDIT] Rate limit is consumed BEFORE execution — failed execution still consumes budget (CEI pattern) | [S] | P0 |
| 9 | [AUDIT] Multiple zero-value transactions don't artificially inflate rate limit usage | [E] | P0 |
| 10 | [AUDIT] Rate limit with timeIntervalLimit=0: blocks all transactions including zero-value | [E] | P0 |
| 11 | [AUDIT] Rate limit overflow: usageAmount + currentUsage exceeds uint256 max — handled without overflow | [S] | P0 |

---

## 3. Parameter Constraint Overflow & Bounds (`LibPolicyParameterConstraints.sol`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 12 | [AUDIT] Offset near type(uint256).max: addition overflow in dataPosition calculation — returns false | [S] | P0 |
| 13 | [AUDIT] Dynamic bytes length near type(uint256).max: overflow in position+SLOT_SIZE+length — returns false | [S] | P0 |
| 14 | [AUDIT] Address OneOf with empty Merkle proof array — returns false (not true) | [S] | P0 |
| 15 | [AUDIT] Multi-slot parameter (paramCalldataHeadSlotCount=2) advances offset by 64 bytes correctly | [E] | P0 |
| 16 | [AUDIT] Dynamic bytes where claimed length exceeds available calldata — returns false | [E] | P0 |
| 17 | [AUDIT] Constraint with paramCalldataHeadSlotCount=0: returns false (not revert) | [E] | P0 |
| 18 | [AUDIT] Malicious constraint array that references non-existent calldata position | [S] | P0 |

---

## 4. Guardian Module Validation (`LibOrganizationAccountSignature.sol`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 19 | [AUDIT] Guardian is contract that reverts on isModuleEnabled() staticcall — signature validation returns invalid | [E] | P0 |
| 20 | [AUDIT] Guardian contract returns truncated data (<32 bytes) from isModuleEnabled() — handled gracefully | [E] | P0 |
| 21 | [AUDIT] Policy-based signature with only type prefix (0x01, no additional data) — returns invalid (not panic) | [E] | P0 |
| 22 | [AUDIT] Empty sourceAccountProof for policy with specific source accounts — validation fails | [S] | P0 |
| 23 | [AUDIT] Recovery signature path: tx recovery enabled but ERC-1271 recovery also enabled — correct path taken | [S] | P0 |

---

## 5. Admin Authorization Race Conditions (`LibOrganizationAdmin.sol`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 24 | [AUDIT] Admin removed between signature collection and validation — operation fails because signer no longer admin | [S] | P0 |
| 25 | [AUDIT] Voting threshold increased between signature collection and execution — old signatures insufficient | [S] | P0 |
| 26 | [AUDIT] Mixed EOA+ERC-1271 admin signatures: offset accumulation correct for sequence EOA→ERC1271→EOA | [S] | P0 |

---

## 6. Cross-Organization Attacks (`OrganizationAccountTransactionBase.sol`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 27 | [AUDIT] Execute transaction against account deployed by different organization — reverts AccountNotDeployedByOrganization | [S] | P0 |
| 28 | [AUDIT] Nonce consumed before external call — failed execution still marks nonce as used (reentrancy protection) | [S] | P0 |
| 29 | [AUDIT] Event emission timing: AccountTransactionExecuted event emitted even if account execution reverts (verify this is intentional or reverts the whole tx) | [U] | P1 |

---

## 7. Account Implementation (`AccountImplementation.sol`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 30 | [AUDIT] Low-level call that returns false (non-reverting failure) — reverts TransactionExecutionFailed | [U] | P0 |
| 31 | [AUDIT] Low-level call that reverts with data — reverts TransactionExecutionFailed (revert data not propagated) | [U] | P0 |
| 32 | [AUDIT] Low-level call with insufficient gas — reverts TransactionExecutionFailed | [S] | P0 |
| 33 | [AUDIT] Account.receive() cannot re-enter executeTransaction (onlyOrganization prevents it) | [S] | P0 |
| 34 | [AUDIT] isValidSignature passes address(this) correctly to Organization.isValidSignatureForAccount | [U] | P0 |
| 35 | [AUDIT] Self-destruct target: Account executing transaction to selfdestruct target — does not destroy account | [S] | P1 |

---

## 8. Upgrade System (`OrganizationImplementation.sol`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 36 | [AUDIT] Failed upgrade (bad init data) does not leave isUpgradeAuthorized flag stuck true | [S] | P0 |
| 37 | [AUDIT] Direct call to upgradeToAndCall (bypassing upgradeToAndCallWithAuthorization) always reverts UnauthorizedUpgrade | [S] | P0 |
| 38 | [AUDIT] _authorizeUpgrade succeeds regardless of newImplementation parameter value (flag-based, not address-based) | [S] | P1 |
| 39 | [AUDIT] Multiple inheritance override resolution: all base contract functions accessible and correct | [I] | P1 |

---

## 9. Factory Deployment (`OrganizationFactory.sol`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 40 | [AUDIT] Deploy with same salt twice — second deployment reverts | [N] | P1 |
| 41 | [AUDIT] computeOrganizationAddress with different whitelist produces different address than deployed | [U] | P1 |
| 42 | [AUDIT] Deploy with bad init params — entire tx reverts, no uninitialized contract left on-chain | [S] | P0 |
| 43 | [AUDIT] Factory deployer address cannot be changed after construction | [S] | P1 |

---

## 10. Modifier Bypass Scenarios (`OrganizationModifiers.sol`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 44 | [AUDIT] onlyGuardian rejects calls from guardian recovery address | [S] | P0 |
| 45 | [AUDIT] onlyTxRecoveryAddress rejects calls from guardian (different role) | [S] | P0 |
| 46 | [AUDIT] onlyGuardianRecoveryAddress rejects calls from tx recovery address | [S] | P0 |
| 47 | [AUDIT] All modifier enforcement functions revert with correct error for wrong caller | [N] | P0 |

---

## 11. Additional Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 48 | [AUDIT-INV] **No orphaned admins**: Removing a member who is an admin always reverts (can never leave admin without member status) | P0 |
| 49 | [AUDIT-INV] **Rate limit atomicity**: Rate limit usage is either fully updated or not at all (no partial updates) | P0 |
| 50 | [AUDIT-INV] **Signature non-transferability**: A signature valid for one Organization is never valid for another Organization (even with same admin set) | P0 |
| 51 | [AUDIT-INV] **Recovery path isolation**: Guardian recovery operations never modify tx recovery state, and vice versa | P0 |
| 52 | [AUDIT-INV] **Account beacon immutability**: An Account's beacon (Organization) address cannot be changed after deployment | P0 |
| 53 | [AUDIT-INV] **Group deletion permanence**: Once wasGroupDeleted is true for a groupId, it can never become false | P0 |

---

## 12. Additional Fuzz Tests

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 54 | [AUDIT-FUZZ] Random parameter constraint offsets: bounds checking never overflows | 10000 | P0 |
| 55 | [AUDIT-FUZZ] Random dynamic bytes lengths: constraint validation always terminates | 10000 | P0 |
| 56 | [AUDIT-FUZZ] Random ERC-20 calldata: getActualDestination never panics | 10000 | P0 |
| 57 | [AUDIT-FUZZ] Random signature type prefixes (0x00-0xff): only 0x00 and 0x01 return magic value | 1000 | P0 |
| 58 | [AUDIT-FUZZ] Random guardian addresses (EOA/contract/zero): module validation always returns valid result | 1000 | P0 |
| 59 | [AUDIT-FUZZ] Random admin arrays: modifyAdmins never leaves adminCount=0 | 1000 | P0 |
| 60 | [AUDIT-FUZZ] Random rate limit configs: checkAndUpdateRateLimit never overflows | 10000 | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Signature binding & replay | 5 | P0 |
| Rate limit edge cases | 6 | P0 |
| Parameter constraint overflow | 7 | P0 |
| Guardian module validation | 5 | P0 |
| Admin auth race conditions | 3 | P0 |
| Cross-org attacks | 3 | P0 |
| Account implementation | 6 | P0-P1 |
| Upgrade system | 4 | P0-P1 |
| Factory deployment | 4 | P0-P1 |
| Modifier bypass | 4 | P0 |
| Additional invariants | 6 | P0 |
| Additional fuzz tests | 7 | P0 |
| **Total** | **60** | |
