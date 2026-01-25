# Safe EOA Executor Module - Implementation Plan

This document outlines the implementation plan for a Safe module that allows a designated EOA to execute contract calls on behalf of a Safe multisig.

## Table of Contents

1. [Overview](#overview)
2. [Module Contract Design](#module-contract-design)
3. [Deployment Scripts](#deployment-scripts)
4. [Safe Transaction Scripts](#safe-transaction-scripts)
5. [Testing Strategy](#testing-strategy)
6. [Configuration Updates](#configuration-updates)
7. [Documentation Updates](#documentation-updates)
8. [Implementation Order](#implementation-order)

---

## Overview

### Purpose

The Safe EOA Executor Module enables a single authorized EOA to execute arbitrary contract calls on behalf of a Safe multisig, with the following restrictions:

- **No delegate calls** - Only regular `CALL` operations are allowed
- **No ETH transfers** - The `value` parameter must be zero
- **No calls to the Safe itself** - Prevents the EOA from modifying Safe ownership, threshold, modules, guards, etc.
- **No calls to the module itself** - Prevents any module self-modification

### Design Philosophy

The module is intentionally minimal:

- **No admin functions** - The authorized EOA is immutable (set at deployment)
- **No pause mechanism** - If pausing is needed, Safe owners remove the module via multisig
- **No upgradability** - To rotate the authorized EOA, deploy a new module and swap via Safe multisig
- **One module instance per Safe** - Simplifies the contract and avoids multi-Safe state management

### Events

Safe v1.3.0's `ModuleManager` already emits these events when a module executes transactions:
- `ExecutionFromModuleSuccess(address indexed module)` - On successful execution
- `ExecutionFromModuleFailure(address indexed module)` - On failed execution

No additional events are needed in the module contract.

---

## Module Contract Design

### File Location

```
src/safe-module/SafeEOAExecutorModule.sol
```

### Interface

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title SafeEOAExecutorModule
 * @notice A minimal Safe module that allows a single authorized EOA to execute
 *         contract calls on behalf of a Safe multisig.
 * @dev This module enforces the following restrictions:
 *      - Only regular CALL operations (no delegate calls)
 *      - No ETH value transfers (value must be zero)
 *      - No calls to the Safe itself (prevents ownership/module changes)
 *      - No calls to the module itself
 *
 *      The authorized EOA is immutable - to rotate, deploy a new module instance
 *      and have Safe owners swap modules via multisig transaction.
 *
 * @author Den Technologies Inc
 */
contract SafeEOAExecutorModule {
    /// @notice The Safe this module is authorized to execute transactions for
    address public immutable safe;

    /// @notice The EOA authorized to execute transactions via this module
    address public immutable authorizedExecutor;

    /// @notice Error thrown when caller is not the authorized executor
    error UnauthorizedCaller(address caller, address expected);

    /// @notice Error thrown when attempting to call the Safe itself
    error CannotCallSafe(address target);

    /// @notice Error thrown when attempting to call the module itself
    error CannotCallModule(address target);

    /// @notice Error thrown when attempting to send ETH value
    error CannotSendValue(uint256 value);

    /// @notice Error thrown when the Safe execution fails
    error ExecutionFailed();

    /**
     * @notice Initializes the module with the Safe address and authorized executor
     * @param _safe The Safe multisig this module will execute transactions for
     * @param _authorizedExecutor The EOA authorized to call executeOnBehalf
     */
    constructor(address _safe, address _authorizedExecutor) {
        require(_safe != address(0), "Safe address cannot be zero");
        require(_authorizedExecutor != address(0), "Executor address cannot be zero");

        safe = _safe;
        authorizedExecutor = _authorizedExecutor;
    }

    /**
     * @notice Executes a transaction on behalf of the Safe
     * @dev Only callable by the authorized executor. Enforces:
     *      - No calls to the Safe address
     *      - No calls to this module
     *      - No ETH value transfers
     * @param to The target contract address
     * @param data The calldata to execute
     * @return success Whether the execution succeeded
     * @return returnData The return data from the call
     */
    function executeOnBehalf(
        address to,
        bytes calldata data
    ) external returns (bool success, bytes memory returnData) {
        // Only the authorized executor can call this function
        if (msg.sender != authorizedExecutor) {
            revert UnauthorizedCaller(msg.sender, authorizedExecutor);
        }

        // Cannot call the Safe itself (prevents ownership/module modifications)
        if (to == safe) {
            revert CannotCallSafe(to);
        }

        // Cannot call this module (prevents any self-modification attempts)
        if (to == address(this)) {
            revert CannotCallModule(to);
        }

        // Execute via Safe's execTransactionFromModule
        // Parameters: to, value (0), data, operation (0 = Call)
        success = ISafe(safe).execTransactionFromModule(
            to,
            0,      // value - always zero (no ETH transfers)
            data,
            0       // operation - always Call (no delegate calls)
        );

        if (!success) {
            revert ExecutionFailed();
        }

        // Note: execTransactionFromModule doesn't return data directly
        // If return data is needed, use execTransactionFromModuleReturnData
        return (success, returnData);
    }

    /**
     * @notice Executes a transaction on behalf of the Safe and returns the result data
     * @dev Same restrictions as executeOnBehalf, but returns call data
     * @param to The target contract address
     * @param data The calldata to execute
     * @return success Whether the execution succeeded
     * @return returnData The return data from the call
     */
    function executeOnBehalfWithReturn(
        address to,
        bytes calldata data
    ) external returns (bool success, bytes memory returnData) {
        // Only the authorized executor can call this function
        if (msg.sender != authorizedExecutor) {
            revert UnauthorizedCaller(msg.sender, authorizedExecutor);
        }

        // Cannot call the Safe itself
        if (to == safe) {
            revert CannotCallSafe(to);
        }

        // Cannot call this module
        if (to == address(this)) {
            revert CannotCallModule(to);
        }

        // Execute via Safe's execTransactionFromModuleReturnData
        // Parameters: to, value (0), data, operation (0 = Call)
        (success, returnData) = ISafe(safe).execTransactionFromModuleReturnData(
            to,
            0,      // value - always zero
            data,
            0       // operation - always Call
        );

        if (!success) {
            revert ExecutionFailed();
        }

        return (success, returnData);
    }
}

/// @notice Minimal interface for Safe module execution
interface ISafe {
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    ) external returns (bool success);

    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    ) external returns (bool success, bytes memory returnData);
}
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| `immutable` for `safe` and `authorizedExecutor` | No admin functions needed; rotation requires new module deployment |
| Custom errors instead of `require` strings | Gas efficient and provides better error context |
| Two execution functions | `executeOnBehalf` for simple execution, `executeOnBehalfWithReturn` when return data is needed |
| No reentrancy guard | The module only calls the Safe, which handles its own reentrancy protection |
| `0.8.33` compiler version | Matches platform contracts; enables compilation with default Foundry profile |

### Contract Size

The module should be very small (< 1KB deployed bytecode), well under the 24KB contract size limit.

---

## Deployment Scripts

### Module Deployment Script

**File:** `script/safe-module/DeploySafeEOAExecutorModule.s.sol`

This script deploys the SafeEOAExecutorModule via CREATE2 for deterministic addresses.

#### Script Structure

```solidity
contract DeploySafeEOAExecutorModule is Script {
    /**
     * @notice Deploy SafeEOAExecutorModules for both Guardian and Deployer Safes
     * @dev Safe addresses and salts are retrieved from DeploymentConfig.sol based on factory
     * @param factoryAddress The CREATE2 factory to use
     * @param executorAddress The authorized EOA (same for both modules)
     */
    function run(address factoryAddress, address executorAddress) external;

    /**
     * @notice Deploy only the Guardian Safe module
     * @param factoryAddress The CREATE2 factory to use
     * @param executorAddress The authorized EOA
     */
    function runGuardianOnly(address factoryAddress, address executorAddress) external;

    /**
     * @notice Deploy only the Deployer Safe module
     * @param factoryAddress The CREATE2 factory to use
     * @param executorAddress The authorized EOA
     */
    function runDeployerOnly(address factoryAddress, address executorAddress) external;

    /**
     * @notice Compute expected module addresses without deploying
     * @param factoryAddress The CREATE2 factory
     * @param executorAddress The authorized EOA
     */
    function computeAddresses(address factoryAddress, address executorAddress) external view;
}
```

The script retrieves Safe addresses and salts from `DeploymentConfig.sol` based on the factory address, keeping the interface simple.

#### Safety Checks (matching existing deployment scripts)

1. Validate factory address is not zero
2. Validate factory is deployed at the provided address
3. Validate safe address is not zero
4. Validate safe is deployed (has code)
5. Validate executor address is not zero
6. Warn and confirm for production chains
7. Confirm before broadcast
8. Prevent using production Den Factory deployer EOA

#### Salt Convention

Following the existing ERC-7201 naming convention:

```solidity
// Salts for Guardian and Deployer Safe modules
bytes32 internal constant GUARDIAN_SAFE_EOA_MODULE_SALT =
    keccak256("den.mls-wallet.safe-module.eoa-executor.guardian.v1");
bytes32 internal constant DEPLOYER_SAFE_EOA_MODULE_SALT =
    keccak256("den.mls-wallet.safe-module.eoa-executor.deployer.v1");
```

These salts are hardcoded in `DeploymentConfig.sol` since there are exactly two Safes (Guardian and Deployer) that need modules.

---

## Safe Transaction Scripts

### Combined Add/Remove Module Script

**File:** `script/safe-module/SafeModuleTransaction.s.sol`

A single script that handles both adding and removing modules from a Safe, using onchain approvals.

#### Script Interface

```solidity
contract SafeModuleTransaction is Script {
    /**
     * @notice Approve and optionally execute adding a module to a Safe
     * @dev Safe and module addresses are retrieved from DeploymentConfig.sol
     * @param factoryAddress The CREATE2 factory (to look up correct addresses)
     * @param target "guardian" or "deployer" - which Safe to modify
     * @param executeIfReady If true, execute the transaction if threshold is met after approval
     */
    function addModule(
        address factoryAddress,
        string calldata target,
        bool executeIfReady
    ) external;

    /**
     * @notice Approve and optionally execute removing a module from a Safe
     * @param factoryAddress The CREATE2 factory (to look up correct addresses)
     * @param target "guardian" or "deployer" - which Safe to modify
     * @param executeIfReady If true, execute the transaction if threshold is met after approval
     */
    function removeModule(
        address factoryAddress,
        string calldata target,
        bool executeIfReady
    ) external;

    /**
     * @notice Check the current approval status for a module transaction
     * @param factoryAddress The CREATE2 factory
     * @param target "guardian" or "deployer"
     * @param action "add" or "remove"
     */
    function checkStatus(
        address factoryAddress,
        string calldata target,
        string calldata action
    ) external view;
}
```

The script retrieves Safe and module addresses from `DeploymentConfig.sol` based on the factory and target, simplifying the command-line interface.

#### How It Works

1. **Compute Transaction Hash:**
   - Build the Safe transaction data for `enableModule(address)` or `disableModule(address,address)`
   - Compute the Safe transaction hash using Safe's `getTransactionHash()`

2. **Submit Onchain Approval:**
   - Call `Safe.approveHash(bytes32)` to register the signer's approval onchain
   - This stores the approval in `Safe.approvedHashes[owner][hash]`

3. **Check Threshold:**
   - Query the Safe's threshold and count existing approvals
   - If `executeIfReady` is true and threshold is met, execute the transaction

4. **Execute Transaction:**
   - Collect all approving owners' signatures (using the "approved hash" signature type)
   - Call `Safe.execTransaction()` with the pre-approved signatures

#### Safe Transaction Data

**Enable Module:**
```solidity
// Safe.enableModule(address module)
bytes memory data = abi.encodeWithSelector(
    bytes4(keccak256("enableModule(address)")),
    moduleAddress
);
```

**Disable Module:**
```solidity
// Safe.disableModule(address prevModule, address module)
// Requires finding the previous module in the linked list
bytes memory data = abi.encodeWithSelector(
    bytes4(keccak256("disableModule(address,address)")),
    prevModule,  // Must be computed by iterating modules
    moduleAddress
);
```

#### Finding Previous Module (for disableModule)

Safe stores modules as a linked list. To remove a module, you need the previous module:

```solidity
function findPrevModule(address safe, address module) internal view returns (address prev) {
    // SENTINEL_MODULES = address(0x1)
    address SENTINEL = address(0x1);
    address[] memory modules = ISafe(safe).getModulesPaginated(SENTINEL, 100);

    prev = SENTINEL;
    for (uint i = 0; i < modules.length; i++) {
        if (modules[i] == module) {
            return prev;
        }
        prev = modules[i];
    }
    revert("Module not found");
}
```

#### Safety Checks

1. Validate Safe address is not zero and is deployed
2. Validate module address is not zero and is deployed
3. For ADD_MODULE: Verify module is not already enabled
4. For REMOVE_MODULE: Verify module is currently enabled
5. Verify the signer is an owner of the Safe
6. Warn and confirm for production chains
7. Confirm before broadcast

---

## Testing Strategy

### Test File Location

```
test/safe-module/SafeEOAExecutorModule.t.sol
```

### Handling Different Foundry Profiles

The module is compiled with Solidity 0.8.33 (default profile), but Safe contracts use 0.7.6 (safe profile). Two approaches to handle this:

#### Option A: Use Safe Interfaces Only (Recommended)

Don't import Safe contracts directly. Instead:
1. Deploy Safe contracts using `vm.deployCode()` with pre-compiled bytecode
2. Interact with them via interface types

```solidity
// In test setup
function setUp() public {
    // Deploy Safe singleton from artifact
    safeSingleton = deployCode("GnosisSafe.sol:GnosisSafe");

    // Deploy proxy factory from artifact
    proxyFactory = deployCode("GnosisSafeProxyFactory.sol:GnosisSafeProxyFactory");

    // Create a Safe proxy
    safe = ISafe(proxyFactory.createProxyWithNonce(safeSingleton, initData, 0));
}
```

#### Option B: Fork Testing

Fork a testnet/mainnet where Safe contracts are already deployed:

```solidity
function setUp() public {
    // Fork Sepolia where Safe contracts exist
    vm.createSelectFork("sepolia");

    // Use existing Safe factory to create test Safes
    safe = ISafe(GnosisSafeProxyFactory(SEPOLIA_PROXY_FACTORY).createProxyWithNonce(...));
}
```

### Test Cases

#### Unit Tests

| Test | Description |
|------|-------------|
| `test_constructor_setsImmutables` | Verify constructor sets `safe` and `authorizedExecutor` correctly |
| `test_constructor_revertsOnZeroSafe` | Revert if safe address is zero |
| `test_constructor_revertsOnZeroExecutor` | Revert if executor address is zero |
| `test_executeOnBehalf_succeeds` | Authorized executor can execute valid calls |
| `test_executeOnBehalf_revertsUnauthorizedCaller` | Non-executor cannot call |
| `test_executeOnBehalf_revertsCallToSafe` | Cannot call the Safe address |
| `test_executeOnBehalf_revertsCallToModule` | Cannot call the module itself |
| `test_executeOnBehalfWithReturn_returnsData` | Verify return data is passed through |

#### Integration Tests

| Test | Description |
|------|-------------|
| `test_moduleExecution_emitsSafeEvent` | Safe emits `ExecutionFromModuleSuccess` |
| `test_moduleExecution_stateChanges` | Verify target contract state is modified |
| `test_moduleExecution_multipleCallsInSequence` | Multiple sequential calls work correctly |
| `test_cannotModifySafeViaModule` | Verify all Safe management functions are blocked |

#### Safe Management Function Tests

Verify the module cannot be used to call these Safe functions (by attempting calls to the Safe address):

- `addOwnerWithThreshold(address,uint256)`
- `removeOwner(address,address,uint256)`
- `swapOwner(address,address,address)`
- `changeThreshold(uint256)`
- `enableModule(address)`
- `disableModule(address,address)`
- `setGuard(address)`
- `setFallbackHandler(address)`

---

## Configuration Updates

### DeploymentConfig.sol Updates

Add new constants for module deployment. Following the existing pattern, we need:
- 2 salt constants (Guardian and Deployer)
- 6 address constants (2 modules × 3 factories: Arachnid, Den non-prod, Den prod)
- Helper function to retrieve expected module addresses by factory

```solidity
// ==================== Safe EOA Executor Module Salts ====================

/// @dev Salt for Guardian Safe EOA Executor Module deployment
bytes32 internal constant GUARDIAN_SAFE_EOA_MODULE_SALT =
    keccak256("den.mls-wallet.safe-module.eoa-executor.guardian.v1");

/// @dev Salt for Deployer Safe EOA Executor Module deployment
bytes32 internal constant DEPLOYER_SAFE_EOA_MODULE_SALT =
    keccak256("den.mls-wallet.safe-module.eoa-executor.deployer.v1");

// ==================== Safe EOA Executor Module Addresses ====================
// Module addresses depend on which CREATE2 factory is used for deployment.
// Each factory produces different deterministic addresses.

/// @dev Expected module addresses when deployed via Arachnid Deterministic Deployment Proxy
///      TODO: Update after deploying modules via Arachnid factory
address internal constant ARACHNID_GUARDIAN_SAFE_EOA_MODULE_ADDRESS = address(0);
address internal constant ARACHNID_DEPLOYER_SAFE_EOA_MODULE_ADDRESS = address(0);

/// @dev Expected module addresses when deployed via Production Den Singleton Factory
///      TODO: Update after deploying modules via prod Den Singleton Factory
address internal constant PROD_DEN_FACTORY_GUARDIAN_SAFE_EOA_MODULE_ADDRESS = address(0);
address internal constant PROD_DEN_FACTORY_DEPLOYER_SAFE_EOA_MODULE_ADDRESS = address(0);

/// @dev Expected module addresses when deployed via Non-Production Den Singleton Factory
///      TODO: Update after deploying modules via non-prod Den Singleton Factory
address internal constant NON_PROD_DEN_FACTORY_GUARDIAN_SAFE_EOA_MODULE_ADDRESS = address(0);
address internal constant NON_PROD_DEN_FACTORY_DEPLOYER_SAFE_EOA_MODULE_ADDRESS = address(0);

// ==================== Helper Functions ====================

/// @dev Returns expected Safe EOA Executor Module addresses based on which CREATE2 factory was used
/// @param factoryAddress The CREATE2 factory address used to deploy the modules
/// @return guardianModuleAddress Expected Guardian Safe module address
/// @return deployerModuleAddress Expected Deployer Safe module address
function getExpectedSafeEOAModuleAddresses(address factoryAddress)
    internal
    pure
    returns (address guardianModuleAddress, address deployerModuleAddress)
{
    // Case: Arachnid Deterministic Deployment Proxy
    if (factoryAddress == ARACHNID_CREATE2_FACTORY_ADDRESS) {
        return (ARACHNID_GUARDIAN_SAFE_EOA_MODULE_ADDRESS, ARACHNID_DEPLOYER_SAFE_EOA_MODULE_ADDRESS);
    }

    // Case: Production Den Singleton Factory
    if (factoryAddress == PROD_DEN_SINGLETON_FACTORY_ADDRESS) {
        return (PROD_DEN_FACTORY_GUARDIAN_SAFE_EOA_MODULE_ADDRESS, PROD_DEN_FACTORY_DEPLOYER_SAFE_EOA_MODULE_ADDRESS);
    }

    // Case: Non-Production Den Singleton Factory
    if (factoryAddress == NON_PROD_DEN_SINGLETON_FACTORY_ADDRESS) {
        return (NON_PROD_DEN_FACTORY_GUARDIAN_SAFE_EOA_MODULE_ADDRESS, NON_PROD_DEN_FACTORY_DEPLOYER_SAFE_EOA_MODULE_ADDRESS);
    }

    revert("Unknown factory - no expected Safe EOA module addresses");
}
```

### foundry.toml Updates

No changes needed - the module compiles with the default profile (Solidity 0.8.33).

---

## Documentation Updates

### DEPLOYMENT.md Updates

Add a new section after "Safe 1.3.0 Deployment":

```markdown
## Safe EOA Executor Module

The Safe EOA Executor Module allows a designated EOA to execute contract calls on behalf of a Safe multisig. This is useful for automated services that need to interact with contracts through the Safe.

### Module Restrictions

- **No delegate calls** - Only regular CALL operations
- **No ETH transfers** - Value must be zero
- **No calls to the Safe** - Prevents ownership/module changes
- **No calls to the module** - Prevents self-modification

### Deploying Modules

Deploy the Guardian and Deployer Safe EOA Executor Modules:

```bash
# Deploy both modules (Guardian and Deployer)
make deploy-safe-modules \
    EXECUTOR=0xYourExecutorEOA \
    NETWORK=sepolia \
    ACCOUNT=my-deployer

# Or deploy individually
make deploy-guardian-safe-module \
    EXECUTOR=0xYourExecutorEOA \
    NETWORK=sepolia \
    ACCOUNT=my-deployer

make deploy-deployer-safe-module \
    EXECUTOR=0xYourExecutorEOA \
    NETWORK=sepolia \
    ACCOUNT=my-deployer

# Compute expected addresses without deploying
make compute-module-addresses EXECUTOR=0x...
```

### Adding a Module to a Safe

After deploying, Safe owners must approve adding the module:

```bash
# First signer approves adding module to Guardian Safe (executes if threshold met)
make safe-add-module \
    TARGET=guardian \
    EXECUTE=true \
    NETWORK=sepolia \
    ACCOUNT=safe-owner-1

# Second signer approves (for 2-of-3 Safe)
make safe-add-module \
    TARGET=guardian \
    EXECUTE=true \
    NETWORK=sepolia \
    ACCOUNT=safe-owner-2

# Same for Deployer Safe
make safe-add-module TARGET=deployer EXECUTE=true NETWORK=sepolia ACCOUNT=safe-owner-1
```

### Removing a Module

To remove a module (e.g., for EOA rotation):

```bash
# Safe owners approve removal
make safe-remove-module \
    TARGET=guardian \
    EXECUTE=true \
    NETWORK=sepolia \
    ACCOUNT=safe-owner-1
```

### Rotating the Authorized EOA

To change the authorized executor, you must deploy a new module (with new salt version) and swap:

1. Deploy a new module with the new executor EOA (update salt version in DeploymentConfig.sol first)
2. Add the new module to the Safe
3. Remove the old module from the Safe

```bash
# Step 1: Update GUARDIAN_SAFE_EOA_MODULE_SALT to v2 in DeploymentConfig.sol, then:
make deploy-guardian-safe-module EXECUTOR=0xNewEOA NETWORK=sepolia ACCOUNT=deployer

# Step 2: Add new module (TARGET=guardian uses the new v2 address from config)
make safe-add-module TARGET=guardian EXECUTE=true NETWORK=sepolia ACCOUNT=safe-owner-1

# Step 3: Remove old module (requires passing the old module address explicitly)
# This is a manual operation - see documentation for details
```
```

---

## Makefile Updates

Add new targets:

```makefile
# ==============================================================================
# Safe EOA Executor Module Commands
# ==============================================================================

.PHONY: deploy-safe-modules deploy-guardian-safe-module deploy-deployer-safe-module
.PHONY: deploy-safe-modules-dry-run compute-module-addresses
.PHONY: safe-add-module safe-remove-module safe-module-status

# Deploy both Safe EOA Executor Modules (Guardian and Deployer)
# Example: make deploy-safe-modules EXECUTOR=0x... NETWORK=sepolia ACCOUNT=deployer
deploy-safe-modules: validate-signer-vars
ifndef EXECUTOR
	$(error EXECUTOR is required. Set EXECUTOR=<executor-eoa-address>)
endif
	@echo "Deploying SafeEOAExecutorModules..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Executor: $(EXECUTOR)"
	forge script script/safe-module/DeploySafeEOAExecutorModule.s.sol:DeploySafeEOAExecutorModule \
		--sig "run(address,address)" $(FACTORY_ADDRESS) $(EXECUTOR) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Deploy only Guardian Safe module
deploy-guardian-safe-module: validate-signer-vars
ifndef EXECUTOR
	$(error EXECUTOR is required. Set EXECUTOR=<executor-eoa-address>)
endif
	forge script script/safe-module/DeploySafeEOAExecutorModule.s.sol:DeploySafeEOAExecutorModule \
		--sig "runGuardianOnly(address,address)" $(FACTORY_ADDRESS) $(EXECUTOR) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Deploy only Deployer Safe module
deploy-deployer-safe-module: validate-signer-vars
ifndef EXECUTOR
	$(error EXECUTOR is required. Set EXECUTOR=<executor-eoa-address>)
endif
	forge script script/safe-module/DeploySafeEOAExecutorModule.s.sol:DeploySafeEOAExecutorModule \
		--sig "runDeployerOnly(address,address)" $(FACTORY_ADDRESS) $(EXECUTOR) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Compute module addresses without deploying
compute-module-addresses:
ifndef EXECUTOR
	$(error EXECUTOR is required. Set EXECUTOR=<executor-eoa-address>)
endif
	@echo "Computing SafeEOAExecutorModule addresses..."
	forge script script/safe-module/DeploySafeEOAExecutorModule.s.sol:DeploySafeEOAExecutorModule \
		--sig "computeAddresses(address,address)" $(FACTORY_ADDRESS) $(EXECUTOR) \
		--rpc-url $(RPC_URL)

# Add module to Safe (onchain approval)
# TARGET: "guardian" or "deployer" to use preconfigured addresses
# Set EXECUTE=true to execute if threshold is met after approval
safe-add-module: validate-signer-vars
ifndef TARGET
	$(error TARGET is required. Set TARGET=guardian or TARGET=deployer)
endif
	@echo "Approving module addition to Safe..."
	@echo "  Target: $(TARGET)"
	@echo "  Execute if ready: $(EXECUTE)"
	forge script script/safe-module/SafeModuleTransaction.s.sol:SafeModuleTransaction \
		--sig "addModule(address,string,bool)" $(FACTORY_ADDRESS) $(TARGET) $(if $(EXECUTE),true,false) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Remove module from Safe (onchain approval)
safe-remove-module: validate-signer-vars
ifndef TARGET
	$(error TARGET is required. Set TARGET=guardian or TARGET=deployer)
endif
	@echo "Approving module removal from Safe..."
	@echo "  Target: $(TARGET)"
	@echo "  Execute if ready: $(EXECUTE)"
	forge script script/safe-module/SafeModuleTransaction.s.sol:SafeModuleTransaction \
		--sig "removeModule(address,string,bool)" $(FACTORY_ADDRESS) $(TARGET) $(if $(EXECUTE),true,false) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Check module transaction approval status
safe-module-status:
ifndef TARGET
	$(error TARGET is required. Set TARGET=guardian or TARGET=deployer)
endif
ifndef ACTION
	$(error ACTION is required. Set ACTION=add or ACTION=remove)
endif
	@echo "Checking module transaction status..."
	forge script script/safe-module/SafeModuleTransaction.s.sol:SafeModuleTransaction \
		--sig "checkStatus(address,string,string)" $(FACTORY_ADDRESS) $(TARGET) $(ACTION) \
		--rpc-url $(RPC_URL)
```

---

## Implementation Order

### Phase 1: Module Contract

1. Create `src/safe-module/SafeEOAExecutorModule.sol`
2. Create minimal `ISafe` interface (or reuse existing if available)
3. Verify compilation with default Foundry profile

### Phase 2: Module Deployment Script

1. Create `script/safe-module/DeploySafeEOAExecutorModule.s.sol`
2. Implement `run()`, `runGuardianOnly()`, `runDeployerOnly()` functions with all safety checks
3. Implement `computeAddresses()` function
4. Add Makefile targets: `deploy-safe-modules`, `deploy-guardian-safe-module`, `deploy-deployer-safe-module`, `compute-module-addresses`

### Phase 3: Safe Transaction Script

1. Create `script/safe-module/SafeModuleTransaction.s.sol`
2. Implement `addModule()` and `removeModule()` functions
3. Implement `checkStatus()` view function
4. Add Makefile targets: `safe-add-module`, `safe-remove-module`, `safe-module-status`

### Phase 4: Testing

1. Create `test/safe-module/SafeEOAExecutorModule.t.sol`
2. Implement unit tests for the module contract
3. Implement integration tests with Safe contracts
4. Verify all tests pass

### Phase 5: Configuration & Documentation

1. Update `script/config/DeploymentConfig.sol` with new salt constants
2. Update `DEPLOYMENT.md` with module deployment instructions
3. Update `Makefile` help text

### Phase 6: Final Review

1. Run `make check` (format, lint, analyze, sizes, test)
2. Review contract for security issues
3. Verify all documentation is accurate

---

## File Summary

| File | Description |
|------|-------------|
| `src/safe-module/SafeEOAExecutorModule.sol` | The module contract |
| `script/safe-module/DeploySafeEOAExecutorModule.s.sol` | Deployment script |
| `script/safe-module/SafeModuleTransaction.s.sol` | Add/remove module script |
| `test/safe-module/SafeEOAExecutorModule.t.sol` | Test file |
| `script/config/DeploymentConfig.sol` | Add salt constants |
| `DEPLOYMENT.md` | Add module documentation |
| `Makefile` | Add new targets |

---

## Development Workflow Notes

### Interactive Script Testing

Deployment scripts use interactive input (confirmations, password prompts for Foundry-managed accounts). During development:

1. **Do not attempt to run deployment scripts directly** - they require interactive input
2. **For testing**, either:
   - Modify `script/sh/test_deploy_scripts_locally.sh` to include module deployment steps
   - Create a new convenience script (e.g., `script/sh/test_module_deploy_locally.sh`)
   - Ask the user to run specific `make` commands and provide output

3. **Unit tests** can be run non-interactively with `forge test`

---

## Resolved Design Decisions

| Question | Decision |
|----------|----------|
| Salt naming convention | `den.mls-wallet.safe-module.eoa-executor.guardian.v1` and `den.mls-wallet.safe-module.eoa-executor.deployer.v1` |
| Module address tracking | Add to `DeploymentConfig.sol` with 3 sets of addresses (Arachnid, Den non-prod, Den prod) for both Guardian and Deployer modules |
| Previous module query utility | Not needed - script computes it automatically |

---

## Open Questions

1. **Gas Optimization:** The current design uses custom errors. Should we add `unchecked` blocks where safe (e.g., for the address comparisons)?

2. **Authorized Executor Configuration:** Where will the authorized executor EOA addresses be configured? Options:
   - Hardcoded in `DeploymentConfig.sol` (like Safe owner addresses)
   - Passed as command-line arguments to the deployment script
   - Environment variables
