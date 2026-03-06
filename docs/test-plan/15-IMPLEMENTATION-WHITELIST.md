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

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-CON-1 | Constructor disables initializers on implementation contract (`_disableInitializers`) | [S] | P1 |
| IWI-CON-2 | Direct call to `initialize` on implementation contract (not proxy) reverts | [N] | P1 |

### 1.2 `initialize`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-INIT-1 | Fresh proxy state: `isInitialized()` returns false before `initialize` | [U] | P2 |
| IWI-INIT-2 | Valid `initialize(initialOwner, orgImpls, accountImpls)` succeeds | [U] | P1 |
| IWI-INIT-3 | Owner set to `initialOwner` after init | [U] | P1 |
| IWI-INIT-4 | Organization implementation list is whitelisted on init | [U] | P1 |
| IWI-INIT-5 | Account implementation list is whitelisted on init | [U] | P1 |
| IWI-INIT-6 | Same address can be independently whitelisted under both `ContractType.Organization` and `ContractType.Account` | [U] | P1 |
| IWI-INIT-7 | Emits `ImplementationWhitelisted` for each organization implementation in init array | [EV] | P2 |
| IWI-INIT-8 | Emits `ImplementationWhitelisted` for each account implementation in init array | [EV] | P2 |
| IWI-INIT-9 | Emits `ImplementationWhitelistInitialized(initialOwner)` | [EV] | P1 |
| IWI-INIT-10 | Empty organization/account arrays: initialize still succeeds and sets owner | [E] | P2 |
| IWI-INIT-11 | `initialOwner == address(0)` reverts | [N] | P0 |
| IWI-INIT-12 | Second initialization attempt reverts (initializer guard) | [N] | P0 |

### 1.3 `whitelistImplementations`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-WI-1 | Only owner can call `whitelistImplementations` | [N] | P0 |
| IWI-WI-2 | Pending owner cannot call before `acceptOwnership` | [N] | P1 |
| IWI-WI-3 | After `acceptOwnership`, new owner can call and old owner cannot | [S] | P1 |
| IWI-WI-4 | Add organization implementation sets whitelist to true | [U] | P1 |
| IWI-WI-5 | Add account implementation sets whitelist to true | [U] | P1 |
| IWI-WI-6 | Remove implementation sets whitelist to false | [U] | P1 |
| IWI-WI-7 | Same address in `toWhitelist` and `toUnwhitelist` in one call results in net unwhitelisted (add then remove order) | [E] | P2 |
| IWI-WI-8 | Duplicate addresses in `toWhitelist` are idempotent at state level (remains true) | [E] | P2 |
| IWI-WI-9 | Duplicate addresses in `toUnwhitelist` are idempotent at state level (remains false) | [E] | P2 |
| IWI-WI-10 | Empty arrays (`toWhitelist=[]`, `toUnwhitelist=[]`) are no-op and do not revert | [E] | P2 |
| IWI-WI-11 | Emits `ImplementationWhitelisted` with correct type/address for each added entry | [EV] | P2 |
| IWI-WI-12 | Emits `ImplementationUnwhitelisted` with correct type/address for each removed entry | [EV] | P2 |
| IWI-WI-13 | Type isolation: changing one `ContractType` does not modify the other mapping | [U] | P1 |

### 1.4 `isInitialized`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-ISI-1 | Returns false before initialization | [U] | P2 |
| IWI-ISI-2 | Returns true after successful initialization | [U] | P1 |
| IWI-ISI-3 | Remains true after ownership transfer (`transferOwnership` + `acceptOwnership`) | [U] | P1 |
| IWI-ISI-4 | [DESIRED] Initialization state should be permanent (`false -> true` only once; no return to false) | [INV] | P0 |

### 1.5 `isImplementationWhitelisted`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-IIW-1 | Returns true for whitelisted address under correct `ContractType` | [U] | P1 |
| IWI-IIW-2 | Returns false for never-whitelisted address | [U] | P1 |
| IWI-IIW-3 | Returns false when address is whitelisted for the other `ContractType` only | [U] | P1 |
| IWI-IIW-4 | Returns false for all addresses before initialization | [U] | P2 |
| IWI-IIW-5 | Returns false addresses that were added to the whitelist, then later removed from the whitelist | [U] | P2 |

### 1.6 `validateIsImplementationWhitelistedOrRevert`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-VIIWOR-1 | Succeeds for whitelisted address + matching `ContractType` | [U] | P1 |
| IWI-VIIWOR-2 | Reverts `ImplementationNotWhitelisted(implementation)` for non-whitelisted address | [N] | P0 |
| IWI-VIIWOR-3 | Reverts `ImplementationNotWhitelisted(implementation)` for address that were added to the whitelist, and then later removed from the whitelist | [N] | P0 |
| IWI-VIIWOR-4 | Reverts when whitelisted under wrong `ContractType` | [N] | P0 |
| IWI-VIIWOR-5 | Revert payload includes the exact rejected implementation address | [U] | P1 |

