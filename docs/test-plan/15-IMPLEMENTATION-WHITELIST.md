# 15 — Implementation Whitelist Controls Test Plan

**Files Under Test:**
- `src/implementation-whitelist/ImplementationWhitelistImplementation.sol`
- `src/implementation-whitelist/ImplementationWhitelistProxy.sol`
- `src/organization/OrganizationFactory.sol` (whitelist enforcement path)
- `src/organization/OrganizationProxy.sol` (whitelist wiring into org storage)
- `src/organization/OrganizationImplementation.sol` (organization upgrade whitelist gate)
- `src/organization/base/OrganizationAccountFactoryBase.sol` (account upgrade whitelist gate)

**Out of Scope for This Plan (tested elsewhere):**
- `src/interfaces/IImplementationWhitelist.sol`
- `src/implementation-whitelist/libraries/storage/LibImplementationWhitelistStorage.sol`

**Harness Strategy (Private Functions):**
- For this plan, helper functions currently marked `private` are changed to `internal` in test-only builds and exposed via harness contracts for direct unit testing.

---

## 1. File: `ImplementationWhitelistImplementation.sol`

### 1.1 `constructor`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Constructor disables initializers on implementation contract (`_disableInitializers`) | [S] | P1 |
| 2 | Direct call to `initialize` on implementation contract (not proxy) reverts | [N] | P1 |

### 1.2 `initialize`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 3 | Fresh proxy state: `isInitialized()` returns false before `initialize` | [U] | P2 |
| 4 | Valid `initialize(initialOwner, orgImpls, accountImpls)` succeeds | [U] | P1 |
| 5 | Owner set to `initialOwner` after init | [U] | P1 |
| 6 | Organization implementation list is whitelisted on init | [U] | P1 |
| 7 | Account implementation list is whitelisted on init | [U] | P1 |
| 8 | Same address can be independently whitelisted under both `ContractType.Organization` and `ContractType.Account` | [U] | P1 |
| 9 | Emits `ImplementationWhitelisted` for each organization implementation in init array | [EV] | P2 |
| 10 | Emits `ImplementationWhitelisted` for each account implementation in init array | [EV] | P2 |
| 11 | Emits `ImplementationWhitelistInitialized(initialOwner)` | [EV] | P1 |
| 12 | Empty organization/account arrays: initialize still succeeds and sets owner | [E] | P2 |
| 13 | `initialOwner == address(0)` reverts | [N] | P0 |
| 14 | Second initialization attempt reverts (initializer guard) | [N] | P0 |
| 15 | [DESIRED] Init rejects `address(0)` implementation entries | [N] | P0 |
| 16 | [DESIRED] Init rejects implementation entries with no code (EOA/non-contract) | [S] | P0 |

### 1.3 `whitelistImplementations`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 17 | Only owner can call `whitelistImplementations` | [N] | P0 |
| 18 | Pending owner cannot call before `acceptOwnership` | [N] | P1 |
| 19 | After `acceptOwnership`, new owner can call and old owner cannot | [S] | P1 |
| 20 | Add organization implementation sets whitelist to true | [U] | P1 |
| 21 | Add account implementation sets whitelist to true | [U] | P1 |
| 22 | Remove implementation sets whitelist to false | [U] | P1 |
| 23 | Same address in `toWhitelist` and `toUnwhitelist` in one call results in net unwhitelisted (add then remove order) | [E] | P2 |
| 24 | Duplicate addresses in `toWhitelist` are idempotent at state level (remains true) | [E] | P2 |
| 25 | Duplicate addresses in `toUnwhitelist` are idempotent at state level (remains false) | [E] | P2 |
| 26 | Empty arrays (`toWhitelist=[]`, `toUnwhitelist=[]`) are no-op and do not revert | [E] | P2 |
| 27 | Emits `ImplementationWhitelisted` with correct type/address for each added entry | [EV] | P2 |
| 28 | Emits `ImplementationUnwhitelisted` with correct type/address for each removed entry | [EV] | P2 |
| 29 | Type isolation: changing one `ContractType` does not modify the other mapping | [U] | P1 |
| 30 | [DESIRED] Reject `address(0)` in `toWhitelist` | [N] | P0 |
| 31 | [DESIRED] Reject no-code addresses in `toWhitelist` | [S] | P0 |

### 1.4 `isInitialized`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 32 | Returns false before initialization | [U] | P2 |
| 33 | Returns true after successful initialization | [U] | P1 |
| 34 | Remains true after ownership transfer (`transferOwnership` + `acceptOwnership`) | [U] | P1 |
| 35 | [DESIRED] Initialization state should be permanent (`false -> true` only once; no return to false) | [INV] | P0 |

