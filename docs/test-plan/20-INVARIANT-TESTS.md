# 20 — Invariant Tests Plan

**Scope:** System-wide properties that must hold across arbitrary sequences of valid and invalid operations.

**Out of Scope (covered elsewhere):**
- Interface files (`src/interfaces/**`)
- Storage library files (`src/**/libraries/storage/**`)

---

## Invariant Harness Prerequisite (Private Functions)

For this plan, private helper functions are explicitly in scope. In the test branch, change targeted helpers from `private` to `internal` and expose them through harness contracts for direct assertions (and include any newly introduced private helpers in scope during refactors).

Helpers to expose include:
- `LibOrganizationAdmin`: `_areAdminSignaturesValid`, `_getAdminOperationHash`
- `LibOrganizationGroups`: `_createGroup`, `_updateGroup`, `_deleteGroup`, `_addGroupMembers`, `_removeGroupMembers`
- `LibOrganizationAccountTransaction`: `_validateAndUpdateRateLimitOrRevert`, `_validateAutoApproveRejectionOrRevert`, `_validateManualConfirmationOrRevert`, `_computeInitiatorHashFromParams`, `_computeReviewHashFromParams`
- `LibOrganizationAccountSignature`: `_validateRecoverySignature`, `_validatePolicyBasedSignature`, `_isValidGuardianSignature`, `_isERC1271SignatureAllowedByPolicy`, `_getInitiatorSignatureHash`, `_getReviewSignatureHash`
- `LibOrganizationPolicy`: `_computePolicyLeaf`
- `LibPolicyApproval`: `_isSignerAuthorizedForPolicy`
- `LibPolicyContractInteraction`: `_isFunctionAllowedByPolicy`, `_computeFunctionLeaf`
- `LibPolicyParameterConstraints`: `_processConstraints`, `_isParameterAllowedByConstraint`, and type-specific validators
- `LibOrganizationGuardianRecovery`: `_clearPendingGuardianRecoveryInitTimelock`, `_validateGuardianRecoveryNotConfiguredOrRevert`, `_validateGuardianRecoveryParamsOrRevert`
- `LibOrganizationTxRecovery`: `_clearPendingTxRecoveryInitTimelock`, `_validateTxRecoveryNotConfiguredOrRevert`, `_validateTxRecoveryParamsOrRevert`
- `ImplementationWhitelistImplementation`: `_addToWhitelist`, `_removeFromWhitelist`
- `AccountImplementation`: `_execute`, `_onlyOrganization`
- `SignatureUtils`: `_getVByte`, `_getContractSigner`, `_getContractSignatureLength`, `_extractContractInnerSignature`, `_tryRecoverEOASigner`, `_tryRecoverContractSigner`
- `BytesUtils`: (all functions already `internal`; expose via harness for direct fuzz assertions)

---

## Handler Design

Use stateful handlers plus a shadow-state tracker (for non-enumerable mappings like admins/members/groups/accounts).

| Handler | Purpose | Core Calls |
|---|---|---|
| `AdminStateHandler` | Mutate org/admin/member/group/policy/upgrade state | `modifyAdmins`, `modifyMembers`, `modifyGroups`, `setPolicies`, `setAccountImplementation`, `upgradeToAndCallWithAuthorization` |
| `TxHandler` | Exercise transaction execution/rejection and nonce/rate-limit paths | `executeAccountTransaction`, `rejectAccountTransaction` |
| `GuardianHandler` | Exercise normal guardian flow | `initiateGuardianUpdate`, `finalizeGuardianUpdate`, `cancelGuardianUpdate`, `acceptGuardian` |
| `RecoveryHandler` | Exercise guardian/tx recovery and deferred recovery init flows | recovery entrypoints in `OrganizationGuardianRecoveryBase` and `OrganizationTxRecoveryBase` |
| `SignatureHandler` | Exercise ERC-1271 paths and guardian-module integration | `Account.isValidSignature`, `Organization.isValidSignatureForAccount` |
| `AttackerHandler` | Repeated unauthorized calls to enforce access-control invariants | All privileged entrypoints with wrong caller roles |
| `TimeHandler` | Warp timestamps for timelock and rate-limit windows | `vm.warp` across pending/finalization boundaries |

---