### 1.7 `_authorizeUpgrade` (tested through proxy `upgradeToAndCall`)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-AU-1 | Owner can upgrade whitelist proxy to valid UUPS implementation | [I] | P1 |
| IWI-AU-2 | Non-owner cannot upgrade whitelist proxy | [N] | P0 |
| IWI-AU-3 | Upgrade preserves whitelist state for both contract types, even in the case of multiple sequential upgrades | [I] | P1 |
| IWI-AU-4 | Upgrade preserves ownership state | [I] | P1 |
| IWI-AU-5 | Upgrade with post-upgrade calldata executes successfully | [I] | P1 |
| IWI-AU-6 | Upgrade to no-code implementation reverts | [N] | P0 |

### 1.8 Private Helpers (`_addToWhitelist`, `_removeFromWhitelist`)

> **Prerequisite for private-function tests:** convert these functions from `private` to `internal` in test builds and expose wrappers through a harness contract.

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-HELP-1 | `_addToWhitelist`: single entry sets `whitelisted[type][addr] = true` | [U] | P2 |
| IWI-HELP-2 | `_addToWhitelist`: multiple entries all become true | [U] | P2 |
| IWI-HELP-3 | `_addToWhitelist`: empty array is no-op | [E] | P2 |
| IWI-HELP-4 | `_addToWhitelist`: type independence preserved | [U] | P2 |
| IWI-HELP-5 | `_addToWhitelist`: emits `ImplementationWhitelisted` per processed element | [EV] | P2 |
| IWI-HELP-6 | `_removeFromWhitelist`: whitelisted entry becomes false | [U] | P2 |
| IWI-HELP-7 | `_removeFromWhitelist`: non-whitelisted entry stays false (idempotent) | [E] | P2 |
| IWI-HELP-8 | `_removeFromWhitelist`: type independence preserved (removing under one `ContractType` does not affect the other mapping) | [U] | P2 |
| IWI-HELP-9 | `_removeFromWhitelist`: empty array is no-op | [E] | P2 |
| IWI-HELP-10 | `_removeFromWhitelist`: emits `ImplementationUnwhitelisted` per processed element | [EV] | P2 |

---

## 2. File: `ImplementationWhitelistProxy.sol`

### 2.1 `constructor`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWP-CON-1 | Deploying proxy with valid `initData` initializes owner + initial implementation lists atomically | [I] | P1 |
| IWP-CON-2 | Deploying proxy with `implementation == address(0)` reverts | [N] | P0 |
| IWP-CON-3 | Deploying proxy with implementation address that has no code reverts | [N] | P0 |
| IWP-CON-4 | Invalid/malformed `initData` causes constructor deployment revert | [N] | P1 |
| IWP-CON-5 | If delegated `initialize` reverts, proxy deployment reverts atomically | [S] | P1 |
| IWP-CON-6 | Implementation slot points to provided implementation address after deploy | [U] | P2 |
| IWP-CON-7 | Proxy delegates calls to implementation correctly (read path and write path) | [I] | P1 |
| IWP-CON-8 | [DESIRED] Empty `initData` deployment should revert to prevent uninitialized proxy takeover | [S] | P0 |

---

## 3. File: `OrganizationFactory.sol` (Whitelist Enforcement on Organization Deploy)

### 3.1 `deployOrganization`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OF-DO-1 | Rejects caller that is not `DEPLOYER_ADDRESS` | [N] | P0 |
| OF-DO-2 | Rejects deployment when organization implementation is not whitelisted | [N] | P0 |
| OF-DO-3 | Rejects deployment when implementation is whitelisted only under `ContractType.Account` | [N] | P0 |
| OF-DO-4 | Deployment succeeds when implementation is whitelisted under `ContractType.Organization` | [I] | P1 |
| OF-DO-5 | Emits `OrganizationDeployed(organizationAddress, salt, DEPLOYER_ADDRESS)` with correct values on successful deployment | [EV] | P1 |
| OF-DO-6 | If whitelist call reverts (bad whitelist contract), deployment reverts | [N] | P0 |
| OF-DO-7 | `whitelistAddress == address(0)` causes deployment revert | [N] | P0 |
| OF-DO-8 | Whitelist check failure occurs before proxy deployment side effects (no deployed contract, no event) | [S] | P0 |
| OF-DO-9 | Deployed Organization proxy stores the exact `whitelistAddress` and `implementationAddress` passed to factory | [I] | P1 |
| OF-DO-10 | [DESIRED] Reject implementation targets with no code, even if whitelist contract is permissive/malicious | [S] | P0 |
| OF-DO-11 | [DESIRED] Reject `implementationAddress == address(0)` explicitly | [N] | P0 |
| OF-DO-12 | If organization initialization fails after deploy, tx reverts atomically and no uninitialized org remains deployed | [S] | P0 |
| OF-DO-13 | If organization initialization fails after deploy, can still redeploy organization at same address using same create2 inputs, but with different (valid) initialization data | [S] | P0 |
| OF-DO-14 | Same `(salt, implementationAddress, whitelistAddress)` cannot be deployed twice (CREATE2 collision) | [N] | P1 |

