# 02 — Storage Libraries Test Plan

## Scope

This plan covers **all of our project's ERC-7201 storage libraries under `src/`**.


**Existing Tests:** `test/ERC7201StorageSlots.t.sol` (14 tests: 12 slot checks + uniqueness + `0x00` suffix check)

**Planned Test File(s):**
- Keep/extend `test/ERC7201StorageSlots.t.sol`
- Add `test/StorageLayout.t.sol` for variable-level read/write coverage

---

## 1. Complete ERC-7201 Library Inventory 

| Library | Namespace | Layout Variables That Must Be Covered |
|---|---|---|
| `src/organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol` | `den.mls-wallet.organization.account-factory` | `deployedAccounts`, `accountImplementation` |
| `src/organization/libraries/storage/LibOrganizationAdminOperationTimelockStorage.sol` | `den.mls-wallet.organization.admin-operation-timelock` | `adminOperationTimelockDurationSeconds` |
| `src/organization/libraries/storage/LibOrganizationAdminStorage.sol` | `den.mls-wallet.organization.admin` | `isAdmin`, `adminCount`, `votingThreshold` |
| `src/organization/libraries/storage/LibOrganizationDeployerAddressStorage.sol` | `den.mls-wallet.organization.deployer` | `deployerAddress` |
| `src/organization/libraries/storage/LibOrganizationGroupsStorage.sol` | `den.mls-wallet.organization.groups` | `isGroup`, `isGroupMember`, `wasGroupDeleted` |
| `src/organization/libraries/storage/LibOrganizationGuardianStorage.sol` | `den.mls-wallet.organization.guardian` | `guardian`, `isGuardianUpdateReadyForAcceptance`, `pendingGuardian`, `pendingGuardianUpdateTimestamp` |
| `src/organization/libraries/storage/LibOrganizationMembersStorage.sol` | `den.mls-wallet.organization.members` | `isMember` |
| `src/organization/libraries/storage/LibOrganizationPolicyStorage.sol` | `den.mls-wallet.organization.policy` | `policiesRoot`, `policyUsage` |
| `src/organization/libraries/storage/LibOrganizationRecoveryStorage.sol` | `den.mls-wallet.organization.recovery` | `txRecovery`, `guardianRecovery` (expanded field coverage listed below) |
| `src/organization/libraries/storage/LibOrganizationSignaturesStorage.sol` | `den.mls-wallet.organization.signatures` | `usedNonces` |
| `src/organization/libraries/storage/LibOrganizationUpgradeStorage.sol` | `den.mls-wallet.organization.upgrade` | `whitelistAddress`, `isUpgradeAuthorized` |
| `src/implementation-whitelist/libraries/storage/LibImplementationWhitelistStorage.sol` | `den.mls-wallet.implementation-whitelist.main` | `whitelisted` |

Recovery nested-field coverage (must be explicit):
- `txRecovery.recoveryAddress`
- `txRecovery.isEnabled`
- `txRecovery.timelockDurationSeconds`
- `txRecovery.pendingEnableTimestamp`
- `txRecovery.pendingInit.pendingRecoveryAddress`
- `txRecovery.pendingInit.pendingTimelockDurationSeconds`
- `txRecovery.pendingInit.pendingTimestamp`
- `guardianRecovery.recoveryAddress`
- `guardianRecovery.isUpdateReadyForAcceptance`
- `guardianRecovery.pendingGuardian`
- `guardianRecovery.timelockDurationSeconds`
- `guardianRecovery.pendingGuardianTimestamp`
- `guardianRecovery.pendingInit.pendingRecoveryAddress`
- `guardianRecovery.pendingInit.pendingTimelockDurationSeconds`
- `guardianRecovery.pendingInit.pendingTimestamp`

---

## 2. Slot-Level Coverage (Library Complete)

`test/ERC7201StorageSlots.t.sol` already checks all 12 in-scope ERC-7201 namespaces for:
- exact slot constant match (`cast index-erc7201` formula)
- uniqueness across all in-scope slots
- ERC-7201 low-byte alignment (`...00`)