## File 1: `src/organization/libraries/LibOrganizationSignatures.sol` / `src/organization/base/OrganizationSignaturesBase.sol`

Functions: `validateAndConsumeNonceOrRevert`, `isNonceUsed`, `computeNonce`

| ID | Invariant | Priority |
|---|-----------|----------|
| NMSIG-INV-1 | **Nonce monotonicity:** once `isNonceUsed(nonce)` becomes `true`, it never becomes `false` | P0 |
| NMSIG-INV-2 | **No double consume:** any nonce consumed once cannot be consumed by any entrypoint again | P0 |
| NMSIG-INV-3 | **Deterministic nonce computation:** same `(operationType, operationData, salt, organization)` always yields same nonce | P0 |
| NMSIG-INV-4 | **OperationType isolation:** same `operationData` and `salt` with different `operationType` values must produce different nonces | P0 |
| NMSIG-INV-5 | **Cross-org isolation:** same inputs on different Organization addresses must produce different nonces | P0 |
| NMSIG-INV-6 | **Rollback safety:** if a call reverts after nonce consume in the same transaction, nonce state does not persist | P0 |

---

## File 2: `src/organization/libraries/LibOrganizationAdmin.sol` / `src/organization/base/OrganizationAdminBase.sol` / `src/organization/libraries/LibOrganizationMembers.sol` / `src/organization/base/OrganizationMembersBase.sol`

Functions: `validateAdminAuthAndConsumeNonceOrRevert`, `_areAdminSignaturesValid`, `_getAdminOperationHash`, `modifyAdmins`, `modifyMembers`

| ID | Invariant | Priority |
|---|-----------|----------|
| ADMIN-INV-1 | **Admin subset of members:** every admin is always a member (`isAdmin(a) => isMember(a)`) | P0 |
| ADMIN-INV-2 | **Minimum admins:** `adminCount >= 1` always holds after initialization | P0 |
| ADMIN-INV-3 | **Threshold bounds:** `1 <= votingThreshold <= adminCount` at all times | P0 |
| ADMIN-INV-4 | **Admin count consistency:** tracked admin-set cardinality equals `adminCount()` | P0 |
| ADMIN-INV-5 | **No orphaned admins:** removing a member who is currently an admin always fails | P0 |
| ADMIN-INV-6 | **Signer uniqueness/order:** admin signature streams must be strictly increasing and duplicate-free | P0 |
| ADMIN-INV-7 | **Fail-closed auth:** expired/invalid admin auth never mutates privileged state and never burns nonce | P0 |
| ADMIN-INV-8 | **Approval/rejection separation:** admin signatures with `isApproval=true` never validate as rejection auth and vice versa | P0 |
| ADMIN-INV-9 | **State-at-execution auth:** signatures collected before admin set/threshold changes must fail if they no longer satisfy current state | P0 |

---

## File 3: `src/organization/libraries/LibOrganizationGroups.sol`

Functions: `modifyGroups`, `_createGroup`, `_updateGroup`, `_deleteGroup`, `_addGroupMembers`, `_removeGroupMembers`

| ID | Invariant | Priority |
|---|-----------|----------|
| GROUP-INV-1 | **Deletion permanence:** once `wasGroupDeleted[groupId]` is `true`, it never returns to `false` | P0 |
| GROUP-INV-2 | **No group-ID reuse:** deleted group IDs can never be recreated as active groups | P0 |
| GROUP-INV-3 | **Group existence gate:** group-based initiator/approver authorization cannot succeed if `isGroup(groupId) == false` | P0 |
| GROUP-INV-4 | **No ghost authorization:** stale `isGroupMember` entries for deleted groups never grant policy authorization | P0 |
| GROUP-INV-5 | **Zero-address exclusion:** `address(0)` cannot become a group member | P0 |
| GROUP-INV-6 | **Isolation:** group mutations never directly alter admin/member counters or thresholds | P1 |
| GROUP-INV-7 | **Desired behavior (docs): member-only groups:** addresses added to groups must be current Organization members | P0 |
| GROUP-INV-8 | **Desired behavior (docs): no effective stale group membership:** once an address is no longer a member, it cannot remain effectively authorized via any group path | P1 |

---

## File 4: `src/organization/base/OrganizationPolicyBase.sol` / `src/organization/libraries/LibOrganizationPolicy.sol` / `src/organization/libraries/policy/*.sol`