### 3.2 `computeOrganizationAddress`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OF-COA-1 | Deterministic output for same `(salt, implementationAddress, whitelistAddress)` | [U] | P1 |
| OF-COA-2 | Changing `salt` changes computed address | [U] | P1 |
| OF-COA-3 | Changing `whitelistAddress` changes computed address | [U] | P1 |
| OF-COA-4 | Changing `implementationAddress` changes computed address | [U] | P1 |
| OF-COA-5 | Computed address matches actual deployed address when deployment succeeds | [U] | P1 |

### 3.3 `_getOrganizationProxyBytecode` (private)

> **Prerequisite for private-function tests:** convert to `internal` in test builds and expose via harness.

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OF-GOPB-1 | Encodes `OrganizationProxy` creation code with constructor args `(implementationAddress, whitelistAddress)` | [U] | P2 |
| OF-GOPB-2 | Deterministic for same inputs | [U] | P2 |
| OF-GOPB-3 | Changing `whitelistAddress` changes bytecode hash | [U] | P1 |
| OF-GOPB-4 | Changing `implementationAddress` changes bytecode hash | [U] | P1 |

---

## 4. File: `OrganizationProxy.sol` (Whitelist Address Wiring)

### 4.1 `constructor`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| ORP-CON-1 | Constructor stores `whitelistAddress` in upgrade storage slot used by org/account upgrade flows | [U] | P1 |
| ORP-CON-2 | Organization upgrade path reads the stored whitelist address (not caller-supplied address) | [I] | P1 |
| ORP-CON-3 | [DESIRED] Constructor should reject `whitelistAddress == address(0)` | [N] | P0 |

---

## 5. File: `OrganizationImplementation.sol` (Whitelist Enforcement on Organization UUPS Upgrades)

### 5.1 `upgradeToAndCallWithAuthorization`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OI-UTCWA-1 | Non-whitelisted organization implementation is rejected | [N] | P0 |
| OI-UTCWA-2 | Implementation whitelisted only as `Account` is rejected | [N] | P0 |
| OI-UTCWA-3 | Whitelisted organization implementation with valid auth upgrades successfully | [I] | P1 |
| OI-UTCWA-4 | Whitelist-call failure causes upgrade revert and implementation remains unchanged | [S] | P0 |
| OI-UTCWA-5 | If stored whitelist address is invalid/no-code, upgrade reverts | [N] | P0 |
| OI-UTCWA-6 | Whitelist validation executes before setting `isUpgradeAuthorized` (no external window with flag=true pre-validation) | [S] | P0 |
| OI-UTCWA-7 | Failed whitelist validation does not leave `isUpgradeAuthorized` stuck true | [S] | P0 |
| OI-UTCWA-8 | Successful upgrade resets `isUpgradeAuthorized` back to false | [S] | P0 |
| OI-UTCWA-9 | Failed upgrade execution (e.g., bad `data`) does not leave auth flag stuck true (tx rollback) | [S] | P0 |
| OI-UTCWA-10 | Direct call to inherited `upgradeToAndCall` bypassing auth flow reverts `UnauthorizedUpgrade` | [S] | P0 |
| OI-UTCWA-11 | Upgrade `data` payload executes only on successful whitelisted upgrade | [I] | P1 |
| OI-UTCWA-12 | [DESIRED] Admin authorization must bind migration `data` payload in addition to `newImplementation` | [S] | P0 |
| OI-UTCWA-13 | [DESIRED] Migration `data` cannot trigger unauthorized nested second upgrade that bypasses whitelist/admin checks | [S] | P0 |
| OI-UTCWA-14 | [DESIRED] Reject new implementation with no code even if whitelist contract returns true | [S] | P0 |
| OI-UTCWA-15 | [DESIRED] Reject `newImplementation == address(0)` explicitly | [N] | P0 |

