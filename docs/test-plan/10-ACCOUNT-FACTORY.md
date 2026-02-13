# 10 — Account Factory Test Plan

**Files Under Test:**
- `src/organization/base/OrganizationAccountFactoryBase.sol`
- `src/organization/libraries/LibOrganizationAccountFactory.sol`
- `src/account/AccountProxy.sol`
- `src/interfaces/organization/IOrganizationAccountFactory.sol`

**Test File(s):** `test/OrganizationAccountFactoryBase.t.sol`, `test/LibOrganizationAccountFactory.t.sol`, `test/AccountProxy.t.sol`

---

## File 1: OrganizationAccountFactoryBase.sol

### 1.1 `deployAccount`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| 2 | Insufficient admin signatures — reverts | [N] | P0 |
| 3 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| 4 | Delegates to `LibOrganizationAccountFactory.deployAccount` — returns deployed address | [U] | P1 |
| 5 | Returns the correct deployed account address | [U] | P1 |
| 6 | `OperationType` is `DeployAccount` in admin auth | [U] | P1 |
| 7 | `operationData` encodes `create2Salt` | [U] | P1 |

---

### 1.2 `setAccountImplementation`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 8 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| 9 | Insufficient admin signatures — reverts | [N] | P0 |
| 10 | Non-whitelisted implementation — reverts | [N] | P1 |
| 11 | Whitelisted implementation — updates `accountImplementation` in storage | [U] | P1 |
| 12 | Emits `AccountImplementationUpdated(newImplementation)` | [EV] | P1 |
| 13 | `OperationType` is `UpgradeAccount` in admin auth | [U] | P1 |
| 14 | `operationData` encodes `newImplementation` | [U] | P1 |
| 15 | Validates against whitelist with `ContractType.Account` | [U] | P1 |
| 16 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |

---

### 1.3 `computeAccountAddress` (external view)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 17 | Delegates to `LibOrganizationAccountFactory.computeAccountAddress` — returns same result | [U] | P1 |
| 18 | Callable by anyone (no access restriction) | [U] | P3 |

---

### 1.4 `implementation` (IBeacon)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 19 | Returns current implementation address from storage | [U] | P1 |
| 20 | Reverts `AccountImplementationNotSet` when implementation is `address(0)` (not yet set) | [N] | P1 |
| 21 | Returns correct address after `setAccountImplementation` updates it | [U] | P1 |
| 22 | Callable by anyone (used by BeaconProxy during delegatecall) | [U] | P1 |

---

## File 2: LibOrganizationAccountFactory.sol

### 2.1 `deployAccount`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 23 | Deploys account at deterministic CREATE2 address | [U] | P1 |
| 24 | Deployed address matches `computeAccountAddress(create2Salt)` | [U] | P1 |
| 25 | Sets `deployedAccounts[accountAddress] = true` in storage | [U] | P1 |
| 26 | Emits `AccountDeployed(accountAddress, address(this), create2Salt)` with correct parameters | [EV] | P1 |
| 27 | Same salt deployed twice — reverts (CREATE2 collision) | [N] | P1 |
| 28 | Deployed proxy's beacon is the Organization (`address(this)`) | [U] | P1 |
| 29 | Defensive check: reverts `AccountDeploymentAddressMismatch` if deployed address != computed (should never happen in practice) | [E] | P2 |

---

### 2.2 `computeAccountAddress`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 30 | Deterministic: same salt always produces same address | [U] | P1 |
| 31 | Different salts produce different addresses | [U] | P1 |
| 32 | Uses `keccak256(_getAccountProxyBytecode())` as init code hash | [U] | P1 |
| 33 | Deployer is `address(this)` (Organization) | [U] | P1 |
| 34 | Result matches actual deployed address | [U] | P1 |

---

### 2.3 `isAccountDeployedByOrganization`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 35 | Returns `true` for deployed account | [U] | P1 |
| 36 | Returns `false` for unknown/non-deployed address | [U] | P1 |
| 37 | Returns `false` for `address(0)` | [E] | P1 |
| 38 | Returns `false` for account deployed by a different organization | [S] | P0 |

---

### 2.4 `validateIsAccountDeployedByOrgOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 39 | Succeeds for deployed account (no revert) | [U] | P1 |
| 40 | Reverts `AccountNotDeployedByOrganization` for non-org account | [N] | P0 |
| 41 | Reverts `AccountNotDeployedByOrganization` for `address(0)` | [N] | P0 |

---

### 2.5 `_getAccountProxyBytecode`

> Note: This function is already `internal view` (not `private`), so no conversion needed.

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 42 | Returns valid creation bytecode for `AccountProxy` | [U] | P1 |
| 43 | Bytecode includes Organization address (`address(this)`) as beacon parameter | [U] | P1 |
| 44 | Bytecode includes empty bytes as initialization data | [U] | P1 |
| 45 | Different organizations produce different bytecodes (beacon address differs) | [S] | P1 |
| 46 | Bytecode is deterministic for same organization — same result on repeated calls | [U] | P1 |

---

## File 3: AccountProxy.sol

### 3.1 Constructor and Proxy Behavior

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 47 | Constructor accepts beacon and data parameters — deploys successfully | [U] | P1 |
| 48 | Proxy delegates all calls to implementation returned by beacon | [I] | P1 |
| 49 | Updating implementation on Organization changes all Account behavior simultaneously | [I] | P1 |
| 50 | Account receives ETH via `receive()` in implementation (proxy forwards) | [I] | P1 |
| 51 | Account's `getOrganizationAddress()` returns correct organization through proxy | [I] | P1 |

---

## 4. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 52 | Fuzz: Random salts always produce unique addresses | [F] | P1 |
| 53 | Fuzz: Random salts always produce deployable accounts | [F] | P1 |
| 54 | Fuzz: Random non-whitelisted implementation addresses always rejected | [F] | P1 |
| 55 | Fuzz: Computed address matches deployed address for any valid salt | [F] | P1 |
| 56 | Fuzz: Random addresses — non-deployed always return false for `isAccountDeployedByOrganization` | [F] | P1 |
| 57 | Fuzz: Same salt on different organizations — always produces different addresses | [F] | P1 |

---

## 5. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 58 | **Account tracking**: Every `deployAccount` call sets `deployedAccounts[addr] = true` | P0 |
| 59 | **Account-org binding**: An Account's beacon (Organization) address never changes after deployment | P0 |
| 60 | **Whitelist enforcement**: No account implementation can be set unless it's whitelisted | P0 |
| 61 | **CREATE2 determinism**: `computeAccountAddress` always matches actual deployed address for any salt | P0 |
| 62 | **Deployed accounts monotonic**: `deployedAccounts` mapping only transitions `false → true`, never `true → false` | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `deployAccount` (Base) | 7 | P0-P1 |
| `setAccountImplementation` | 9 | P0-P1 |
| `computeAccountAddress` (external) | 2 | P1-P3 |
| `implementation` (IBeacon) | 4 | P1 |
| `deployAccount` (Lib) | 7 | P1-P2 |
| `computeAccountAddress` (Lib) | 5 | P1 |
| `isAccountDeployedByOrganization` | 4 | P0-P1 |
| `validateIsAccountDeployedByOrgOrRevert` | 3 | P0 |
| `_getAccountProxyBytecode` | 5 | P1 |
| AccountProxy (constructor/proxy) | 5 | P1 |
| Fuzz tests | 6 | P1 |
| Invariant tests | 5 | P0 |
| **Total** | **62** | |
