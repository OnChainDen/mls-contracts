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
| 1 | `src/libraries/SignatureUtils.sol` | `tryRecoverSigner`, `recoverSignerOrRevert` | Valid EOA and ERC-1271 signatures recover expected signer | 10000 | P0 |
| 2 | `src/libraries/SignatureUtils.sol` | `tryRecoverSigner`, `recoverSignerOrRevert` | Invalid `v` / malformed length / truncated bytes fail (`false` or `SignatureRecoveryFailed`) | 10000 | P0 |
| 3 | `src/libraries/SignatureUtils.sol` | `_tryRecoverEOASigner` | High-`s` malleable signatures are always rejected | 10000 | P0 |
| 4 | `src/libraries/SignatureUtils.sol` | `tryRecoverSigner`, `tryRecoverSignerAtOffset` | Signature for hash `A` never validates for hash `B` | 10000 | P0 |
| 5 | `src/libraries/SignatureUtils.sol` | `tryRecoverSignerAtOffset` | Mixed packed signatures (EOA + ERC-1271) produce strictly increasing offsets ending at `signatures.length` | 10000 | P0 |
| 6 | `src/libraries/SignatureUtils.sol` | `_tryRecoverContractSigner`, `_isValidERC1271SignatureNow` | Revert/empty/short/non-magic ERC-1271 responses always fail recovery | 10000 | P0 |
| 7 | `src/libraries/SignatureUtils.sol` | private helpers via harness | `_getVByte`, `_getContractSigner`, `_getContractSignatureLength`, `_extractContractInnerSignature` parse correctly with random offsets/lengths | 2000 | P1 |
| 141 | `src/libraries/SignatureUtils.sol` | `recoverSignerAtOffsetOrRevert`, `tryRecoverSignerAtOffset` | Revert-wrapper parity: success path matches `tryRecoverSignerAtOffset`; any failed recovery path always reverts `SignatureRecoveryFailed` | 10000 | P0 |
| 8 | `src/libraries/MerkleUtils.sol` | `computeAddressLeaf` | Deterministic and double-hashed leaf format for random addresses | 2000 | P1 |
| 9 | `src/libraries/MerkleUtils.sol` | `computeAddressLeaf` | Distinct random addresses do not collide in practical fuzz space | 2000 | P1 |
| 10 | `src/libraries/MerkleUtils.sol` | `computeAddressLeaf` + Merkle verification | Any byte mutation in a valid proof invalidates verification | 10000 | P0 |
| 11 | `src/libraries/TokenTransferUtils.sol` | `isTransactionTokenTransfer` | Native and ERC-20 classification is mutually exclusive for random calldata/value pairs | 10000 | P0 |
| 12 | `src/libraries/TokenTransferUtils.sol` | `isTransactionERC20TokenTransfer` | ERC-20 transfer only when selector is `transfer(address,uint256)` and `value == 0` | 10000 | P0 |
| 13 | `src/libraries/TokenTransferUtils.sol` | `extractERC20TransferRecipient` | Random valid transfer calldata always extracts correct recipient | 10000 | P0 |
| 14 | `src/libraries/TokenTransferUtils.sol` | `extractTransferAmount` | Native path returns `value`; ERC-20 path returns encoded amount | 10000 | P0 |
| 15 | `src/libraries/TokenTransferUtils.sol` | `extractERC20TransferRecipient`, `extractTransferAmount` | Malformed calldata lengths always revert `MalformedTokenTransfer` | 10000 | P0 |
| 16 | `src/libraries/TokenTransferUtils.sol` | `extractTokenAddress` | Non-empty calldata always returns `to`; empty calldata always returns `address(0)` | 10000 | P0 |
| 17 | `src/libraries/ContractInteractionUtils.sol` | `extractFunctionSelector` | For random calldata length `>= 4`, selector always equals first 4 bytes | 1000 | P2 |
| 142 | `src/libraries/ContractInteractionUtils.sol` | `extractFunctionSelector` | For random calldata length `< 4`, selector extraction always reverts (never returns padded garbage) | 1000 | P2 |
| 18 | `src/libraries/TimelockUtils.sol` | `validateTimelockDurationOrRevert` | Any duration in `[2 days, 30 days]` always succeeds | 2000 | P1 |
| 19 | `src/libraries/TimelockUtils.sol` | `validateTimelockDurationOrRevert` | Any duration outside `[2 days, 30 days]` always reverts | 2000 | P1 |
| 20 | `src/libraries/BytesUtils.sol` | `sliceFrom`, `sliceRange` | Keep existing fuzz suite as mandatory regression coverage | 1000 | P2 |
| 143 | `src/organization/libraries/LibOrganizationAdminOperationTimelock.sol` | `initializeAdminOperationTimelock`, `getAdminOperationTimelockDurationSeconds` | Valid boundaries (`2 days`, `30 days`) persist exactly; out-of-range values always revert via timelock validation | 2000 | P1 |
| 144 | `src/organization/libraries/LibOrganizationAdminOperationTimelock.sol` | `validateTimelockExpiredOrRevert`, `computeCanFinalizeAtTimestamp` | Boundary semantics hold: `< canFinalizeAt` reverts, `>= canFinalizeAt` succeeds, and computed timestamp equals `block.timestamp + configuredDuration` | 10000 | P0 |
| 145 | `src/organization/base/OrganizationAdminOperationTimelockBase.sol` | `adminOperationTimelockDurationSeconds` | Base getter always reflects initialized value and remains unchanged across guardian/recovery operation flows | 2000 | P1 |
| 146 | `src/organization/libraries/LibOrganizationInitialization.sol` | `initialize` | Valid randomized initialization params establish core invariants: initialized state set once, admins are members, guardian/timelock persisted, optional recovery config respected | 10000 | P0 |
| 147 | `src/organization/libraries/LibOrganizationInitialization.sol` | `initialize` | Any failing sub-step (members/admins/groups/recovery validation) reverts atomically with no partial persisted org state | 10000 | P0 |
| 148 | `src/organization/base/OrganizationInitializationBase.sol` | `initialize` | Only deployer can initialize and initialization is strictly single-use (`false -> true` exactly once) | 10000 | P0 |
| 149 | `src/organization/OrganizationProxy.sol` | constructor | Constructor always seeds deployer and whitelist storage slots exactly to constructor inputs for later initialization/upgrade auth checks | 2000 | P1 |
| 21 | `src/organization/libraries/LibOrganizationSignatures.sol` | `computeNonce` | `(operationType, operationData, salt)` sensitivity: changing any field changes nonce | 10000 | P0 |
| 22 | `src/organization/libraries/LibOrganizationSignatures.sol` | `computeNonce` | Cross-organization isolation: same inputs on different org addresses produce different nonces | 10000 | P0 |
| 23 | `src/organization/libraries/LibOrganizationSignatures.sol` | `validateAndConsumeNonceOrRevert` | Monotonic consumption: `false -> true` only; replay always reverts | 10000 | P0 |
| 24 | `src/organization/libraries/LibOrganizationSignatures.sol` | `validateAndConsumeNonceOrRevert` (integration) | Failed parent tx paths do not burn nonce after revert rollback | 10000 | P0 |
| 150 | `src/organization/base/OrganizationSignaturesBase.sol` | `computeNonce`, `isNonceUsed` | Base view functions stay library-consistent: nonce derivation caller-independent and nonce visibility reflects actual consume/revert outcomes | 2000 | P1 |
| 25 | `src/organization/libraries/LibOrganizationEIP712.sol` | `getDomainSeparator` | Domain separator deterministic for same org+chain, different for other org/chain | 10000 | P0 |
| 26 | `src/organization/libraries/LibOrganizationEIP712.sol` | `computeTypedDataHash` | Output equals EIP-712 reference `keccak256(0x1901 || domain || structHash)` | 2000 | P1 |
| 27 | `src/organization/libraries/LibOrganizationEIP712.sol` | typehash constants | All message type hashes are unique and match documented type strings | 2000 | P1 |
| 28 | `src/organization/libraries/LibOrganizationAdmin.sol` | `validateAdminAuthAndConsumeNonceOrRevert` | Expiration boundary: future timestamps pass, past timestamps fail | 10000 | P0 |
| 29 | `src/organization/libraries/LibOrganizationAdmin.sol` | `validateAdminAuthAndConsumeNonceOrRevert`, `_getAdminOperationHash` | Signatures are bound to `operationType`, `operationData`, `salt`, `isApproval`, `chainId`, and org address | 10000 | P0 |
| 30 | `src/organization/libraries/LibOrganizationAdmin.sol` | `_areAdminSignaturesValid` | Admin signers must be strictly ascending and unique (duplicates/out-of-order revert) | 10000 | P0 |
| 31 | `src/organization/libraries/LibOrganizationAdmin.sol` | `_areAdminSignaturesValid` | Any non-admin signer in stream reverts authorization | 10000 | P0 |
| 32 | `src/organization/libraries/LibOrganizationAdmin.sol` | `modifyAdmins` | `newVotingThreshold` must satisfy `1 <= threshold <= adminCount` after modification | 10000 | P0 |
| 33 | `src/organization/libraries/LibOrganizationAdmin.sol` | `modifyAdmins` | Random add/remove arrays never leave `adminCount == 0` | 10000 | P0 |
| 34 | `src/organization/libraries/LibOrganizationAdmin.sol` | private helpers via harness | `_getAdminOperationHash` deterministic + field-sensitive; `_areAdminSignaturesValid` robust under mixed signature streams | 2000 | P1 |
| 151 | `src/organization/base/OrganizationAdminBase.sol` | `modifyAdmins`, `rejectAdminOperation` | Guardian-only access and operation-data binding: signatures for one `(operationType, payloadHashes, threshold, salt)` never authorize a different payload | 10000 | P0 |
| 35 | `src/organization/libraries/LibOrganizationMembers.sol` | `modifyMembers` | Add is idempotent for duplicates; remove non-member always reverts | 10000 | P0 |
| 36 | `src/organization/libraries/LibOrganizationMembers.sol` | `modifyMembers` | `address(0)` additions always revert; admin-member removal always reverts | 10000 | P0 |
| 152 | `src/organization/base/OrganizationMembersBase.sol` | `modifyMembers` | Guardian-only access and operation-data binding to `keccak256(adds)`/`keccak256(removes)` prevent signature reuse across different member batches | 10000 | P0 |
| 37 | `src/organization/libraries/LibOrganizationGroups.sol` | `modifyGroups` | Create/update/delete semantics hold for random valid modification batches | 10000 | P0 |
| 38 | `src/organization/libraries/LibOrganizationGroups.sol` | `modifyGroups` | Deleted group IDs are never reusable | 10000 | P0 |
| 39 | `src/organization/libraries/LibOrganizationGroups.sol` | `modifyGroups` | `address(0)` group members are always rejected | 10000 | P0 |
| 40 | `src/organization/libraries/LibOrganizationGroups.sol` | `modifyGroups` | **[DESIRED]** only organization members can be added to groups | 10000 | P0 |
| 41 | `src/organization/libraries/LibOrganizationGroups.sol` | private helpers via harness | `_createGroup`, `_updateGroup`, `_deleteGroup`, `_addGroupMembers`, `_removeGroupMembers` stay atomic and consistent | 2000 | P1 |
| 153 | `src/organization/base/OrganizationGroupsBase.sol` | `modifyGroups` | Guardian-only access and operation-data binding to `keccak256(abi.encode(modifications))` prevent replaying signatures for altered group batches | 10000 | P0 |
| 42 | `src/organization/libraries/LibOrganizationPolicy.sol` | `setPolicies` | Policies root changes only via explicit `setPolicies` calls | 2000 | P1 |
| 43 | `src/organization/libraries/LibOrganizationPolicy.sol` | `isPolicyInOrg` | Exact policy+proof verifies; any single-field mutation in policy/proof fails | 10000 | P0 |
| 44 | `src/organization/libraries/LibOrganizationPolicy.sol` | `isSourceAccountAllowedByPolicy` | `anySourceAccount=true` always accepts; false requires valid source proof | 10000 | P0 |
| 45 | `src/organization/libraries/LibOrganizationPolicy.sol` | `isTransactionAllowedByPolicy` | Token-transfer policies only accept actual token transfers satisfying token+destination constraints | 10000 | P0 |
| 46 | `src/organization/libraries/LibOrganizationPolicy.sol` | `isTransactionAllowedByPolicy` | Contract-interaction policies reject token transfers and enforce function+constraint+destination checks | 10000 | P0 |
| 47 | `src/organization/libraries/LibOrganizationPolicy.sol` | `isTransactionAllowedByPolicy` | `TransactionType.Any` accepts both tx classes only when destination checks pass | 10000 | P0 |
| 48 | `src/organization/libraries/LibOrganizationPolicy.sol` | `isTransactionAllowedByPolicy` | `TransactionType.Signatures` never authorizes account transaction execution/rejection path | 10000 | P0 |
| 49 | `src/organization/libraries/LibOrganizationPolicy.sol` | private `_computePolicyLeaf` via harness | Policy leaf is deterministic, double-hashed, and sensitive to every field | 2000 | P1 |
| 154 | `src/organization/base/OrganizationPolicyBase.sol` | `setPolicies`, `getPolicyUsage` | Guardian-only policy updates bind signatures to `(newRoot, keccak256(ipfsCid))`; `getPolicyUsage` always reverts on invalid policy proof | 10000 | P0 |
| 50 | `src/organization/libraries/policy/LibPolicyDestination.sol` | `getActualDestination` | ERC-20 transfer uses token recipient as destination; non-transfer uses `to` | 10000 | P0 |
| 51 | `src/organization/libraries/policy/LibPolicyDestination.sol` | `isDestinationAllowedByPolicy` | Custom destination mode accepts only valid Merkle membership proof | 10000 | P0 |
| 52 | `src/organization/libraries/policy/LibPolicyTokenTransfer.sol` | `_isTokenAllowedByPolicy` | `anyToken` and specific-token behavior are enforced exactly | 10000 | P0 |
| 53 | `src/organization/libraries/policy/LibPolicyTokenTransfer.sol` | `_isTokenAmountAllowedByPolicy` | **[DESIRED]** threshold check is inclusive (`amount <= threshold`) | 10000 | P0 |
| 54 | `src/organization/libraries/policy/LibPolicyTokenTransfer.sol` | `isTokenTransferAllowedByPolicy` | Malformed token calldata cannot bypass token policy checks | 10000 | P0 |
| 55 | `src/organization/libraries/policy/LibPolicyContractInteraction.sol` | `_isFunctionAllowedByPolicy` | `anyFunction=true` bypasses function proof requirements | 10000 | P0 |
| 56 | `src/organization/libraries/policy/LibPolicyContractInteraction.sol` | `_isFunctionAllowedByPolicy` | Function membership binds `selector + keccak256(constraints)` exactly | 10000 | P0 |
| 57 | `src/organization/libraries/policy/LibPolicyContractInteraction.sol` | private `_computeFunctionLeaf` via harness | Deterministic, double-hashed function leaf generation | 2000 | P1 |
| 58 | `src/organization/libraries/policy/LibPolicyParameterConstraints.sol` | `areParametersAllowedByConstraints` | Empty constraint bytes and empty decoded arrays both accept | 2000 | P1 |
| 59 | `src/organization/libraries/policy/LibPolicyParameterConstraints.sol` | type-specific validators via harness | Exact/Range/OneOf matrix enforced correctly for supported combinations | 10000 | P0 |
| 60 | `src/organization/libraries/policy/LibPolicyParameterConstraints.sol` | type-specific validators via harness | Unsupported combinations always fail (no silent acceptance) | 10000 | P0 |
| 61 | `src/organization/libraries/policy/LibPolicyParameterConstraints.sol` | address OneOf path | Valid proof passes; mutated proof/value/root fails | 10000 | P0 |
| 62 | `src/organization/libraries/policy/LibPolicyParameterConstraints.sol` | bytes/string path | Malformed dynamic offsets/lengths return `false` (no panic/revert) | 10000 | P0 |
| 63 | `src/organization/libraries/policy/LibPolicyParameterConstraints.sol` | `_processConstraints` | Random offsets/head-slot counts terminate and do not overflow/panic | 10000 | P0 |
| 64 | `src/organization/libraries/policy/LibPolicyApproval.sol` | `areApprovalsValid` | Reviewer signers must be sorted/unique; duplicates/out-of-order revert | 10000 | P0 |
| 65 | `src/organization/libraries/policy/LibPolicyApproval.sol` | `getRequiredApprovals` | Member approver requires exactly 1; group approver requires threshold | 10000 | P0 |
| 66 | `src/organization/libraries/policy/LibPolicyApproval.sol` | private `_isSignerAuthorizedForPolicy` via harness | Signer must be org member and match member/group approver config | 10000 | P0 |
| 67 | `src/organization/libraries/policy/LibPolicyInitiator.sol` | `isInitiatorAuthorized` | Any/member/group initiator modes enforced correctly; non-members always fail unless `anyInitiator` is explicitly intended | 10000 | P0 |
| 68 | `src/organization/libraries/policy/LibPolicyRateLimits.sol` | `checkAndUpdateRateLimit` | `None` and zero-hour interval modes are no-op success | 2000 | P1 |
| 69 | `src/organization/libraries/policy/LibPolicyRateLimits.sol` | `computeUsageKey` | Scope composition (`AcrossAll` vs `PerEntity`) produces expected key isolation/merging | 10000 | P0 |
| 70 | `src/organization/libraries/policy/LibPolicyRateLimits.sol` | `checkAndUpdateRateLimit` | Within-limit usage increments exactly by `usageAmount` | 10000 | P0 |
| 71 | `src/organization/libraries/policy/LibPolicyRateLimits.sol` | `checkAndUpdateRateLimit` | Exceeding limit returns `false` and does not modify usage | 10000 | P0 |
| 72 | `src/organization/libraries/policy/LibPolicyRateLimits.sol` | `computeTimeWindow`, `getCurrentUsage` | Usage is window-local and resets when time window changes | 10000 | P0 |
| 73 | `src/organization/libraries/policy/LibPolicyRateLimits.sol` | `checkAndUpdateRateLimit` | **[DESIRED]** near-overflow usage math should fail safely (not panic) and behave as over-limit | 10000 | P0 |
| 74 | `src/organization/libraries/LibOrganizationAccountTransaction.sol` | `validateTransactionApprovalOrRevert` | Requires non-expired tx, valid initiator sig, and policy applicability | 10000 | P0 |
| 75 | `src/organization/libraries/LibOrganizationAccountTransaction.sol` | `validateTransactionRejectionOrRevert` | Auto-approve rejection uses authorized initiator rejection sig; manual uses reviewer threshold | 10000 | P0 |
| 76 | `src/organization/libraries/LibOrganizationAccountTransaction.sol` | private hash helpers via harness | `_computeInitiatorHashFromParams` and `_computeReviewHashFromParams` are field-sensitive and deterministic | 10000 | P0 |
| 77 | `src/organization/libraries/LibOrganizationAccountTransaction.sol` | private hash helpers via harness | Review hash always changes when `initiatorSignature` changes | 10000 | P0 |
| 78 | `src/organization/libraries/LibOrganizationAccountTransaction.sol` | `_validateAndUpdateRateLimitOrRevert` | Usage amount is transfer amount for token-transfer policies, otherwise `1` | 10000 | P0 |
| 79 | `src/organization/libraries/LibOrganizationAccountTransaction.sol` | approval/rejection signature flow | Approval signatures cannot be replayed as rejection signatures (and vice versa) | 10000 | P0 |
| 80 | `src/organization/base/OrganizationAccountTransactionBase.sol` | `executeAccountTransaction`, `rejectAccountTransaction` | Non-org account addresses are always rejected | 10000 | P0 |
| 81 | `src/organization/base/OrganizationAccountTransactionBase.sol` | `executeAccountTransaction`, `rejectAccountTransaction` | Same tx payload+salt yields same nonce; first consume blocks second path | 10000 | P0 |
| 82 | `src/organization/base/OrganizationAccountTransactionBase.sol` | `executeAccountTransaction` | CEI property: replay attempts during reentrancy fail because nonce is consumed first | 10000 | P0 |
| 83 | `src/organization/libraries/LibOrganizationAccountSignature.sol` | `isValidSignature` | Only type prefixes `0x00` and `0x01` can ever return magic value | 10000 | P0 |
| 84 | `src/organization/libraries/LibOrganizationAccountSignature.sol` | `_validateRecoverySignature` | Recovery signatures pass only when tx recovery is configured+enabled and signer matches recovery address | 10000 | P0 |
| 85 | `src/organization/libraries/LibOrganizationAccountSignature.sol` | `_validatePolicyBasedSignature` | Policy path enforces expiration, initiator sig, guardian sig, policy applicability, and manual approvals when needed | 10000 | P0 |
| 86 | `src/organization/libraries/LibOrganizationAccountSignature.sol` | `_isValidGuardianSignature` | Guardian sig accepted from guardian directly or enabled safe module only | 10000 | P0 |
| 87 | `src/organization/libraries/LibOrganizationAccountSignature.sol` | `_getReviewSignatureHash` | Review hash binds to initiator signature (`keccak256(initiatorSignature)`) | 10000 | P0 |
| 88 | `src/organization/libraries/LibOrganizationAccountSignature.sol` | EIP-712 hash helpers | Cross-org and cross-chain replay always fails | 10000 | P0 |
| 89 | `src/organization/libraries/LibOrganizationAccountSignature.sol` | `isValidSignature` | **[DESIRED]** malformed policy payloads return `0xffffffff` and never revert | 10000 | P0 |
| 90 | `src/organization/base/OrganizationAccountSignatureBase.sol` | `isValidSignatureForAccount` | Caller must equal `account` and account must be deployed by organization | 10000 | P0 |
| 91 | `src/organization/libraries/LibOrganizationGuardian.sol` | `initiateGuardianUpdate` | Pending guardian and finalize timestamp set correctly | 2000 | P1 |
| 92 | `src/organization/libraries/LibOrganizationGuardian.sol` | `finalizeGuardianUpdate` | Finalize before timelock expiry always reverts | 2000 | P1 |
| 93 | `src/organization/libraries/LibOrganizationGuardian.sol` | `acceptGuardian` | Accept requires finalized state and pending guardian caller | 2000 | P1 |
| 94 | `src/organization/libraries/LibOrganizationGuardian.sol` | `cancelGuardianUpdate` | Cancel clears all normal pending guardian state | 2000 | P1 |
| 95 | `src/organization/libraries/LibOrganizationGuardianRecovery.sol` | `initializeGuardianRecovery` | Recovery config can only be initialized once | 2000 | P1 |
| 96 | `src/organization/libraries/LibOrganizationTxRecovery.sol` | `initializeTxRecovery` | Tx recovery config can only be initialized once | 2000 | P1 |
| 97 | `src/organization/libraries/LibOrganizationGuardianRecovery.sol` | deferred init trio | Initiate/finalize/cancel deferred guardian-recovery init obey admin-operation timelock | 2000 | P1 |
| 98 | `src/organization/libraries/LibOrganizationTxRecovery.sol` | deferred init trio | Initiate/finalize/cancel deferred tx-recovery init obey admin-operation timelock | 2000 | P1 |
| 99 | `src/organization/libraries/LibOrganizationGuardianRecovery.sol` | recovery update trio | Recovery guardian flow uses recovery-specific timelock and isolated state | 10000 | P0 |
| 100 | `src/organization/libraries/LibOrganizationTxRecovery.sol` | enable/disable trio | Tx recovery enable requires timelock; disable is immediate and clears pending enable | 10000 | P0 |
| 101 | `src/organization/libraries/LibOrganizationTxRecovery.sol` | `validateRecoveryAccountTransactionAllowedOrRevert` | Recovery tx path allowed only when configured and enabled | 10000 | P0 |
| 102 | `src/organization/libraries/LibOrganizationTxRecovery.sol` | `isValidRecoverySignature` | Supports EOA and ERC-1271 recovery signers; validity independent of enabled flag | 10000 | P0 |
| 103 | `src/organization/libraries/LibOrganizationGuardianRecovery.sol` + `LibOrganizationTxRecovery.sol` | state isolation | Guardian recovery ops never mutate tx recovery state and vice versa | 10000 | P0 |
| 104 | `src/organization/libraries/LibOrganizationGuardianRecovery.sol` + `LibOrganizationTxRecovery.sol` | private helpers via harness | `_clearPending*` and `_validate*` helpers are idempotent and field-consistent | 2000 | P1 |
| 105 | `src/organization/base/OrganizationGuardianBase.sol` | guardian entrypoints | Random caller fuzz enforces only-guardian and only-pending-guardian access rules | 10000 | P0 |
| 106 | `src/organization/base/OrganizationGuardianRecoveryBase.sol` | recovery guardian entrypoints | Random caller fuzz enforces only-recovery-address and only-recovery-pending-guardian rules | 10000 | P0 |
| 107 | `src/organization/base/OrganizationTxRecoveryBase.sol` | tx recovery entrypoints | Random caller fuzz enforces only-tx-recovery-address rules | 10000 | P0 |
| 155 | `src/organization/base/OrganizationAccountFactoryBase.sol` | `deployAccount`, `setAccountImplementation` | Guardian-only auth + operation-data binding (`create2Salt` / `newImplementation`) + account-whitelist enforcement hold under randomized payloads/signatures | 10000 | P0 |
| 156 | `src/organization/base/OrganizationAccountFactoryBase.sol` | `implementation` | Beacon implementation getter always reverts when unset and returns exactly the configured whitelisted account implementation once set | 10000 | P0 |
| 108 | `src/organization/libraries/LibOrganizationAccountFactory.sol` | `deployAccount`, `computeAccountAddress` | CREATE2 address is deterministic for random salts and always matches deployed address | 2000 | P1 |
| 109 | `src/organization/libraries/LibOrganizationAccountFactory.sol` | `deployAccount` | `deployedAccounts[address]` transitions `false -> true` only | 2000 | P1 |
| 110 | `src/organization/libraries/LibOrganizationAccountFactory.sol` | `computeAccountAddress` | Same salt across different organizations yields different account addresses | 2000 | P1 |
| 157 | `src/organization/libraries/LibOrganizationAccountFactory.sol` | `deployAccount` | Reusing the same salt always reverts (CREATE2 collision), and failed repeat attempts never corrupt `deployedAccounts` mapping state | 10000 | P0 |
| 158 | `src/organization/libraries/LibOrganizationAccountFactory.sol` | `_getAccountProxyBytecode` via harness | Bytecode generation is deterministic and organization-address-sensitive (changes across org addresses, stable within one org) | 2000 | P1 |
| 111 | `src/organization/OrganizationFactory.sol` | `deployOrganization`, `computeOrganizationAddress` | CREATE2 address deterministic for `(salt, implementation, whitelist)` | 2000 | P1 |
| 112 | `src/organization/OrganizationFactory.sol` | `deployOrganization` | Only `DEPLOYER_ADDRESS` can deploy | 10000 | P0 |
| 113 | `src/organization/OrganizationFactory.sol` | deploy+initialize integration | Failed initialization leaves no partial state and allows deterministic retry | 10000 | P0 |
| 159 | `src/organization/OrganizationFactory.sol` | constructor | Constructor always rejects `address(0)` deployer and accepts non-zero deployer as immutable deployment authority | 2000 | P1 |
| 160 | `src/organization/OrganizationFactory.sol` | private `_getOrganizationProxyBytecode` via harness | Bytecode is deterministic and field-sensitive to `(implementationAddress, whitelistAddress)` and matches CREATE2 precompute inputs | 2000 | P1 |
| 114 | `src/organization/OrganizationImplementation.sol` | `upgradeToAndCallWithAuthorization` | Upgrade requires guardian caller + valid admin auth + whitelisted implementation | 10000 | P0 |
| 115 | `src/organization/OrganizationImplementation.sol` | `_authorizeUpgrade` | Direct `upgradeToAndCall` without auth flag always reverts `UnauthorizedUpgrade` | 10000 | P0 |
| 116 | `src/organization/OrganizationImplementation.sol` | upgrade auth flag flow | Authorization flag is false outside active authorized upgrade path | 10000 | P0 |
| 117 | `src/organization/OrganizationImplementation.sol` | upgrade path | **[DESIRED]** random migration calldata cannot trigger unauthorized nested second upgrade | 10000 | P0 |
| 161 | `src/implementation-whitelist/ImplementationWhitelistImplementation.sol` | `initialize`, `isInitialized` | Initialization is one-time (`false -> true`), sets owner exactly once, and cannot be re-run with altered initial whitelist sets | 10000 | P0 |
| 162 | `src/implementation-whitelist/ImplementationWhitelistImplementation.sol` | `isImplementationWhitelisted`, `validateIsImplementationWhitelistedOrRevert` | Validation helper is mapping-consistent for random `(contractType, implementation)` tuples (true passes, false always reverts) | 10000 | P0 |
| 118 | `src/implementation-whitelist/ImplementationWhitelistImplementation.sol` | `whitelistImplementations` | Only owner can mutate whitelist mapping under random caller fuzz | 10000 | P0 |
| 119 | `src/implementation-whitelist/ImplementationWhitelistImplementation.sol` | whitelist mapping logic | `ContractType.Account` and `ContractType.Organization` mappings remain independent | 10000 | P0 |
| 120 | `src/implementation-whitelist/ImplementationWhitelistImplementation.sol` + integration callsites | whitelist enforcement | Unwhitelisted implementation rejected in org deploy, org upgrade, and account upgrade flows | 10000 | P0 |
| 121 | `src/implementation-whitelist/ImplementationWhitelistImplementation.sol` | private `_addToWhitelist`, `_removeFromWhitelist` via harness | Model-based add/remove sequence parity under random operations | 2000 | P1 |
| 122 | `src/implementation-whitelist/ImplementationWhitelistImplementation.sol` | whitelist mutation | **[DESIRED]** zero-address / no-code implementations are rejected even if submitted for whitelisting | 10000 | P0 |
| 123 | `src/account/AccountImplementation.sol` | `executeTransaction`, `_onlyOrganization` | Only organization can execute account calls | 10000 | P0 |
| 124 | `src/account/AccountImplementation.sol` | `_execute` via harness | CALL success/failure and data/value forwarding behavior preserved for random targets | 2000 | P1 |
| 125 | `src/account/AccountImplementation.sol` | `isValidSignature` | Account always delegates signature validation to organization result | 2000 | P1 |
| 163 | `src/account/AccountImplementation.sol` | `receive`, `getOrganizationAddress` | Receiving native token always succeeds/emits and never mutates stored organization address returned by getter | 2000 | P1 |
| 164 | `src/safe-module/SafeExecutorModule.sol` | constructor | Any zero-address constructor arg (`safe`, `authorizedExecutor`, `batchedTransaction`) always reverts; non-zero tuple initializes immutables exactly | 2000 | P1 |
| 126 | `src/safe-module/SafeExecutorModule.sol` | `executeOnBehalf` | Only `AUTHORIZED_EXECUTOR` can call successfully | 10000 | P0 |
| 127 | `src/safe-module/SafeExecutorModule.sol` | `executeOnBehalf` | Calls targeting `SAFE` always revert | 10000 | P0 |
| 128 | `src/safe-module/SafeExecutorModule.sol` | `executeOnBehalf` | Delegatecall used iff target is `BATCHED_TRANSACTION`; otherwise regular call | 2000 | P1 |
| 129 | `src/safe-module/SafeExecutorModule.sol` | `executeOnBehalf` | Safe execution always uses `value == 0` | 10000 | P0 |
| 165 | `src/safe-module/SafeExecutorModule.sol` | `executeOnBehalf` | If Safe module execution fails, function always reverts `ExecutionFailed` (never returns `false`) | 10000 | P0 |
| 130 | `src/safe-module/SafeExecutorModule.sol` | `isValidSignature` | Returns magic only when recovered signer equals `AUTHORIZED_EXECUTOR` | 10000 | P0 |
| 131 | `src/safe-module/BatchedTransaction.sol` | `execute` | Valid packed batches produce same effects as sequential execution | 2000 | P1 |
| 132 | `src/safe-module/BatchedTransaction.sol` | `execute` | Any subcall to `address(this)` reverts entire batch | 10000 | P0 |
| 133 | `src/safe-module/BatchedTransaction.sol` | `execute` | **[DESIRED]** malformed packed payloads revert atomically (no partial effects) | 10000 | P0 |
| 134 | `src/safe-module/BatchedTransaction.sol` | `execute` | Fuzzed bounded batch sizes/data lengths always terminate | 2000 | P1 |
| 166 | `src/safe-module/BatchedTransaction.sol` | `execute` | Every subcall is executed with `value == 0` regardless of payload shape (no ETH transfer path exists) | 10000 | P0 |
| 135 | `cross-file` | signature systems | Admin/account/recovery signatures are non-transferable across op types, orgs, and chains | 10000 | P0 |
| 136 | `cross-file` | account signature + recovery | Recovery bypass is active only for `0x00` signatures while tx recovery is enabled | 10000 | P0 |
| 137 | `cross-file` | policy rate limits | `getPolicyUsage` matches usage mutations from transaction execution path | 10000 | P0 |
| 138 | `cross-file` | guardian module rotation | Disabling old module invalidates old signatures immediately; enabling new module activates new signatures immediately | 10000 | P0 |
| 139 | `cross-file` | nonce/replay | Approve/reject/recovery flows cannot replay consumed nonces under randomized ordering | 10000 | P0 |
| 140 | `cross-file` | deployment determinism | Factory/account CREATE2 address precomputation matches runtime deployment across random salts | 2000 | P1 |
| 167 | `cross-file` | admin-operation timelock callsites | Guardian update finalize timestamps and deferred recovery-init finalize timestamps are all derived from the same org-wide admin-operation timelock duration | 10000 | P0 |
| 168 | `cross-file` | factory deploy + initialization | Successful factory deployment always yields initialized org state in the same tx with `getDeployerAddress() == OrganizationFactory` | 10000 | P0 |

## Summary
- Total fuzz/property cases: `168`
- Includes private-function harness coverage where needed
- Explicitly excludes interfaces and storage libraries