### 5.2 `_authorizeUpgrade` (internal hook)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OI-AU-1 | Reverts `UnauthorizedUpgrade` when authorization flag is false | [N] | P0 |
| OI-AU-2 | Succeeds when flag is true (called via authorized flow) | [U] | P1 |
| OI-AU-3 | Behavior is flag-based rather than parameter-based (`newImplementation` not re-validated here) | [S] | P1 |

---

## 6. File: `OrganizationAccountFactoryBase.sol` (Whitelist Enforcement on Account Beacon Upgrades)

### 6.1 `setAccountImplementation`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OAFB-SAI-1 | Non-guardian caller reverts (onlyGuardian) | [N] | P0 |
| OAFB-SAI-2 | Admin signatures for a different `newImplementation` cannot authorize this call (operationData binding) | [S] | P0 |
| OAFB-SAI-3 | Non-whitelisted account implementation is rejected | [N] | P0 |
| OAFB-SAI-4 | Implementation whitelisted only as `Organization` is rejected | [N] | P0 |
| OAFB-SAI-5 | Whitelisted account implementation updates beacon implementation storage | [U] | P1 |
| OAFB-SAI-6 | Emits `AccountImplementationUpdated(newImplementation)` on success | [EV] | P1 |
| OAFB-SAI-7 | Whitelist-call failure reverts and does not update implementation state | [S] | P0 |
| OAFB-SAI-8 | address zero and no-code whitelist contract addresses causes revert | [N] | P0 |
| OAFB-SAI-9 | [DESIRED] Reject account implementation with no code even if whitelist contract returns true | [S] | P0 |
| OAFB-SAI-10 | [DESIRED] Reject `newImplementation == address(0)` explicitly | [N] | P0 |

---

## 7. Cross-File Integration Tests (Whitelist Controls End-to-End)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWC-INT-1 | Unwhitelisted implementation cannot be used in any entrypoint: org deploy, org upgrade, account upgrade | [I] | P0 |
| IWC-INT-2 | Type separation end-to-end: `Account` whitelist never unlocks org deploy/upgrade, and vice versa | [I] | P0 |
| IWC-INT-3 | Unwhitelisting an implementation blocks future use when but does not break already-deployed contracts currently running it for both Organization and Account contracts | [I] | P1 |
| IWC-INT-4 | Re-whitelisting previously removed implementation re-enables eligible flows | [I] | P1 |
| IWC-INT-5 | Upgrading the whitelist contract preserves existing whitelist state and enforcement behavior in factory/org/account flows | [I] | P1 |
| IWC-INT-6 | Ownership transfer of whitelist contract immediately changes who can alter allowed implementations system-wide | [I] | P1 |
| IWC-INT-7 | Deployment path remains atomic with whitelist validation + initialization (no partial state exposure) | [S] | P0 |

---

## 8. Fuzz Tests

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWC-FUZZ-1 | Fuzz random unwhitelisted addresses: always rejected by all three enforcement entrypoints | [F] | P0 |
| IWC-FUZZ-2 | Fuzz add/remove sequences per `ContractType`: onchain state matches reference model mapping | [F] | P1 |
| IWC-FUZZ-3 | Fuzz mixed `Account`/`Organization` operations: mappings remain independent | [F] | P1 |
| IWC-FUZZ-4 | Fuzz `(salt, implementation, whitelist)` tuples: `computeOrganizationAddress` remains deterministic and sensitivity-preserving | [F] | P1 |
| IWC-FUZZ-5 | [DESIRED] Fuzz org-upgrade migration calldata: nested second-upgrade bypass attempts always fail | [F] | P0 |
| IWC-FUZZ-6 | Fuzz proxy initialization inputs: malformed init data never leaves partially initialized whitelist proxy | [F] | P1 |

---

## 9. Invariant Tests

| ID | Invariant | Priority |
|---|-----------|----------|
| IWC-INV-1 | **Owner exclusivity:** Only current whitelist owner can mutate whitelist entries | P0 |
| IWC-INV-2 | **Global whitelist enforcement:** No unwhitelisted implementation can become active via org deploy/org upgrade/account upgrade | P0 |
| IWC-INV-3 | **Type independence:** `Account` and `Organization` whitelist mappings never alias or cross-enable | P0 |
| IWC-INV-4 | **Upgrade auth flag safety:** `isUpgradeAuthorized` is false outside authorized org-upgrade execution window | P0 |
| IWC-INV-5 | **[DESIRED] Org whitelist-pointer immutability:** stored org `whitelistAddress` used for upgrades does not change after proxy construction | P1 |
| IWC-INV-6 | **Whitelist state continuity across whitelist upgrades:** Whitelist data is preserved after whitelist UUPS upgrade | P1 |
| IWC-INV-7 | **[DESIRED] Initialization permanence:** Whitelist initialized state is monotonic (`false -> true` only once) | P0 |

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