Functions: `setPolicies`, `isPolicyInOrg`, `isTransactionAllowedByPolicy`, `isSourceAccountAllowedByPolicy`, `areApprovalsValid`, `isInitiatorAuthorized`

| ID | Invariant | Priority |
|---|-----------|----------|
| POL-INV-1 | **Policy root write-gate:** `policiesRoot` changes only through `setPolicies` | P0 |
| POL-INV-2 | **Merkle existence gate:** invalid policy proof can never authorize tx/signature flows | P0 |
| POL-INV-3 | **Source-account enforcement:** when `anySourceAccount=false`, only proven accounts are valid | P0 |
| POL-INV-4 | **Tx-type separation (tx path):** `TransactionType.Signatures` policies never authorize `execute/rejectAccountTransaction` | P0 |
| POL-INV-5 | **Tx-type separation (signature path):** non-`TransactionType.Signatures` policies never authorize ERC-1271 approval path | P0 |
| POL-INV-6 | **Approval semantics:** member approver always requires exactly one authorized signer; group approver enforces configured threshold | P0 |
| POL-INV-7 | **Desired behavior:** `anyInitiator=true` should still require initiator to be an Organization member (per docs) | P0 |
| POL-INV-8 | **Desired behavior fail-closed:** malformed proofs/constraints payloads never authorize an operation | P0 |
| POL-INV-9 | **(token threshold semantics):** token amount thresholds are exclusive (`amount < threshold`) | P0 |
| POL-INV-10 | **Function-filter helper correctness:** `_isFunctionAllowedByPolicy` enforces selector/proof checks when `anyFunction=false` and rejects calldata shorter than 4 bytes | P0 |
| POL-INV-11 | **Constraint calldata walking:** `_processConstraints` reads each parameter at the correct calldata offset `4 + Σ(headSlotCount × 32)` for all preceding params. Fuzz N constraints with varying `paramCalldataHeadSlotCount` and matching calldata; assert the i-th constraint validates against the correct slot | P0 |
| POL-INV-12 | **Short-calldata constraint rejection:** `areParametersAllowedByConstraints` returns `false` (no revert) when calldata is too short for any declared parameter head. Fuzz valid constraints, truncate calldata before the last parameter | P0 |
| POL-INV-13 | **Dynamic type offset resolution:** for `Bytes`/`String` constraints, the ABI offset in the parameter head correctly locates the dynamic data. Fuzz calldata with dynamic types at various offsets and an Exact hash constraint; assert `true` for correct offset, `false` for corrupted offset | P0 |
| POL-INV-14 | **ComparisonData length gating:** every type-specific validator (`Bool`, `Uint`, `Int`, `Address`, `FixedBytes`, `BytesOrString`) returns `false` when `comparisonData` has wrong byte length (e.g., ≠ 32 for Exact, ≠ 64 for Range). Fuzz each `ParamType` with wrong-length `comparisonData` | P0 |
| POL-INV-15 | **Undersized constraint payload rejection:** `areParametersAllowedByConstraints` returns `false` (no revert) for any `parameterConstraints` payload shorter than 64 bytes (minimum ABI-encoded empty array) | P0 |

---

## File 5: `src/organization/libraries/policy/LibPolicyRateLimits.sol` / `src/organization/libraries/LibOrganizationAccountTransaction.sol` / `src/organization/base/OrganizationAccountTransactionBase.sol`

Functions: `checkAndUpdateRateLimit`, `computeTimeWindow`, `computeUsageKey`, `_validateAndUpdateRateLimitOrRevert`, `executeAccountTransaction`, `rejectAccountTransaction`

