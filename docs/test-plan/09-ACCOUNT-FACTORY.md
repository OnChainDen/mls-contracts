# 09 — Account Factory Test Plan

**Files Under Test:**
- `src/organization/base/OrganizationAccountFactoryBase.sol`
- `src/organization/libraries/LibOrganizationAccountFactory.sol`
- `src/account/AccountProxy.sol`

**Private Function Testability Plan (Global):**
All `private` functions in the files under test will be refactored to `internal` for testing and exposed via test harness contracts.

| File | Private functions to convert to `internal` for harness testing |
|---|---|
| `OrganizationAccountFactoryBase.sol` | None |
| `LibOrganizationAccountFactory.sol` | None (all non-external helper functions are already `internal`) |
| `AccountProxy.sol` | None |

---

## File 1: OrganizationAccountFactoryBase.sol

### 1.1 `deployAccount`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OAFB-DA-1 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| OAFB-DA-2 | Insufficient admin signatures — reverts | [N] | P0 |
| OAFB-DA-3 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| OAFB-DA-4 | Expired `authParams.expirationTimestamp` — reverts via admin auth validation (`AdminOperationExpired`) | [N] | P0 |
| OAFB-DA-5 | Any `create2Salt` tampering after signatures are produced invalidates auth and reverts (`InsufficientAdminAuthorization`) | [S] | P0 |
| OAFB-DA-6 | Auth-validation revert path (e.g., tampered payload / bad signatures) does not consume nonce; same salt+operation succeeds after corrected signatures | [S] | P0 |
| OAFB-DA-7 | Delegates to `LibOrganizationAccountFactory.deployAccount` — returns deployed address | [U] | P1 |
| OAFB-DA-8 | Returns the correct deployed account address | [U] | P1 |
| OAFB-DA-9 | `OperationType` is `DeployAccount` in admin auth | [U] | P1 |
| OAFB-DA-10 | **Golden test:** for a fixed `create2Salt`, `operationData` is exactly `abi.encode(create2Salt)` (pin expected bytes/hash) | [U] | P1 |

---

### 1.2 `setAccountImplementation`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OAFB-SAI-1 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| OAFB-SAI-2 | Insufficient admin signatures — reverts | [N] | P0 |
| OAFB-SAI-3 | Non-whitelisted implementation — reverts | [N] | P1 |
| OAFB-SAI-4 | Reverts when `whitelistAddress` has no runtime code (undeployed contract / EOA), i.e. whitelist validation call cannot be trusted | [N] | P0 |
| OAFB-SAI-5 | Whitelisted implementation — updates `accountImplementation` in storage | [U] | P1 |
| OAFB-SAI-6 | Emits `AccountImplementationUpdated(newImplementation)` | [EV] | P1 |
| OAFB-SAI-7 | `OperationType` is `UpgradeAccount` in admin auth | [U] | P1 |
| OAFB-SAI-8 | `operationData` encodes `newImplementation` | [U] | P1 |
| OAFB-SAI-9 | Validates against whitelist with `ContractType.Account` | [U] | P1 |
| OAFB-SAI-10 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| OAFB-SAI-11 | **Desired Behavior:** failed whitelist validation does not permanently consume admin nonce (same signed request can succeed once implementation is whitelisted) | [S] | P0 |
| OAFB-SAI-12 | **Desired Behavior:** reject `newImplementation` addresses with no runtime code even if mistakenly whitelisted (fail-closed beacon safety) | [S] | P0 |

---

### 1.3 `computeAccountAddress` (external view)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OAFB-CAA-1 | Delegates to `LibOrganizationAccountFactory.computeAccountAddress` — returns same result | [U] | P1 |
| OAFB-CAA-2 | Callable by anyone (no access restriction) | [U] | P3 |
| OAFB-CAA-3 | `computeAccountAddress(salt)` is stable across account implementation upgrades (same org + same salt => same computed address) | [S] | P1 |

---