### 1.5 `isImplementationWhitelisted`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 36 | Returns true for whitelisted address under correct `ContractType` | [U] | P1 |
| 37 | Returns false for never-whitelisted address | [U] | P1 |
| 38 | Returns false when address is whitelisted for the other `ContractType` only | [U] | P1 |
| 39 | Returns false for all addresses before initialization | [U] | P2 |

### 1.6 `validateIsImplementationWhitelistedOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 40 | Succeeds for whitelisted address + matching `ContractType` | [U] | P1 |
| 41 | Reverts `ImplementationNotWhitelisted(implementation)` for non-whitelisted address | [N] | P0 |
| 42 | Reverts when whitelisted under wrong `ContractType` | [N] | P0 |
| 43 | Revert payload includes the exact rejected implementation address | [U] | P1 |

### 1.7 `_authorizeUpgrade` (tested through proxy `upgradeToAndCall`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 44 | Owner can upgrade whitelist proxy to valid UUPS implementation | [I] | P1 |
| 45 | Non-owner cannot upgrade whitelist proxy | [N] | P0 |
| 46 | Upgrade preserves whitelist state for both contract types | [I] | P1 |
| 47 | Upgrade preserves ownership state | [I] | P1 |
| 48 | Upgrade with post-upgrade calldata executes successfully | [I] | P1 |
| 49 | Upgrade to non-UUPS/no-code implementation reverts | [N] | P0 |

### 1.8 Private Helpers (`_addToWhitelist`, `_removeFromWhitelist`)

> **Prerequisite for private-function tests:** convert these functions from `private` to `internal` in test builds and expose wrappers through a harness contract.

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 50 | `_addToWhitelist`: single entry sets `whitelisted[type][addr] = true` | [U] | P2 |
| 51 | `_addToWhitelist`: multiple entries all become true | [U] | P2 |
| 52 | `_addToWhitelist`: empty array is no-op | [E] | P2 |
| 53 | `_addToWhitelist`: type independence preserved | [U] | P2 |
| 54 | `_addToWhitelist`: emits `ImplementationWhitelisted` per processed element | [EV] | P2 |
| 55 | [DESIRED] `_addToWhitelist`: reject `address(0)` | [N] | P0 |
| 56 | [DESIRED] `_addToWhitelist`: reject no-code addresses | [S] | P0 |
| 57 | `_removeFromWhitelist`: whitelisted entry becomes false | [U] | P2 |
| 58 | `_removeFromWhitelist`: non-whitelisted entry stays false (idempotent) | [E] | P2 |
| 59 | `_removeFromWhitelist`: type independence preserved (removing under one `ContractType` does not affect the other mapping) | [U] | P2 |
| 60 | `_removeFromWhitelist`: empty array is no-op | [E] | P2 |
| 61 | `_removeFromWhitelist`: emits `ImplementationUnwhitelisted` per processed element | [EV] | P2 |

---

## 2. File: `ImplementationWhitelistProxy.sol`

### 2.1 `constructor`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 62 | Deploying proxy with valid `initData` initializes owner + initial implementation lists atomically | [I] | P1 |
| 63 | Deploying proxy with `implementation == address(0)` reverts | [N] | P0 |
| 64 | Deploying proxy with implementation address that has no code reverts | [N] | P0 |
| 65 | Invalid/malformed `initData` causes constructor deployment revert | [N] | P1 |
| 66 | If delegated `initialize` reverts, proxy deployment reverts atomically | [S] | P1 |
| 67 | Implementation slot points to provided implementation address after deploy | [U] | P2 |
| 68 | Proxy delegates calls to implementation correctly (read path and write path) | [I] | P1 |
| 69 | [DESIRED] Empty `initData` deployment should revert to prevent uninitialized proxy takeover | [S] | P0 |

---

## 3. File: `OrganizationFactory.sol` (Whitelist Enforcement on Organization Deploy)