| ID | Invariant | Priority |
|---|-----------|----------|
| TXRL-INV-1 | **Window monotonicity:** usage is non-decreasing inside a fixed time window | P0 |
| TXRL-INV-2 | **Window reset:** usage in a new time window starts from a clean slot | P0 |
| TXRL-INV-3 | **Scope correctness:** `AcrossAll` shares usage; `PerEntity` isolates by scoped entity | P0 |
| TXRL-INV-4 | **Rejection does not consume budget:** `rejectAccountTransaction` never updates rate-limit usage | P0 |
| TXRL-INV-5 | **Single-update on success:** successful execution updates usage exactly once | P0 |
| TXRL-INV-6 | **Atomic rollback:** reverted execution path leaves no persisted rate-limit updates | P0 |
| TXRL-INV-7 | **Update atomicity:** usage either increases by exact `usageAmount` or remains unchanged | P0 |
| TXRL-INV-8 | **Desired behavior:** `currentUsage + usageAmount` overflow fails closed without wrap/panic behavior leaks | P0 |
| TXRL-INV-9 | **Policy-ID isolation:** rate-limit usage counters are isolated per `policyId` even when all scoped entities match | P0 |
| TXRL-INV-10 | **No-op when disabled:** non-`TimeInterval` limits (or `timeIntervalHours=0`) never write usage state | P1 |
| TXRL-INV-11 | **Destination-scope correctness:** token-transfer destination scoping uses actual recipient address, not token contract address | P0 |
| TXRL-INV-12 | **No org reentrancy via execution:** account transactions executed via `executeAccountTransaction` cannot re-enter and call privileged external functions on `OrganizationImplementation` | P0 |

---

## File 6: `src/organization/libraries/LibOrganizationGuardian.sol` / `src/organization/base/OrganizationGuardianBase.sol`

Functions: `initializeGuardian`, `initiateGuardianUpdate`, `finalizeGuardianUpdate`, `cancelGuardianUpdate`, `acceptGuardian`, `enforceOnlyGuardian`, `enforceOnlyPendingGuardian`

| ID | Invariant | Priority |
|---|-----------|----------|
| GUARD-INV-1 | **Guardian set:** guardian is never `address(0)` after initialization | P0 |
| GUARD-INV-2 | **Single pending update:** at most one normal pending guardian update exists | P0 |
| GUARD-INV-3 | **Pending-state consistency:** if no pending guardian, timestamp is `0` and ready flag is `false` | P0 |
| GUARD-INV-4 | **State machine enforcement:** accept cannot succeed before finalize/timelock completion | P0 |
| GUARD-INV-5 | **Accept clears pending:** acceptance always clears pending guardian, timestamp, and ready flag | P0 |
| GUARD-INV-6 | **Role enforcement:** only guardian can initiate/finalize/cancel normal updates | P0 |
| GUARD-INV-7 | **Role enforcement:** only pending guardian can call `acceptGuardian` | P0 |
| GUARD-INV-8 | **Cancel clears pending:** `cancelGuardianUpdate` always clears pending guardian, timestamp, and ready flag | P0 |

---

## File 7: `src/organization/libraries/LibOrganizationGuardianRecovery.sol` / `src/organization/base/OrganizationGuardianRecoveryBase.sol`

Functions: recovery update lifecycle, deferred recovery init lifecycle, access-control helpers

| ID | Invariant | Priority |
|---|-----------|----------|
| GREC-INV-1 | **Flow isolation:** guardian-recovery pending fields never overwrite normal guardian pending fields | P0 |
| GREC-INV-2 | **Config immutability:** `guardianRecovery.recoveryAddress` and `timelockDurationSeconds` are write-once after setup | P0 |
| GREC-INV-3 | **Deferred-init consistency:** if pending init timestamp is `0`, pending init address and timelock are zeroed | P0 |
| GREC-INV-4 | **Timelocked state machine:** recovery guardian change requires initiate -> timelock expiry -> finalize -> accept | P0 |
| GREC-INV-5 | **Write target correctness:** `acceptGuardianRecovery` updates normal guardian storage and clears recovery pending state | P0 |
| GREC-INV-6 | **Role enforcement:** only `guardianRecoveryAddress` can initiate/finalize/cancel recovery updates | P0 |
| GREC-INV-7 | **Role enforcement:** only recovery pending guardian can accept recovery update | P0 |
| GREC-INV-8 | **Subsystem isolation:** guardian-recovery operations never mutate tx-recovery state | P0 |
| GREC-INV-9 | **Recovery-cancel clears pending:** `cancelRecoveryGuardianUpdate` always clears recovery pending guardian, timestamp, and ready flag | P0 |
| GREC-INV-10 | **Recovery timelock source correctness:** recovery-update pending timestamp is derived from `guardianRecovery.timelockDurationSeconds` | P0 |
| GREC-INV-11 | **Param validation gate:** guardian-recovery setup rejects zero recovery address and out-of-range timelock durations | P0 |