Additional slot-collision tests to add in `test/StorageLayout.t.sol`:
- No in-scope ERC-7201 slot collides with ERC-1967 implementation slot
- No in-scope ERC-7201 slot collides with ERC-1967 admin slot
- No in-scope ERC-7201 slot collides with ERC-1967 beacon slot
- No in-scope ERC-7201 slot collides with OpenZeppelin `Initializable` namespace
- No in-scope ERC-7201 slot collides with OpenZeppelin `OwnableUpgradeable` namespace

---

## 3. Variable-Level Read/Write Coverage (All Variables)

Add variable-level tests in `test/StorageLayout.t.sol` so each variable above is touched at least once (set + get assertion).

| # | Test Case | Type | Priority |
|---|---|---|---|
| 1 | `LibImplementationWhitelistStorage.whitelisted` read/write for multiple `ContractType` + implementation address pairs | [U] | P1 |
| 2 | `LibOrganizationAccountFactoryStorage.deployedAccounts` and `.accountImplementation` read/write | [U] | P1 |
| 3 | `LibOrganizationAdminOperationTimelockStorage.adminOperationTimelockDurationSeconds` read/write | [U] | P1 |
| 4 | `LibOrganizationAdminStorage.isAdmin` mapping read/write + `.adminCount` + `.votingThreshold` scalar reads/writes | [U] | P1 |
| 5 | `LibOrganizationDeployerAddressStorage.deployerAddress` read/write | [U] | P1 |
| 6 | `LibOrganizationGroupsStorage.isGroup`, `.isGroupMember`, `.wasGroupDeleted` read/write and independence checks | [U] | P1 |
| 7 | `LibOrganizationGuardianStorage.guardian`, `.isGuardianUpdateReadyForAcceptance`, `.pendingGuardian`, `.pendingGuardianUpdateTimestamp` read/write | [U] | P1 |
| 8 | `LibOrganizationMembersStorage.isMember` read/write | [U] | P1 |
| 9 | `LibOrganizationPolicyStorage.policiesRoot` and `.policyUsage` nested mapping read/write | [U] | P1 |
| 10 | `LibOrganizationSignaturesStorage.usedNonces` mapping read/write | [U] | P1 |
| 11 | `LibOrganizationUpgradeStorage.whitelistAddress` and `.isUpgradeAuthorized` read/write | [U] | P1 |
| 12 | `LibOrganizationRecoveryStorage.txRecovery` nested field read/write for all 7 subfields | [U] | P1 |
| 13 | `LibOrganizationRecoveryStorage.guardianRecovery` nested field read/write for all 8 subfields | [U] | P1 |

---

## 4. Namespace Isolation and Regression Tests

| # | Test Case | Type | Priority |
|---|---|---|---|
| 14 | Writes in one namespace do not change values in any other namespace | [U] | P1 |
| 15 | Writes to mappings in one namespace do not affect scalar fields in another namespace | [U] | P1 |
| 16 | Mixed writes across all 12 namespaces preserve all previously written values | [U] | P1 |
| 17 | Storage values persist across multiple `DELEGATECALL` transactions | [I] | P1 |
| 18 | Storage values survive UUPS implementation upgrade | [I] | P1 |

---

## 5. Fuzz and Invariant Coverage

| # | Test Case | Type | Priority |
|---|---|---|---|
| 19 | Fuzz mixed write/read operations across all namespaces and assert deterministic retrieval | [F] | P1 |
| 20 | Fuzz mapping keys/values for `isAdmin`, `isMember`, `isGroupMember`, `policyUsage`, `usedNonces`, `whitelisted` | [F] | P1 |
| 21 | Invariant: no namespace collisions with ERC-1967 slots | [I] | P1 |
| 22 | Invariant: namespace writes are isolated (no cross-namespace mutation) | [I] | P1 |

---

## 6. Account Beacon Storage Helper Coverage (Non-ERC7201)

| # | Test Case | Type | Priority |
|---|---|---|---|
| 23 | `LibAccountOrganizationAddressStorage.getOrganizationAddress()` returns the current ERC-1967 beacon address (organization address) | [U] | P1 |

---

## Summary

| Category | New Tests | Priority |
|---|---|---|
| Variable-level layout coverage (all libraries, all variables) | 13 | P1 |
| Namespace isolation and proxy persistence | 5 | P1 |
| Fuzz/invariant | 4 | P1 |
| Account beacon storage helper coverage | 1 | P1 |
| **Total New** | **23** | |