### 1.4 `implementation` (IBeacon)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OAFB-I-1 | Returns current implementation address from storage | [U] | P1 |
| OAFB-I-2 | Reverts `AccountImplementationNotSet` when implementation is `address(0)` (not yet set) | [N] | P1 |
| OAFB-I-3 | Returns correct address after `setAccountImplementation` updates it | [U] | P1 |
| OAFB-I-4 | Callable by anyone (used by BeaconProxy during delegatecall) | [U] | P1 |
| OAFB-I-5 | **Desired Behavior:** reverts if stored implementation has no runtime code (fail closed rather than returning an unusable beacon implementation) | [S] | P0 |

---

## File 2: LibOrganizationAccountFactory.sol

### 2.1 `deployAccount`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAF-DA-1 | Deploys account at deterministic CREATE2 address | [U] | P1 |
| LOAF-DA-2 | Deployed address matches `computeAccountAddress(create2Salt)` | [U] | P1 |
| LOAF-DA-3 | Runtime code at deployed address matches expected `AccountProxy` runtime code (reference proxy with same beacon/init data) | [U] | P1 |
| LOAF-DA-4 | Boundary salts (`bytes32(0)` and `bytes32(type(uint256).max)`) produce deployed addresses that match `computeAccountAddress(create2Salt)` | [E] | P2 |
| LOAF-DA-5 | Sets `deployedAccounts[accountAddress] = true` in storage | [U] | P1 |
| LOAF-DA-6 | Emits `AccountDeployed(accountAddress, address(this), create2Salt)` with correct parameters | [EV] | P1 |
| LOAF-DA-7 | Same salt deployed twice — reverts (CREATE2 collision) | [N] | P1 |
| LOAF-DA-8 | Deployed proxy's beacon is the Organization (`address(this)`) | [U] | P1 |
| LOAF-DA-9 | Defensive check: reverts `AccountDeploymentAddressMismatch` if deployed address != computed (should never happen in practice) | [E] | P2 |
| LOAF-DA-10 | Reverts when beacon (`address(this)`) returns an implementation with no runtime code | [N] | P0 |
| LOAF-DA-11 | Reverts when Organization beacon returns `implementation() == address(0)` during proxy deployment | [N] | P0 |
| LOAF-DA-12 | Failed deployment path does not set `deployedAccounts[computedAddress]` | [S] | P0 |
| LOAF-DA-13 | Failed deployment path does not emit `AccountDeployed` | [S] | P0 |

---

### 2.2 `computeAccountAddress`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAF-CAA-1 | Deterministic: same salt always produces same address | [U] | P1 |
| LOAF-CAA-2 | Different salts produce different addresses | [U] | P1 |
| LOAF-CAA-3 | Uses `keccak256(_getAccountProxyBytecode())` as init code hash | [U] | P1 |
| LOAF-CAA-4 | Deployer is `address(this)` (Organization) | [U] | P1 |
| LOAF-CAA-5 | Result matches actual deployed address | [U] | P1 |
| LOAF-CAA-6 | Computed address is independent of current account implementation version (before/after `setAccountImplementation`) | [S] | P1 |
| LOAF-CAA-7 | Chain ID changes do not affect computed address (CREATE2 derivation excludes `chainid`) | [S] | P1 |

---

### 2.3 `isAccountDeployedByOrganization`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAF-IADBO-1 | Returns `true` for deployed account | [U] | P1 |
| LOAF-IADBO-2 | Returns `false` for unknown/non-deployed address | [U] | P1 |
| LOAF-IADBO-3 | Returns `false` for `address(0)` | [E] | P1 |
| LOAF-IADBO-4 | Returns `false` for account deployed by a different organization | [S] | P0 |
| LOAF-IADBO-5 | Address from `computeAccountAddress(salt)` returns `false` before deployment and `true` after successful deployment | [U] | P1 |

---

### 2.4 `validateIsAccountDeployedByOrgOrRevert`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAF-VIADBOOR-1 | Succeeds for deployed account (no revert) | [U] | P1 |
| LOAF-VIADBOOR-2 | Reverts `AccountNotDeployedByOrganization` for non-org account | [N] | P0 |
| LOAF-VIADBOOR-3 | Reverts `AccountNotDeployedByOrganization` for `address(0)` | [N] | P0 |

---

### 2.5 `_getAccountProxyBytecode`