---

## File 8: `src/organization/libraries/LibOrganizationTxRecovery.sol` / `src/organization/base/OrganizationTxRecoveryBase.sol`

Functions: enable/disable tx recovery lifecycle, deferred tx-recovery init lifecycle, recovery execution/signature helpers

| ID | Invariant | Priority |
|---|-----------|----------|
| TXRC-INV-1 | **Config immutability:** tx-recovery config is write-once after setup | P0 |
| TXRC-INV-2 | **Timelocked enablement:** enabling recovery always requires initiate -> timelock expiry -> finalize | P0 |
| TXRC-INV-3 | **Immediate disable:** `disableTransactionAndERC1271Recovery` always disables immediately and clears pending enable | P0 |
| TXRC-INV-4 | **Role enforcement:** only tx-recovery address can invoke tx-recovery state-changing entrypoints | P0 |
| TXRC-INV-5 | **Execution gate:** recovery account tx execution succeeds only when configured and enabled | P0 |
| TXRC-INV-6 | **Recovery execution constants:** recovery account calls always use `nonce=0` and `policyId=0` | P0 |
| TXRC-INV-7 | **Subsystem isolation:** tx-recovery operations never mutate guardian-recovery state | P0 |
| TXRC-INV-8 | **Nonce-space isolation:** recovery account execution does not consume Organization nonce mapping | P0 |
| TXRC-INV-9 | **Signature helper separation:** `isValidRecoverySignature` result is independent of enabled/disabled flag | P1 |
| TXRC-INV-10 | **Deferred-init consistency:** if tx-recovery pending init timestamp is `0`, pending init address and timelock are zeroed | P0 |
| TXRC-INV-11 | **Param validation gate:** tx-recovery setup rejects zero recovery address and out-of-range timelock durations | P0 |

---

## File 9: `src/organization/libraries/LibOrganizationAccountFactory.sol` / `src/organization/base/OrganizationAccountFactoryBase.sol` / `src/organization/OrganizationFactory.sol` / `src/organization/OrganizationProxy.sol`

Functions: `deployAccount`, `computeAccountAddress`, `validateIsAccountDeployedByOrgOrRevert`, organization deployment path

| ID | Invariant | Priority |
|---|-----------|----------|
| ACCF-INV-1 | **Deterministic compute:** `computeAccountAddress` is deterministic for same inputs | P1 |
| ACCF-INV-2 | **Compute/deploy match:** deployed account address always equals computed address | P0 |
| ACCF-INV-3 | **Deployment tracking monotonicity:** `deployedAccounts[account]` flips `false -> true` only once and never back | P0 |
| ACCF-INV-4 | **Cross-org account isolation:** org cannot validate or execute through accounts deployed by a different org | P0 |
| ACCF-INV-5 | **Shared beacon pointer:** all accounts under one org resolve the same current account implementation | P0 |
| ACCF-INV-6 | **Upgrade independence:** account implementation updates do not change Organization proxy implementation pointer | P0 |
| ACCF-INV-7 | **Deployment atomicity:** failed organization initialization leaves no live partially initialized org | P0 |
| ACCF-INV-8 | **Desired behavior:** proxy-stored whitelist address remains immutable for upgrade checks | P1 |
| ACCF-INV-9 | **Factory deployer gate:** only `DEPLOYER_ADDRESS` can call `OrganizationFactory.deployOrganization` | P0 |
| ACCF-INV-10 | **Factory whitelist gate:** organization deployment succeeds only for whitelisted `ContractType.Organization` implementations | P0 |
| ACCF-INV-11 | **No duplicate account CREATE2 deployments:** reusing `(organization, salt)` never yields a second deployed account | P0 |

---

## File 10: `src/account/AccountImplementation.sol`

Functions: `executeTransaction`, `getOrganizationAddress`, `isValidSignature`, `_execute`, `_onlyOrganization`

| ID | Invariant | Priority |
|---|-----------|----------|
| AI-INV-1 | **Only-org execution:** only bound Organization can execute account transactions | P0 |
| AI-INV-2 | **Org binding immutability:** `getOrganizationAddress()` stays constant for account lifetime | P0 |
| AI-INV-3 | **Delegation correctness:** `isValidSignature` always queries Organization with `account = address(this)` | P0 |
| AI-INV-4 | **Fail-closed execution:** failed low-level call always reverts `TransactionExecutionFailed` | P0 |
| AI-INV-5 | **No reentrancy privilege escalation:** account cannot self-authorize `onlyOrganization` paths | P0 |