### 3.1 `deployOrganization`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 70 | Rejects caller that is not `DEPLOYER_ADDRESS` | [N] | P0 |
| 71 | Rejects deployment when organization implementation is not whitelisted | [N] | P0 |
| 72 | Rejects deployment when implementation is whitelisted only under `ContractType.Account` | [N] | P0 |
| 73 | Deployment succeeds when implementation is whitelisted under `ContractType.Organization` | [I] | P1 |
| 74 | Emits `OrganizationDeployed(organizationAddress, salt, DEPLOYER_ADDRESS)` with correct values on successful deployment | [EV] | P1 |
| 75 | If whitelist call reverts (bad whitelist contract), deployment reverts | [N] | P0 |
| 76 | `whitelistAddress == address(0)` causes deployment revert | [N] | P0 |
| 77 | Whitelist check failure occurs before proxy deployment side effects (no deployed contract, no event) | [S] | P0 |
| 78 | Deployed Organization proxy stores the exact `whitelistAddress` and `implementationAddress` passed to factory | [I] | P1 |
| 79 | [DESIRED] Reject implementation targets with no code, even if whitelist contract is permissive/malicious | [S] | P0 |
| 80 | [DESIRED] Reject `implementationAddress == address(0)` explicitly | [N] | P0 |
| 81 | If organization initialization fails after deploy, tx reverts atomically and no uninitialized org remains deployed | [S] | P0 |
| 81.2 | If organization initialization fails after deploy, can still redeploy organization at same address using same create2 inputs, but with different (valid) initialization data | [S] | P0 |
| 82 | Same `(salt, implementationAddress, whitelistAddress)` cannot be deployed twice (CREATE2 collision) | [N] | P1 |

### 3.2 `computeOrganizationAddress`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 83 | Deterministic output for same `(salt, implementationAddress, whitelistAddress)` | [U] | P1 |
| 84 | Changing `salt` changes computed address | [U] | P1 |
| 85 | Changing `whitelistAddress` changes computed address | [U] | P1 |
| 86 | Changing `implementationAddress` changes computed address | [U] | P1 |
| 87 | Computed address matches actual deployed address when deployment succeeds | [U] | P1 |

### 3.3 `_getOrganizationProxyBytecode` (private)

> **Prerequisite for private-function tests:** convert to `internal` in test builds and expose via harness.

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 88 | Encodes `OrganizationProxy` creation code with constructor args `(implementationAddress, whitelistAddress)` | [U] | P2 |
| 89 | Deterministic for same inputs | [U] | P2 |
| 90 | Changing `whitelistAddress` changes bytecode hash | [U] | P1 |
| 91 | Changing `implementationAddress` changes bytecode hash | [U] | P1 |

---

## 4. File: `OrganizationProxy.sol` (Whitelist Address Wiring)

### 4.1 `constructor`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 92 | Constructor stores `whitelistAddress` in upgrade storage slot used by org/account upgrade flows | [U] | P1 |
| 93 | Organization upgrade path reads the stored whitelist address (not caller-supplied address) | [I] | P1 |
| 94 | [DESIRED] Constructor should reject `whitelistAddress == address(0)` | [N] | P0 |

---

## 5. File: `OrganizationImplementation.sol` (Whitelist Enforcement on Organization UUPS Upgrades)

### 5.1 `upgradeToAndCallWithAuthorization`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 95 | Non-whitelisted organization implementation is rejected | [N] | P0 |
| 96 | Implementation whitelisted only as `Account` is rejected | [N] | P0 |
| 97 | Whitelisted organization implementation with valid auth upgrades successfully | [I] | P1 |
| 98 | Whitelist-call failure causes upgrade revert and implementation remains unchanged | [S] | P0 |
| 99 | If stored whitelist address is invalid/no-code, upgrade reverts | [N] | P0 |
| 100 | Whitelist validation executes before setting `isUpgradeAuthorized` (no external window with flag=true pre-validation) | [S] | P0 |
| 101 | Failed whitelist validation does not leave `isUpgradeAuthorized` stuck true | [S] | P0 |
| 102 | Successful upgrade resets `isUpgradeAuthorized` back to false | [S] | P0 |
| 103 | Failed upgrade execution (e.g., bad `data`) does not leave auth flag stuck true (tx rollback) | [S] | P0 |
| 104 | Direct call to inherited `upgradeToAndCall` bypassing auth flow reverts `UnauthorizedUpgrade` | [S] | P0 |
| 105 | Upgrade `data` payload executes only on successful whitelisted upgrade | [I] | P1 |
| 106 | [DESIRED] Admin authorization must bind migration `data` payload in addition to `newImplementation` | [S] | P0 |
| 107 | [DESIRED] Migration `data` cannot trigger unauthorized nested second upgrade that bypasses whitelist/admin checks | [S] | P0 |
| 108 | [DESIRED] Reject new implementation with no code even if whitelist contract returns true | [S] | P0 |
| 109 | [DESIRED] Reject `newImplementation == address(0)` explicitly | [N] | P0 |

### 5.2 `_authorizeUpgrade` (internal hook)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 110 | Reverts `UnauthorizedUpgrade` when authorization flag is false | [N] | P0 |
| 111 | Succeeds when flag is true (called via authorized flow) | [U] | P1 |
| 112 | Behavior is flag-based rather than parameter-based (`newImplementation` not re-validated here) | [S] | P1 |

---