> Note: This function is already `internal view` (not `private`), so no conversion needed.

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAF-GAPB-1 | Returns valid creation bytecode for `AccountProxy` | [U] | P1 |
| LOAF-GAPB-2 | Bytecode includes Organization address (`address(this)`) as beacon parameter | [U] | P1 |
| LOAF-GAPB-3 | Bytecode includes empty bytes as initialization data | [U] | P1 |
| LOAF-GAPB-4 | Different organizations produce different bytecodes (beacon address differs) | [S] | P1 |
| LOAF-GAPB-5 | Bytecode is deterministic for same organization — same result on repeated calls | [U] | P1 |
| LOAF-GAPB-6 | Bytecode does not depend on current `accountImplementation` value (same organization always yields same CREATE2 init code) | [S] | P1 |

---

## File 3: AccountProxy.sol

### 3.1 Constructor and Proxy Behavior

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| APX-CPB-1 | Constructor accepts beacon and data parameters — deploys successfully | [U] | P1 |
| APX-CPB-2 | Proxy delegates all calls to implementation returned by beacon | [I] | P1 |
| APX-CPB-3 | Updating implementation on Organization changes all Account behavior simultaneously | [I] | P1 |
| APX-CPB-4 | Account receives ETH via `receive()` in implementation (proxy forwards) | [I] | P1 |
| APX-CPB-5 | Account's `getOrganizationAddress()` returns correct organization through proxy | [I] | P1 |
| APX-CPB-6 | Constructor reverts when beacon address is not a contract (`ERC1967InvalidBeacon`) | [N] | P0 |
| APX-CPB-7 | Constructor reverts when beacon returns an implementation with no runtime code (`ERC1967InvalidImplementation`) | [N] | P0 |
| APX-CPB-8 | Constructor with empty init data and non-zero `msg.value` reverts (`ERC1967NonPayable`) | [N] | P1 |

---

## 4. Fuzz Tests

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| AF-FT-1 | Fuzz: Random salts always produce unique addresses | [F] | P1 |
| AF-FT-2 | Fuzz: Random salts always produce deployable accounts | [F] | P1 |
| AF-FT-3 | Fuzz: Random non-whitelisted implementation addresses always rejected | [F] | P1 |
| AF-FT-4 | Fuzz: Computed address matches deployed address for any valid salt | [F] | P1 |
| AF-FT-5 | Fuzz: Random addresses — non-deployed always return false for `isAccountDeployedByOrganization` | [F] | P1 |
| AF-FT-6 | Fuzz: Same salt on different organizations — always produces different addresses | [F] | P1 |

---

## 5. Invariant Tests

| ID | Invariant | Priority |
|---|-----------|----------|
| AF-IT-1 | **Account tracking**: Every `deployAccount` call sets `deployedAccounts[addr] = true` | P0 |
| AF-IT-2 | **Account-org binding**: An Account's beacon (Organization) address never changes after deployment | P0 |
| AF-IT-3 | **Whitelist enforcement**: No account implementation can be set unless it's whitelisted | P0 |
| AF-IT-4 | **CREATE2 determinism**: `computeAccountAddress` always matches actual deployed address for any salt | P0 |
| AF-IT-5 | **Deployed accounts monotonic**: `deployedAccounts` mapping only transitions `false → true`, never `true → false` | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `deployAccount` (Base) | 10 | P0-P1 |
| `setAccountImplementation` | 12 | P0-P1 |
| `computeAccountAddress` (external) | 3 | P1-P3 |
| `implementation` (IBeacon) | 5 | P0-P1 |
| `deployAccount` (Lib) | 13 | P0-P2 |
| `computeAccountAddress` (Lib) | 7 | P1 |
| `isAccountDeployedByOrganization` | 5 | P0-P1 |
| `validateIsAccountDeployedByOrgOrRevert` | 3 | P0 |
| `_getAccountProxyBytecode` | 6 | P1 |
| AccountProxy (constructor/proxy) | 8 | P0-P1 |
| Fuzz tests | 6 | P1 |
| Invariant tests | 5 | P0 |
| **Total** | **83** | |