---

## File 11: `src/organization/base/OrganizationAccountSignatureBase.sol` / `src/organization/libraries/LibOrganizationAccountSignature.sol` / `src/safe-module/SafeExecutorModule.sol` / `src/safe-module/BatchedTransaction.sol`

Functions: signature routing and validation, Safe module execution, batched execution

| ID | Invariant | Priority |
|---|-----------|----------|
| ASIG-INV-1 | **Signature type routing:** only `0x00` (recovery) and `0x01` (policy) can produce ERC-1271 magic value | P0 |
| ASIG-INV-2 | **Recovery signature gate:** `0x00` path is valid iff tx recovery is enabled and signer is configured recovery address | P0 |
| ASIG-INV-3 | **Policy signature gate:** `0x01` path requires unexpired initiator sig, valid guardian/module sig, and applicable policy | P0 |
| ASIG-INV-4 | **Policy-type approval behavior:** manual approval requires reviewer threshold; auto-approve does not | P0 |
| ASIG-INV-5 | **Guardian signer set:** guardian signature is valid iff signer is guardian or enabled guardian module | P0 |
| ASIG-INV-6 | **Module rotation immediacy:** enabling/disabling modules updates valid signer set immediately, with no org-state migration | P0 |
| ASIG-INV-7 | **Safe-call block:** `SafeExecutorModule.executeOnBehalf` never succeeds with `to == SAFE` | P0 |
| ASIG-INV-8 | **No ETH forwarding:** `SafeExecutorModule` always forwards `value = 0` | P0 |
| ASIG-INV-9 | **Batched atomicity and safe-call block:** batched execution never allows subcall to delegatecaller `address(this)` and fully reverts on any subcall failure | P0 |
| ASIG-INV-10 | **Desired behavior fail-closed parsing:** malformed policy-signature payloads never authorize execution | P0 |
| ASIG-INV-11 | **Account-caller binding:** `isValidSignatureForAccount` only succeeds when `msg.sender == account` and `account` is org-deployed | P0 |
| ASIG-INV-12 | **Safe executor caller gate:** `executeOnBehalf` succeeds only when caller is `AUTHORIZED_EXECUTOR` | P0 |
| ASIG-INV-13 | **Desired behavior (ERC-1271 compatibility):** malformed policy-signature payloads return invalid magic value (`0xffffffff`) instead of reverting | P1 |
| ASIG-INV-14 | **Batch field decoding:** each sub-tx in `BatchedTransaction.execute` calls the correct `to` with the correct `data`. Fuzz: pack N sub-txs as `[to(20)][dataLength(8)][data(N)]`, execute via delegatecall; verify each mock target received exactly its expected calldata | P0 |
| ASIG-INV-15 | **Batch offset walking:** a well-formed batch executes every sub-tx — none skipped, none repeated. Fuzz: pack N sub-txs targeting counter contracts; assert all N counters incremented exactly once | P0 |

---

## File 12: `src/organization/OrganizationImplementation.sol` / `src/organization/base/OrganizationAccountFactoryBase.sol` / `src/implementation-whitelist/ImplementationWhitelistImplementation.sol`

Functions: upgrade/whitelist control paths

| ID | Invariant | Priority |
|---|-----------|----------|
| UPG-CTRL-1 | **Upgrade auth flag safety:** `isUpgradeAuthorized` is `false` outside authorized upgrade execution | P0 |
| UPG-CTRL-2 | **Direct UUPS path blocked:** direct inherited `upgradeToAndCall` calls are never authorized | P0 |
| UPG-CTRL-3 | **Org upgrade whitelist gate:** organization upgrades activate only whitelisted `ContractType.Organization` targets | P0 |
| UPG-CTRL-4 | **Account upgrade whitelist gate:** account implementation updates activate only whitelisted `ContractType.Account` targets | P0 |
| UPG-CTRL-5 | **Whitelist owner exclusivity:** only current whitelist owner mutates whitelist entries | P0 |
| UPG-CTRL-6 | **Whitelist type independence:** account and organization whitelist maps never cross-enable each other | P0 |
| UPG-CTRL-7 | **Desired behavior:** org upgrade admin auth should bind both `newImplementation` and migration `data` payload | P0 |
| UPG-CTRL-9 | **Upgrade rollback safety:** failed org upgrade/migration leaves pre-upgrade implementation active and `isUpgradeAuthorized == false` | P0 |
| UPG-CTRL-10 | **Whitelist UUPS owner gate:** direct whitelist upgrades are authorized only by the current whitelist owner | P0 |

