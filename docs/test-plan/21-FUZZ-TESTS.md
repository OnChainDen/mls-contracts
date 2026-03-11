# 21 — Fuzz & Property-Based Test Plan (File/Function Breakdown)

## Scope
Property-based testing for custom contract behavior across `src/`, broken down by concrete file and function.

## Exclusions
- Interface files in `src/interfaces/**` are out of scope for this plan.
- Storage libraries in `src/**/libraries/storage/**` are out of scope for this plan.

## Private Function Harness Note
Several cases below target functions currently marked `private`. For implementation, expose these through test harnesses by changing visibility `private -> internal` in test-only builds. This applies to all currently-private helpers in scope for this plan (not only the ones explicitly called out in row text).

## Run Baseline
- `P0`: `10000` runs minimum
- `P1`: `2000` runs minimum
- `P2`: `1000` runs minimum

## Matrix
| ID | File | Function(s) | Fuzz / Property Case (Desired Behavior) | Min Runs | Priority |
|---|---|---|---|---|---|
| FSU-TRS-1 | `src/libraries/SignatureUtils.sol` | `tryRecoverSigner`, `recoverSignerOrRevert` | Valid EOA and ERC-1271 signatures recover expected signer | 10000 | P0 |
| FSU-TRS-2 | `src/libraries/SignatureUtils.sol` | `tryRecoverSigner`, `recoverSignerOrRevert` | Invalid `v` / malformed length / truncated bytes fail (`false` or `SignatureRecoveryFailed`) | 10000 | P0 |
| FSU-EOA-3 | `src/libraries/SignatureUtils.sol` | `_tryRecoverEOASigner` | High-`s` malleable signatures are always rejected | 10000 | P0 |
| FSU-TRSO-4 | `src/libraries/SignatureUtils.sol` | `tryRecoverSigner`, `tryRecoverSignerAtOffset` | Signature for hash `A` never validates for hash `B` | 10000 | P0 |
| FSU-ATOFF-5 | `src/libraries/SignatureUtils.sol` | `tryRecoverSignerAtOffset` | Mixed packed signatures (EOA + ERC-1271) produce strictly increasing offsets ending at `signatures.length` | 10000 | P0 |
| FSU-ERC1271-6 | `src/libraries/SignatureUtils.sol` | `_tryRecoverContractSigner`, `_isValidERC1271SignatureNow` | Revert/empty/short/non-magic ERC-1271 responses always fail recovery | 10000 | P0 |
| FSU-HAR-7 | `src/libraries/SignatureUtils.sol` | private helpers via harness | `_getVByte`, `_getContractSigner`, `_getContractSignatureLength`, `_extractContractInnerSignature` parse correctly with random offsets/lengths | 2000 | P1 |
| FSU-WRAP-8 | `src/libraries/SignatureUtils.sol` | `recoverSignerAtOffsetOrRevert`, `tryRecoverSignerAtOffset` | Revert-wrapper parity: success path matches `tryRecoverSignerAtOffset`; any failed recovery path always reverts `SignatureRecoveryFailed` | 10000 | P0 |
| FMU-MERK-11 | `src/libraries/MerkleUtils.sol` | `computeAddressLeaf` + Merkle verification | Any byte mutation in a valid proof invalidates verification | 10000 | P0 |
| FTTU-TXTOK-12 | `src/libraries/TokenTransferUtils.sol` | `isTransactionTokenTransfer` | Native and ERC-20 classification is mutually exclusive for random calldata/value pairs | 10000 | P0 |
| FTTU-ERC20-13 | `src/libraries/TokenTransferUtils.sol` | `isTransactionERC20TokenTransfer` | ERC-20 transfer only when selector is `transfer(address,uint256)` and `value == 0` | 10000 | P0 |
| FTTU-RECIP-14 | `src/libraries/TokenTransferUtils.sol` | `extractERC20TransferRecipient` | Random valid transfer calldata always extracts correct recipient | 10000 | P0 |
| FTTU-PARSE-16 | `src/libraries/TokenTransferUtils.sol` | `extractERC20TransferRecipient`, `extractTransferAmount` | Malformed calldata lengths always revert `MalformedTokenTransfer` | 10000 | P0 |
| FCIU-SELECT-19 | `src/libraries/ContractInteractionUtils.sol` | `extractFunctionSelector` | For random calldata length `< 4`, selector extraction always reverts (never returns padded garbage) | 1000 | P2 |
| FBU-SLICE-22 | `src/libraries/BytesUtils.sol` | `sliceFrom`, `sliceRange` | Keep existing fuzz suite as mandatory regression coverage | 1000 | P2 |
| FLOI-INIT-26 | `src/organization/libraries/LibOrganizationInitialization.sol` | `initialize` | Valid randomized initialization params establish core invariants: initialized state set once, admins are members, guardian/timelock persisted, optional recovery config respected | 10000 | P0 |
| FLOI-INIT-27 | `src/organization/libraries/LibOrganizationInitialization.sol` | `initialize` | Any failing sub-step (members/admins/groups/recovery validation) reverts atomically with no partial persisted org state | 10000 | P0 |
| FOIB-INIT-28 | `src/organization/base/OrganizationInitializationBase.sol` | `initialize` | Only deployer can initialize and initialization is strictly single-use (`false -> true` exactly once) | 10000 | P0 |
| FLOS-NONCE-32 | `src/organization/libraries/LibOrganizationSignatures.sol` | `validateAndConsumeNonceOrRevert` | Monotonic consumption: `false -> true` only; replay always reverts | 10000 | P0 |
| FLOS-ROLL-33 | `src/organization/libraries/LibOrganizationSignatures.sol` | `validateAndConsumeNonceOrRevert` (integration) | Failed parent tx paths do not burn nonce after revert rollback | 10000 | P0 |
| FLOEIP-HASH-36 | `src/organization/libraries/LibOrganizationEIP712.sol` | `computeTypedDataHash` | Output equals EIP-712 reference `keccak256(0x1901 || domain || structHash)` | 2000 | P1 |
| FLOA-AUTH-38 | `src/organization/libraries/LibOrganizationAdmin.sol` | `validateAdminAuthAndConsumeNonceOrRevert` | Expiration boundary: future timestamps pass, past timestamps fail | 10000 | P0 |
| FLOA-AUTH-39 | `src/organization/libraries/LibOrganizationAdmin.sol` | `validateAdminAuthAndConsumeNonceOrRevert`, `_getAdminOperationHash` | Signatures are bound to `operationType`, `operationData`, `salt`, `isApproval`, `chainId`, and org address | 10000 | P0 |
| FLOA-SIGS-40 | `src/organization/libraries/LibOrganizationAdmin.sol` | `_areAdminSignaturesValid` | Admin signers must be strictly ascending and unique (duplicates/out-of-order revert) | 10000 | P0 |
| FLOA-SIGS-41 | `src/organization/libraries/LibOrganizationAdmin.sol` | `_areAdminSignaturesValid` | Any non-admin signer in stream reverts authorization | 10000 | P0 |
| FLOA-ADMINS-42 | `src/organization/libraries/LibOrganizationAdmin.sol` | `modifyAdmins` | `newVotingThreshold` must satisfy `1 <= threshold <= adminCount` after modification | 10000 | P0 |
| FLOA-ADMINS-43 | `src/organization/libraries/LibOrganizationAdmin.sol` | `modifyAdmins` | Random add/remove arrays never leave `adminCount == 0` | 10000 | P0 |
| FOAB-ADMOP-45 | `src/organization/base/OrganizationAdminBase.sol` | `modifyAdmins`, `rejectAdminOperation` | Guardian-only access and operation-data binding: signatures for one `(operationType, payloadHashes, threshold, salt)` never authorize a different payload | 10000 | P0 |
| FLOM-MEMBER-46 | `src/organization/libraries/LibOrganizationMembers.sol` | `modifyMembers` | Add is idempotent for duplicates; remove non-member always reverts | 10000 | P0 |
| FLOM-MEMBER-47 | `src/organization/libraries/LibOrganizationMembers.sol` | `modifyMembers` | `address(0)` additions always revert; admin-member removal always reverts | 10000 | P0 |
| FOMB-MEMBER-48 | `src/organization/base/OrganizationMembersBase.sol` | `modifyMembers` | Guardian-only access and operation-data binding to `keccak256(adds)`/`keccak256(removes)` prevent signature reuse across different member batches | 10000 | P0 |
| FLOG-GROUP-49 | `src/organization/libraries/LibOrganizationGroups.sol` | `modifyGroups` | Create/update/delete semantics hold for random valid modification batches | 10000 | P0 |
| FLOG-GROUP-50 | `src/organization/libraries/LibOrganizationGroups.sol` | `modifyGroups` | Deleted group IDs are never reusable | 10000 | P0 |
| FLOG-GROUP-51 | `src/organization/libraries/LibOrganizationGroups.sol` | `modifyGroups` | `address(0)` group members are always rejected | 10000 | P0 |
| FLOG-GROUP-52 | `src/organization/libraries/LibOrganizationGroups.sol` | `modifyGroups` | **[DESIRED]** only organization members can be added to groups | 10000 | P0 |
| FLOG-HAR-53 | `src/organization/libraries/LibOrganizationGroups.sol` | private helpers via harness | `_createGroup`, `_updateGroup`, `_deleteGroup`, `_addGroupMembers`, `_removeGroupMembers` stay atomic and consistent | 2000 | P1 |
| FOGB-GROUP-54 | `src/organization/base/OrganizationGroupsBase.sol` | `modifyGroups` | Guardian-only access and operation-data binding to `keccak256(abi.encode(modifications))` prevent replaying signatures for altered group batches | 10000 | P0 |
| FLOP-SET-55 | `src/organization/libraries/LibOrganizationPolicy.sol` | `setPolicies` | Policies root changes only via explicit `setPolicies` calls | 2000 | P1 |
| FLOP-MERKLE-56 | `src/organization/libraries/LibOrganizationPolicy.sol` | `isPolicyInOrg` | Exact policy+proof verifies; any single-field mutation in policy/proof fails | 10000 | P0 |
| FLOP-SOURCE-57 | `src/organization/libraries/LibOrganizationPolicy.sol` | `isSourceAccountAllowedByPolicy` | `anySourceAccount=true` always accepts; false requires valid source proof | 10000 | P0 |
| FLOP-TX-58 | `src/organization/libraries/LibOrganizationPolicy.sol` | `isTransactionAllowedByPolicy` | Token-transfer policies only accept actual token transfers satisfying token+destination constraints | 10000 | P0 |
| FLOP-TX-59 | `src/organization/libraries/LibOrganizationPolicy.sol` | `isTransactionAllowedByPolicy` | Contract-interaction policies reject token transfers and enforce function+constraint+destination checks | 10000 | P0 |
| FLOP-TX-60 | `src/organization/libraries/LibOrganizationPolicy.sol` | `isTransactionAllowedByPolicy` | `TransactionType.Any` accepts both tx classes only when destination checks pass | 10000 | P0 |
| FLOP-TX-61 | `src/organization/libraries/LibOrganizationPolicy.sol` | `isTransactionAllowedByPolicy` | `TransactionType.Signatures` never authorizes account transaction execution/rejection path | 10000 | P0 |
| FOPB-USAGE-63 | `src/organization/base/OrganizationPolicyBase.sol` | `setPolicies`, `getPolicyUsage` | Guardian-only policy updates bind signatures to `(newRoot, keccak256(ipfsCid))`; `getPolicyUsage` always reverts on invalid policy proof | 10000 | P0 |
| FLPD-DEST-65 | `src/organization/libraries/policy/LibPolicyDestination.sol` | `isDestinationAllowedByPolicy` | Custom destination mode accepts only valid Merkle membership proof | 10000 | P0 |
| FLPT-AMOUNT-67 | `src/organization/libraries/policy/LibPolicyTokenTransfer.sol` | `_isTokenAmountAllowedByPolicy` | **[DESIRED]** threshold check is inclusive (`amount <= threshold`) | 10000 | P0 |
| FLPT-ALLOW-68 | `src/organization/libraries/policy/LibPolicyTokenTransfer.sol` | `isTokenTransferAllowedByPolicy` | Malformed token calldata cannot bypass token policy checks | 10000 | P0 |
| FLPCI-FUNC-69 | `src/organization/libraries/policy/LibPolicyContractInteraction.sol` | `_isFunctionAllowedByPolicy` | `anyFunction=true` bypasses function proof requirements | 10000 | P0 |
| FLPCI-FUNC-70 | `src/organization/libraries/policy/LibPolicyContractInteraction.sol` | `_isFunctionAllowedByPolicy` | Function membership binds `selector + keccak256(constraints)` exactly | 10000 | P0 |
| FLPPC-PARAM-72 | `src/organization/libraries/policy/LibPolicyParameterConstraints.sol` | `areParametersAllowedByConstraints` | Empty constraint bytes and empty decoded arrays both accept | 2000 | P1 |
| FLPPC-VALID-73 | `src/organization/libraries/policy/LibPolicyParameterConstraints.sol` | type-specific validators via harness | Exact/Range/OneOf matrix enforced correctly for supported combinations | 10000 | P0 |
| FLPPC-VALID-74 | `src/organization/libraries/policy/LibPolicyParameterConstraints.sol` | type-specific validators via harness | Unsupported combinations always fail (no silent acceptance) | 10000 | P0 |
| FLPPC-ONEOF-75 | `src/organization/libraries/policy/LibPolicyParameterConstraints.sol` | address OneOf path | Valid proof passes; mutated proof/value/root fails | 10000 | P0 |
| FLPPC-BYTES-76 | `src/organization/libraries/policy/LibPolicyParameterConstraints.sol` | bytes/string path | Malformed dynamic offsets/lengths return `false` (no panic/revert) | 10000 | P0 |
| FLPPC-PROCESS-77 | `src/organization/libraries/policy/LibPolicyParameterConstraints.sol` | `_processConstraints` | Random offsets/head-slot counts terminate and do not overflow/panic | 10000 | P0 |
| FLPA-APPROVE-78 | `src/organization/libraries/policy/LibPolicyApproval.sol` | `areApprovalsValid` | Reviewer signers must be sorted/unique; duplicates/out-of-order revert | 10000 | P0 |
| FLPA-SAUTH-80 | `src/organization/libraries/policy/LibPolicyApproval.sol` | private `_isSignerAuthorizedForPolicy` via harness | Signer must be org member and match member/group approver config | 10000 | P0 |
| FLPI-INIT-81 | `src/organization/libraries/policy/LibPolicyInitiator.sol` | `isInitiatorAuthorized` | Any/member/group initiator modes enforced correctly; non-members always fail unless `anyInitiator` is explicitly intended | 10000 | P0 |
| FLPRL-RATE-82 | `src/organization/libraries/policy/LibPolicyRateLimits.sol` | `checkAndUpdateRateLimit` | `None` and zero-hour interval modes are no-op success | 2000 | P1 |
| FLPRL-RATE-84 | `src/organization/libraries/policy/LibPolicyRateLimits.sol` | `checkAndUpdateRateLimit` | Within-limit usage increments exactly by `usageAmount` | 10000 | P0 |
| FLPRL-RATE-85 | `src/organization/libraries/policy/LibPolicyRateLimits.sol` | `checkAndUpdateRateLimit` | Exceeding limit returns `false` and does not modify usage | 10000 | P0 |
| FLPRL-WINDOW-86 | `src/organization/libraries/policy/LibPolicyRateLimits.sol` | `computeTimeWindow`, `getCurrentUsage` | Usage is window-local and resets when time window changes | 10000 | P0 |
| FLPRL-RATE-87 | `src/organization/libraries/policy/LibPolicyRateLimits.sol` | `checkAndUpdateRateLimit` | **[DESIRED]** near-overflow usage math should fail safely (not panic) and behave as over-limit | 10000 | P0 |
| FLOAT-APPROVE-88 | `src/organization/libraries/LibOrganizationAccountTransaction.sol` | `validateTransactionApprovalOrRevert` | Requires non-expired tx, valid initiator sig, and policy applicability | 10000 | P0 |
| FLOAT-REJECT-89 | `src/organization/libraries/LibOrganizationAccountTransaction.sol` | `validateTransactionRejectionOrRevert` | Auto-approve rejection uses authorized initiator rejection sig; manual uses reviewer threshold | 10000 | P0 |
| FLOAT-RATE-92 | `src/organization/libraries/LibOrganizationAccountTransaction.sol` | `_validateAndUpdateRateLimitOrRevert` | Usage amount is transfer amount for token-transfer policies, otherwise `1` | 10000 | P0 |
| FLOAT-FLOW-93 | `src/organization/libraries/LibOrganizationAccountTransaction.sol` | approval/rejection signature flow | Approval signatures cannot be replayed as rejection signatures (and vice versa) | 10000 | P0 |
| FOATB-ENTRY-94 | `src/organization/base/OrganizationAccountTransactionBase.sol` | `executeAccountTransaction`, `rejectAccountTransaction` | Non-org account addresses are always rejected | 10000 | P0 |
| FOATB-ENTRY-95 | `src/organization/base/OrganizationAccountTransactionBase.sol` | `executeAccountTransaction`, `rejectAccountTransaction` | Same tx payload+salt yields same nonce; first consume blocks second path | 10000 | P0 |
| FOATB-EXEC-96 | `src/organization/base/OrganizationAccountTransactionBase.sol` | `executeAccountTransaction` | CEI property: replay attempts during reentrancy fail because nonce is consumed first | 10000 | P0 |
| FLOAS-SIG-97 | `src/organization/libraries/LibOrganizationAccountSignature.sol` | `isValidSignature` | Only type prefixes `0x00` and `0x01` can ever return magic value | 10000 | P0 |
| FLOAS-RECOV-98 | `src/organization/libraries/LibOrganizationAccountSignature.sol` | `_validateRecoverySignature` | Recovery signatures pass only when tx recovery is configured+enabled and signer matches recovery address | 10000 | P0 |
| FLOAS-POLICY-99 | `src/organization/libraries/LibOrganizationAccountSignature.sol` | `_validatePolicyBasedSignature` | Policy path enforces expiration, initiator sig, guardian sig, policy applicability, and manual approvals when needed | 10000 | P0 |
| FLOAS-GUARD-100 | `src/organization/libraries/LibOrganizationAccountSignature.sol` | `_isValidGuardianSignature` | Guardian sig accepted from guardian directly or enabled safe module only | 10000 | P0 |
| FLOAS-E712-102 | `src/organization/libraries/LibOrganizationAccountSignature.sol` | EIP-712 hash helpers | Cross-org and cross-chain replay always fails | 10000 | P0 |
| FLOAS-SIG-103 | `src/organization/libraries/LibOrganizationAccountSignature.sol` | `isValidSignature` | **[DESIRED]** malformed policy payloads return `0xffffffff` and never revert | 10000 | P0 |
| FOASB-SIG-104 | `src/organization/base/OrganizationAccountSignatureBase.sol` | `isValidSignatureForAccount` | Caller must equal `account` and account must be deployed by organization | 10000 | P0 |
| FLOGU-FINAL-106 | `src/organization/libraries/LibOrganizationGuardian.sol` | `finalizeGuardianUpdate` | Finalize before timelock expiry always reverts | 2000 | P1 |
| FLOGU-ACCEPT-107 | `src/organization/libraries/LibOrganizationGuardian.sol` | `acceptGuardian` | Accept requires finalized state and pending guardian caller | 2000 | P1 |
| FLOGU-CANCEL-108 | `src/organization/libraries/LibOrganizationGuardian.sol` | `cancelGuardianUpdate` | Cancel clears all normal pending guardian state | 2000 | P1 |
| FLOGR-INIT-109 | `src/organization/libraries/LibOrganizationGuardianRecovery.sol` | `initializeGuardianRecovery` | Recovery config can only be initialized once | 2000 | P1 |
| FLOTR-INIT-110 | `src/organization/libraries/LibOrganizationTxRecovery.sol` | `initializeTxRecovery` | Tx recovery config can only be initialized once | 2000 | P1 |
| FLOGR-DINIT-111 | `src/organization/libraries/LibOrganizationGuardianRecovery.sol` | deferred init trio | Initiate/finalize/cancel deferred guardian-recovery init obey admin-operation timelock | 2000 | P1 |
| FLOTR-DINIT-112 | `src/organization/libraries/LibOrganizationTxRecovery.sol` | deferred init trio | Initiate/finalize/cancel deferred tx-recovery init obey admin-operation timelock | 2000 | P1 |
| FLOGR-RUPDATE-113 | `src/organization/libraries/LibOrganizationGuardianRecovery.sol` | recovery update trio | Recovery guardian flow uses recovery-specific timelock and isolated state | 10000 | P0 |
| FLOTR-TOGGLE-114 | `src/organization/libraries/LibOrganizationTxRecovery.sol` | enable/disable trio | Tx recovery enable requires timelock; disable is immediate and clears pending enable | 10000 | P0 |
| FLOTR-GATE-115 | `src/organization/libraries/LibOrganizationTxRecovery.sol` | `validateRecoveryAccountTransactionAllowedOrRevert` | Recovery tx path allowed only when configured and enabled | 10000 | P0 |
| FLOTR-SIG-116 | `src/organization/libraries/LibOrganizationTxRecovery.sol` | `isValidRecoverySignature` | Supports EOA and ERC-1271 recovery signers; validity independent of enabled flag | 10000 | P0 |
| FLOGR-ISO-117 | `src/organization/libraries/LibOrganizationGuardianRecovery.sol` + `LibOrganizationTxRecovery.sol` | state isolation | Guardian recovery ops never mutate tx recovery state and vice versa | 10000 | P0 |
| FLOGR-HAR-118 | `src/organization/libraries/LibOrganizationGuardianRecovery.sol` + `LibOrganizationTxRecovery.sol` | private helpers via harness | `_clearPending*` and `_validate*` helpers are idempotent and field-consistent | 2000 | P1 |
| FOGUB-ENTRY-119 | `src/organization/base/OrganizationGuardianBase.sol` | guardian entrypoints | Random caller fuzz enforces only-guardian and only-pending-guardian access rules | 10000 | P0 |
| FOGRB-ENTRY-120 | `src/organization/base/OrganizationGuardianRecoveryBase.sol` | recovery guardian entrypoints | Random caller fuzz enforces only-recovery-address and only-recovery-pending-guardian rules | 10000 | P0 |
| FOTRB-ENTRY-121 | `src/organization/base/OrganizationTxRecoveryBase.sol` | tx recovery entrypoints | Random caller fuzz enforces only-tx-recovery-address rules | 10000 | P0 |
| FOAFB-AUTH-122 | `src/organization/base/OrganizationAccountFactoryBase.sol` | `deployAccount`, `setAccountImplementation` | Guardian-only auth + operation-data binding (`create2Salt` / `newImplementation`) + account-whitelist enforcement hold under randomized payloads/signatures | 10000 | P0 |
| FLOAF-DEPLOY-124 | `src/organization/libraries/LibOrganizationAccountFactory.sol` | `deployAccount`, `computeAccountAddress` | CREATE2 address is deterministic for random salts and always matches deployed address | 2000 | P1 |
| FLOAF-DEPLOY-125 | `src/organization/libraries/LibOrganizationAccountFactory.sol` | `deployAccount` | `deployedAccounts[address]` transitions `false -> true` only | 2000 | P1 |
| FLOAF-DEPLOY-127 | `src/organization/libraries/LibOrganizationAccountFactory.sol` | `deployAccount` | Reusing the same salt always reverts (CREATE2 collision), and failed repeat attempts never corrupt `deployedAccounts` mapping state | 10000 | P0 |
| FOF-DEPLOY-129 | `src/organization/OrganizationFactory.sol` | `deployOrganization`, `computeOrganizationAddress` | CREATE2 address deterministic for `(salt, implementation, whitelist)` | 2000 | P1 |
| FOF-DEPLOY-130 | `src/organization/OrganizationFactory.sol` | `deployOrganization` | Only `DEPLOYER_ADDRESS` can deploy | 10000 | P0 |
| FOF-DINIT-131 | `src/organization/OrganizationFactory.sol` | deploy+initialize integration | Failed initialization leaves no partial state and allows deterministic retry | 10000 | P0 |
| FOI-UPGRADE-134 | `src/organization/OrganizationImplementation.sol` | `upgradeToAndCallWithAuthorization` | Upgrade requires guardian caller + valid admin auth + whitelisted implementation | 10000 | P0 |
| FOI-AUTH-135 | `src/organization/OrganizationImplementation.sol` | `_authorizeUpgrade` | Direct `upgradeToAndCall` without auth flag always reverts `UnauthorizedUpgrade` | 10000 | P0 |
| FOI-FLAG-136 | `src/organization/OrganizationImplementation.sol` | upgrade auth flag flow | Authorization flag is false outside active authorized upgrade path | 10000 | P0 |
| FOI-UPGRADE-137 | `src/organization/OrganizationImplementation.sol` | upgrade path | **[DESIRED]** random migration calldata cannot trigger unauthorized nested second upgrade | 10000 | P0 |
| FIWI-INIT-138 | `src/implementation-whitelist/ImplementationWhitelistImplementation.sol` | `initialize`, `isInitialized` | Initialization is one-time (`false -> true`), sets owner exactly once, and cannot be re-run with altered initial whitelist sets | 10000 | P0 |
| FIWI-WHITELIST-140 | `src/implementation-whitelist/ImplementationWhitelistImplementation.sol` | `whitelistImplementations` | Only owner can mutate whitelist mapping under random caller fuzz | 10000 | P0 |
| FIWI-MAP-141 | `src/implementation-whitelist/ImplementationWhitelistImplementation.sol` | whitelist mapping logic | `ContractType.Account` and `ContractType.Organization` mappings remain independent | 10000 | P0 |
| FIWI-ENFORCE-142 | `src/implementation-whitelist/ImplementationWhitelistImplementation.sol` + integration callsites | whitelist enforcement | Unwhitelisted implementation rejected in org deploy, org upgrade, and account upgrade flows | 10000 | P0 |
| FIWI-HELPER-143 | `src/implementation-whitelist/ImplementationWhitelistImplementation.sol` | private `_addToWhitelist`, `_removeFromWhitelist` via harness | Model-based add/remove sequence parity under random operations | 2000 | P1 |
| FIWI-MUTATE-144 | `src/implementation-whitelist/ImplementationWhitelistImplementation.sol` | whitelist mutation | **[DESIRED]** zero-address / no-code implementations are rejected even if submitted for whitelisting | 10000 | P0 |
| FAI-ORG-145 | `src/account/AccountImplementation.sol` | `executeTransaction`, `_onlyOrganization` | Only organization can execute account calls | 10000 | P0 |
| FAI-EXEC-146 | `src/account/AccountImplementation.sol` | `_execute` via harness | CALL success/failure and data/value forwarding behavior preserved for random targets | 2000 | P1 |
| FSEM-EXEC-150 | `src/safe-module/SafeExecutorModule.sol` | `executeOnBehalf` | Only `AUTHORIZED_EXECUTOR` can call successfully | 10000 | P0 |
| FSEM-EXEC-151 | `src/safe-module/SafeExecutorModule.sol` | `executeOnBehalf` | Calls targeting `SAFE` always revert | 10000 | P0 |
| FSEM-EXEC-153 | `src/safe-module/SafeExecutorModule.sol` | `executeOnBehalf` | Safe execution always uses `value == 0` | 10000 | P0 |
| FSEM-EXEC-154 | `src/safe-module/SafeExecutorModule.sol` | `executeOnBehalf` | If Safe module execution fails, function always reverts `ExecutionFailed` (never returns `false`) | 10000 | P0 |
| FBT-EXEC-156 | `src/safe-module/BatchedTransaction.sol` | `execute` | Valid packed batches produce same effects as sequential execution | 2000 | P1 |
| FBT-EXEC-157 | `src/safe-module/BatchedTransaction.sol` | `execute` | Any subcall to `address(this)` reverts entire batch | 10000 | P0 |
| FBT-EXEC-158 | `src/safe-module/BatchedTransaction.sol` | `execute` | **[DESIRED]** malformed packed payloads revert atomically (no partial effects) | 10000 | P0 |
| FBT-EXEC-159 | `src/safe-module/BatchedTransaction.sol` | `execute` | Fuzzed bounded batch sizes/data lengths always terminate | 2000 | P1 |
| FBT-EXEC-160 | `src/safe-module/BatchedTransaction.sol` | `execute` | Every subcall is executed with `value == 0` regardless of payload shape (no ETH transfer path exists) | 10000 | P0 |
| FCF-SIGSYS-161 | `cross-file` | signature systems | Admin/account/recovery signatures are non-transferable across op types, orgs, and chains | 10000 | P0 |
| FCF-ASREC-162 | `cross-file` | account signature + recovery | Recovery bypass is active only for `0x00` signatures while tx recovery is enabled | 10000 | P0 |
| FCF-RATE-163 | `cross-file` | policy rate limits | `getPolicyUsage` matches usage mutations from transaction execution path | 10000 | P0 |
| FCF-MODULE-164 | `cross-file` | guardian module rotation | Disabling old module invalidates old signatures immediately; enabling new module activates new signatures immediately | 10000 | P0 |
| FCF-REPLAY-165 | `cross-file` | nonce/replay | Approve/reject/recovery flows cannot replay consumed nonces under randomized ordering | 10000 | P0 |
| FCF-DEPLOY-166 | `cross-file` | deployment determinism | Factory/account CREATE2 address precomputation matches runtime deployment across random salts | 2000 | P1 |
| FCF-TIMELK-167 | `cross-file` | admin-operation timelock callsites | Guardian update finalize timestamps and deferred recovery-init finalize timestamps are all derived from the same org-wide admin-operation timelock duration | 10000 | P0 |

## Summary
- Total fuzz/property cases: `129`
- Includes private-function harness coverage where needed
- Explicitly excludes interfaces and storage libraries
