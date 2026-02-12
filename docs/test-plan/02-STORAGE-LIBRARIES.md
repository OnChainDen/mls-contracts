# 02 — Storage Libraries Test Plan

**Files Under Test:**
- `src/organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol`
- `src/organization/libraries/storage/LibOrganizationAdminStorage.sol`
- `src/organization/libraries/storage/LibOrganizationAdminOperationTimelockStorage.sol`
- `src/organization/libraries/storage/LibOrganizationDeployerAddressStorage.sol`
- `src/organization/libraries/storage/LibOrganizationGroupsStorage.sol`
- `src/organization/libraries/storage/LibOrganizationGuardianStorage.sol`
- `src/organization/libraries/storage/LibOrganizationMembersStorage.sol`
- `src/organization/libraries/storage/LibOrganizationPolicyStorage.sol`
- `src/organization/libraries/storage/LibOrganizationRecoveryStorage.sol`
- `src/organization/libraries/storage/LibOrganizationSignaturesStorage.sol`
- `src/organization/libraries/storage/LibOrganizationUpgradeStorage.sol`
- `src/account/libraries/storage/LibAccountOrganizationAddressStorage.sol`
- `src/implementation-whitelist/libraries/storage/LibImplementationWhitelistStorage.sol`

**Existing Tests:** `test/ERC7201StorageSlots.t.sol` (14 tests — storage slot validation only)

**Test File(s):** Existing `test/ERC7201StorageSlots.t.sol` + `test/StorageLayout.t.sol`

---

## 1. ERC-7201 Slot Validation (Already Tested — Gap Analysis)

The existing `ERC7201StorageSlots.t.sol` verifies:
- Each storage slot matches `cast index-erc7201` computation
- All slots are unique
- All slots end with `0x00` byte

**Gaps to fill:**

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Account storage slot (`LibAccountOrganizationAddressStorage`) does not collide with organization slots | [U] | P1 |
| 2 | Whitelist storage slot does not collide with organization or account slots | [U] | P1 |

---

## 2. Storage Layout Tests

These tests verify that ERC-7201 namespaced storage does not collide with proxy storage slots or other contract state.

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 3 | No storage slot collides with ERC-1967 implementation slot | [U] | P1 |
| 4 | No storage slot collides with ERC-1967 beacon slot | [U] | P1 |
| 5 | No storage slot collides with ERC-1967 admin slot | [U] | P1 |
| 6 | No storage slot collides with Initializable storage slot | [U] | P1 |
| 7 | No storage slot collides with OwnableUpgradeable storage slot | [U] | P1 |

---

## 3. Storage Isolation Tests (Proxy Context)

These tests verify that storage libraries work correctly when called through a proxy (UUPS or Beacon).

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 8 | Organization storage accessible through UUPS proxy | [I] | P1 |
| 9 | Account storage accessible through BeaconProxy | [I] | P1 |
| 10 | Writing to one storage namespace does not affect another | [U] | P1 |
| 11 | Storage persists across multiple DELEGATECALL transactions | [I] | P1 |
| 12 | Storage survives implementation upgrade (UUPS) | [I] | P1 |

---

## 4. Storage Struct Layout Compatibility

These tests verify that the storage struct layout is compatible with the ERC-7201 pattern after the Merkle-to-mapping refactor.

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 13 | Admin storage: `isAdmin` mapping writes/reads correctly at computed slot | [U] | P2 |
| 14 | Admin storage: `adminCount` and `votingThreshold` accessible after mapping | [U] | P2 |
| 15 | Members storage: `isMember` mapping writes/reads correctly | [U] | P2 |
| 16 | Groups storage: nested `isGroupMember` mapping works (groupId => address => bool) | [U] | P2 |
| 17 | Groups storage: `wasGroupDeleted` mapping independent from `isGroup` | [U] | P2 |
| 18 | Policy storage: `policyUsage` nested mapping (bytes32 => uint256 => uint256) works | [U] | P2 |
| 19 | Recovery storage: `TxRecoveryState` and `GuardianRecoveryState` structs both accessible | [U] | P2 |

---

## 5. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 20 | Fuzz: Random namespace strings produce unique ERC-7201 storage locations | [F] | P1 |
| 21 | Fuzz: Random write/read sequences to namespaced storage slots preserve data integrity | [F] | P1 |
| 22 | Fuzz: Random proxy delegate call sequences preserve namespaced storage values | [F] | P1 |

---

## 6. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 23 | **No slot collision**: ERC-7201 storage slots never collide with ERC-1967 proxy standard slots | P1 |
| 24 | **Namespace isolation**: Writing to one ERC-7201 namespace never affects values in another namespace | P1 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Slot collision (cross-contract) | 2 | P1 |
| Proxy storage slot collision | 5 | P1 |
| Storage isolation (proxy context) | 5 | P1 |
| Storage struct layout | 7 | P2 |
| Fuzz tests | 3 | P1 |
| Invariant tests | 2 | P1 |
| **Total** | **24** | |