---

## File 13: `src/organization/libraries/LibOrganizationEIP712.sol` + private hash helpers in admin/tx/signature libraries

Functions: `getDomainSeparator`, `computeTypedDataHash`, `_getAdminOperationHash`, `_computeInitiatorHashFromParams`, `_computeReviewHashFromParams`, `_getInitiatorSignatureHash`, `_getReviewSignatureHash`

| ID | Invariant | Priority |
|---|-----------|----------|
| E712-HASH-1 | **Domain determinism:** same `(chainId, organization)` always yields same domain separator | P0 |
| E712-HASH-2 | **Domain separation:** changing `chainId` or `organization` changes domain separator | P0 |
| E712-HASH-3 | **Approval/rejection hash separation:** toggling `isApproval` changes admin/tx hash domains | P0 |
| E712-HASH-4 | **Initiator-signature binding:** review hashes are bound to `keccak256(initiatorSignature)` | P0 |
| E712-HASH-5 | **Cross-chain replay protection:** valid signatures on one chain never validate on another chain | P0 |
| E712-HASH-6 | **Cross-org replay protection:** valid signatures for one org never validate for another org | P0 |
| E712-HASH-7 | **Field-level hash binding:** changing any signed field (`expirationTimestamp`, `policyId`, `account`, `operationData/data`) changes the corresponding typed-data hash | P0 |

---

## File 14: `src/organization/libraries/LibOrganizationInitialization.sol` / `src/organization/base/OrganizationInitializationBase.sol` / `src/organization/common/OrganizationModifiers.sol`

Functions: `initialize`, `isInitialized`, modifier-enforced role boundaries

| ID | Invariant | Priority |
|---|-----------|----------|
| INIT-STATE-1 | **Initialization permanence:** `isInitialized` is monotonic (`false -> true` only) | P0 |
| INIT-STATE-2 | **Member-before-admin invariant:** first initialized state and all subsequent states preserve admin-as-member relation | P0 |
| INIT-STATE-3 | **Deployer gate:** `initialize` is callable only by the configured deployer | P0 |
| INIT-STATE-4 | **Role-boundary isolation:** guardian, tx-recovery, and guardian-recovery role checks remain disjoint by function set | P0 |
| INIT-STATE-5 | **No recovery-role privilege bleed:** recovery privileged roles cannot call guardian-only entrypoints unless also guardian | P0 |
| INIT-STATE-6 | **Desired behavior atomicity:** deployment/init and deferred-recovery finalization paths never leave partial committed state on revert | P0 |
| INIT-STATE-7 | **Timelock bound enforcement:** all timelock params accepted in init/deferred-init paths satisfy `TimelockUtils` min/max bounds | P0 |

---

## File 15: `src/libraries/BytesUtils.sol` / `src/libraries/SignatureUtils.sol` / `src/libraries/TokenTransferUtils.sol` / `src/libraries/ContractInteractionUtils.sol`

Functions: `sliceFrom`, `sliceRange`, `tryRecoverSignerAtOffset`, `_getVByte`, `_getContractSigner`, `_getContractSignatureLength`, `_extractContractInnerSignature`, `_tryRecoverEOASigner`, `extractFunctionSelector`, `extractERC20TransferRecipient`, `extractTransferAmount`, `isTransactionERC20TokenTransfer`

These are pure-function libraries with no storage — test via a harness contract that exposes each function and fuzz the inputs directly (no stateful handlers needed).

### BytesUtils