## 6. File: `OrganizationAccountFactoryBase.sol` (Whitelist Enforcement on Account Beacon Upgrades)

### 6.1 `setAccountImplementation`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 113 | Non-guardian caller reverts (onlyGuardian) | [N] | P0 |
| 114 | Admin signatures for a different `newImplementation` cannot authorize this call (operationData binding) | [S] | P0 |
| 115 | Non-whitelisted account implementation is rejected | [N] | P0 |
| 116 | Implementation whitelisted only as `Organization` is rejected | [N] | P0 |
| 117 | Whitelisted account implementation updates beacon implementation storage | [U] | P1 |
| 118 | Emits `AccountImplementationUpdated(newImplementation)` on success | [EV] | P1 |
| 119 | Whitelist-call failure reverts and does not update implementation state | [S] | P0 |
| 120 | Invalid/no-code whitelist contract address causes revert | [N] | P0 |
| 121 | [DESIRED] Reject account implementation with no code even if whitelist contract returns true | [S] | P0 |
| 122 | [DESIRED] Reject `newImplementation == address(0)` explicitly | [N] | P0 |

---

## 7. Cross-File Integration Tests (Whitelist Controls End-to-End)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 123 | Unwhitelisted implementation cannot be used in any entrypoint: org deploy, org upgrade, account upgrade | [I] | P0 |
| 124 | Type separation end-to-end: `Account` whitelist never unlocks org deploy/upgrade, and vice versa | [I] | P0 |
| 125 | Unwhitelisting an implementation blocks future use when but does not break already-deployed contracts currently running it for both Organization and Account contracts | [I] | P1 |
| 126 | Re-whitelisting previously removed implementation re-enables eligible flows | [I] | P1 |
| 127 | Upgrading the whitelist contract preserves existing whitelist state and enforcement behavior in factory/org/account flows | [I] | P1 |
| 128 | Ownership transfer of whitelist contract immediately changes who can alter allowed implementations system-wide | [I] | P1 |
| 129 | Malicious/buggy whitelist contract behavior (revert/false positives) cannot bypass desired no-code-address protections | [S] | P0 |
| 130 | Deployment path remains atomic with whitelist validation + initialization (no partial state exposure) | [S] | P0 |

---

## 8. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 131 | Fuzz random unwhitelisted addresses: always rejected by all three enforcement entrypoints | [F] | P0 |
| 132 | Fuzz add/remove sequences per `ContractType`: onchain state matches reference model mapping | [F] | P1 |
| 133 | Fuzz mixed `Account`/`Organization` operations: mappings remain independent | [F] | P1 |
| 134 | Fuzz `(salt, implementation, whitelist)` tuples: `computeOrganizationAddress` remains deterministic and sensitivity-preserving | [F] | P1 |
| 135 | [DESIRED] Fuzz zero/no-code implementation addresses: always rejected as valid implementations | [F] | P0 |
| 136 | [DESIRED] Fuzz org-upgrade migration calldata: nested second-upgrade bypass attempts always fail | [F] | P0 |
| 137 | Fuzz proxy initialization inputs: malformed init data never leaves partially initialized whitelist proxy | [F] | P1 |

---

## 9. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 138 | **Owner exclusivity:** Only current whitelist owner can mutate whitelist entries | P0 |
| 139 | **Global whitelist enforcement:** No unwhitelisted implementation can become active via org deploy/org upgrade/account upgrade | P0 |
| 140 | **Type independence:** `Account` and `Organization` whitelist mappings never alias or cross-enable | P0 |
| 141 | **Upgrade auth flag safety:** `isUpgradeAuthorized` is false outside authorized org-upgrade execution window | P0 |
| 142 | **[DESIRED] Org whitelist-pointer immutability:** stored org `whitelistAddress` used for upgrades does not change after proxy construction | P1 |
| 143 | **Whitelist state continuity across whitelist upgrades:** Whitelist data is preserved after whitelist UUPS upgrade | P1 |
| 144 | **[DESIRED] Initialization permanence:** Whitelist initialized state is monotonic (`false -> true` only once) | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `ImplementationWhitelistImplementation.sol` | 61 | P0-P2 |
| `ImplementationWhitelistProxy.sol` | 8 | P0-P2 |
| `OrganizationFactory.sol` | 22 | P0-P2 |
| `OrganizationProxy.sol` | 3 | P0-P1 |
| `OrganizationImplementation.sol` | 18 | P0-P1 |
| `OrganizationAccountFactoryBase.sol` | 10 | P0-P1 |
| Cross-file integration | 8 | P0-P1 |
| Fuzz tests | 7 | P0-P1 |
| Invariant tests | 7 | P0-P1 |
| **Total** | **144** | |