| ID | Invariant | Priority |
|---|-----------|----------|
| BYTE-SLICE-1 | **Slice content fidelity:** `sliceFrom(buf, i)[j] == buf[i + j]` and `sliceRange(buf, i, len)[j] == buf[i + j]` for all valid `j`. Fuzz random buffer with random valid `i`/`len`; compare output byte-by-byte against the source | P0 |
| BYTE-SLICE-2 | **Slice OOB returns empty:** `sliceFrom` with `startIndex >= buf.length` returns `bytes("")`; `sliceRange` with `startIndex + length > buf.length` returns `bytes("")`. Neither reverts | P0 |
| BYTE-SLICE-3 | **Slice output length:** `sliceFrom(buf, i).length == buf.length - i`; `sliceRange(buf, i, len).length == len` (when in-range) | P0 |
| BYTE-SLICE-4 | **Slice trailing-byte isolation:** when `len % 32 != 0`, the last word of `sliceRange` output is zero-padded — no garbage bytes leak from adjacent source memory. Fuzz random buffer and non-aligned length; assert trailing bytes are zero | P0 |

### SignatureUtils

| ID | Invariant | Priority |
|---|-----------|----------|
| SIGU-PARSE-1 | **EOA (v, r, s) extraction:** given a known 65-byte EOA sig placed at a fuzzed offset, `_getVByte` returns `sig[offset]`, and `_tryRecoverEOASigner` reads `r` from `[offset+1:+33]` and `s` from `[offset+33:+65]`. Fuzz: craft known `(v,r,s)`, embed at random offset in a larger buffer; assert extracted values match | P0 |
| SIGU-PARSE-2 | **Contract sig field extraction:** `_getContractSigner` returns the address at `[offset+1:+21]`, `_getContractSignatureLength` returns the uint16 at `[offset+21:+23]`, `_extractContractInnerSignature` returns the bytes at `[offset+23:+23+len]`. Fuzz: encode a contract sig with known signer/length/inner bytes, embed at random offset; assert all three fields match | P0 |
| SIGU-PARSE-3 | **Signature nextOffset correctness:** `tryRecoverSignerAtOffset` returns `nextOffset == offset + 65` for EOA sigs and `nextOffset == offset + 23 + sigLength` for contract sigs | P0 |
| SIGU-PARSE-4 | **Multi-sig iteration completeness:** concatenate N known sigs (mix of EOA and contract), iterate with `recoverSignerAtOffsetOrRevert` from offset 0; assert final `nextOffset == sigs.length` and all N signers are recovered in order | P0 |
| SIGU-PARSE-5 | **Signature OOB returns failure:** when `offset + headerSize > signatures.length`, `tryRecoverSignerAtOffset` returns `(false, address(0), 0)` — no panic, no garbage read | P0 |

### TokenTransferUtils / ContractInteractionUtils

| ID | Invariant | Priority |
|---|-----------|----------|
| TXUT-PARSE-1 | **ERC-20 recipient parsing:** `extractERC20TransferRecipient` returns the same address as `abi.decode(data[4:], (address, uint256))` for the first param. Fuzz: encode `transfer(address,uint256)` with a known recipient; assert match | P0 |
| TXUT-PARSE-2 | **ERC-20 amount parsing:** `extractTransferAmount` returns the same uint256 as `abi.decode(data[4:], (address, uint256))` for the second param. Fuzz: encode `transfer(address,uint256)` with a known amount; assert match | P0 |
| TXUT-PARSE-3 | **Token transfer short-calldata reverts:** `extractERC20TransferRecipient` reverts `MalformedTokenTransfer` for `data.length < 36`; `extractTransferAmount` reverts for `data.length < 68`; `isTransactionERC20TokenTransfer` returns `false` for `data.length < 68` | P0 |
| TXUT-PARSE-4 | **Selector extraction:** `extractFunctionSelector(data) == bytes4(data[:4])` for any `data.length >= 4` | P1 |

---

## Summary

| Category | Invariants | Priority Focus |
|----------|------------|----------------|
| Nonce and replay properties | 6 | P0 |
| Admin/member/group consistency | 17 | P0-P1 |
| Policy and rate-limit correctness | 27 | P0 |
| Guardian and recovery state machines | 30 | P0 |
| Account factory/account behavior | 16 | P0-P1 |
| Signature and guardian-module security | 16 | P0-P1 |
| Upgrade and whitelist controls | 10 | P0 |
| EIP-712 separation properties | 7 | P0 |
| Initialization and role boundaries | 7 | P0 |
| Bytes parsing and extraction primitives | 13 | P0-P1 |
| **Total** | **149** | |
