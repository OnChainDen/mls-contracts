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
     * @notice Deploy a SafeEOAExecutorModule for a specific Safe and executor
     * @param factoryAddress The CREATE2 factory to use
     * @param safeAddress The Safe this module will execute for
     * @param executorAddress The authorized EOA
     * @param salt The CREATE2 salt for deterministic deployment
     */
    function run(
        address factoryAddress,
        address safeAddress,
        address executorAddress,
        bytes32 salt
    ) external;

    /**
     * @notice Compute the expected module address without deploying
     * @param factoryAddress The CREATE2 factory
     * @param safeAddress The Safe address
     * @param executorAddress The authorized EOA
     * @param salt The CREATE2 salt
     */
    function computeAddress(
        address factoryAddress,
        address safeAddress,
        address executorAddress,
        bytes32 salt
    ) external view;
}
```

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
// Salt format: keccak256("den.mls-wallet.safe-module.eoa-executor.<safe-name>.<executor-identifier>.v1")
//
// Examples:
// - Guardian Safe module: keccak256("den.mls-wallet.safe-module.eoa-executor.guardian.service-1.v1")
// - Deployer Safe module: keccak256("den.mls-wallet.safe-module.eoa-executor.deployer.service-1.v1")
```

The salt should be passed as a parameter rather than hardcoded, since:
- Different Safes need different modules
- Multiple executor services might exist
- Versioning for module rotation

---

## Safe Transaction Scripts

### Combined Add/Remove Module Script

**File:** `script/safe-module/SafeModuleTransaction.s.sol`

A single script that handles both adding and removing modules from a Safe, using onchain approvals.

#### Script Interface

```solidity
contract SafeModuleTransaction is Script {
    enum Action {
        ADD_MODULE,
        REMOVE_MODULE
    }

    /**
     * @notice Approve and optionally execute a module add/remove transaction
     * @param safeAddress The Safe to modify
     * @param moduleAddress The module to add or remove
     * @param action Whether to add or remove the module
     * @param executeIfReady If true, execute the transaction if threshold is met after approval
     */
    function run(
        address safeAddress,
        address moduleAddress,
        Action action,
        bool executeIfReady
    ) external;

    /**
     * @notice Check the current approval status for a module transaction
     * @param safeAddress The Safe address
     * @param moduleAddress The module address
     * @param action The action (add or remove)
     */
    function checkApprovalStatus(
        address safeAddress,
        address moduleAddress,
        Action action
    ) external view;
}
```

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

Add new constants for module deployment:

```solidity
// ==================== Safe EOA Executor Module ====================

/// @dev Salt prefix for SafeEOAExecutorModule deployments
/// Full salt is: keccak256(abi.encodePacked(SAFE_EOA_MODULE_SALT_PREFIX, safeIdentifier, executorIdentifier))
string internal constant SAFE_EOA_MODULE_SALT_PREFIX = "den.mls-wallet.safe-module.eoa-executor.";

/// @dev Example salts for Guardian and Deployer Safe modules
bytes32 internal constant GUARDIAN_SAFE_EOA_MODULE_SALT =
    keccak256("den.mls-wallet.safe-module.eoa-executor.guardian.service-1.v1");
bytes32 internal constant DEPLOYER_SAFE_EOA_MODULE_SALT =
    keccak256("den.mls-wallet.safe-module.eoa-executor.deployer.service-1.v1");
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

### Deploying a Module

Deploy a new module instance for a Safe:

```bash
# Deploy module for Guardian Safe
make deploy-safe-module \
    SAFE=0x6aCC5D703Fa6136Bc9305fa1cCEF87F7e1dDCA99 \
    EXECUTOR=0xYourExecutorEOA \
    SALT=0x... \
    NETWORK=sepolia \
    ACCOUNT=my-deployer

# Compute expected address without deploying
make compute-module-address \
    SAFE=0x... \
    EXECUTOR=0x... \
    SALT=0x...
```

### Adding a Module to a Safe

After deploying, Safe owners must approve adding the module:

```bash
# First signer approves (and executes if threshold is met)
make safe-add-module \
    SAFE=0x6aCC5D703Fa6136Bc9305fa1cCEF87F7e1dDCA99 \
    MODULE=0xDeployedModuleAddress \
    EXECUTE=true \
    NETWORK=sepolia \
    ACCOUNT=safe-owner-1

# Second signer approves (for 2-of-3 Safe)
make safe-add-module \
    SAFE=0x... \
    MODULE=0x... \
    EXECUTE=true \
    NETWORK=sepolia \
    ACCOUNT=safe-owner-2
```

### Removing a Module

To remove a module (e.g., for EOA rotation):

```bash
# Safe owners approve removal
make safe-remove-module \
    SAFE=0x... \
    MODULE=0x... \
    EXECUTE=true \
    NETWORK=sepolia \
    ACCOUNT=safe-owner-1
```

### Rotating the Authorized EOA

To change the authorized executor:

1. Deploy a new module with the new executor EOA
2. Add the new module to the Safe
3. Remove the old module from the Safe

```bash
# Step 1: Deploy new module
make deploy-safe-module SAFE=0x... EXECUTOR=0xNewEOA SALT=0x...

# Step 2: Add new module
make safe-add-module SAFE=0x... MODULE=0xNewModule EXECUTE=true

# Step 3: Remove old module
make safe-remove-module SAFE=0x... MODULE=0xOldModule EXECUTE=true
```
```

---

## Makefile Updates

Add new targets:

```makefile
# ==============================================================================
# Safe EOA Executor Module Commands
# ==============================================================================

.PHONY: deploy-safe-module deploy-safe-module-dry-run compute-module-address
.PHONY: safe-add-module safe-remove-module safe-module-status

# Deploy Safe EOA Executor Module
# Example: make deploy-safe-module SAFE=0x... EXECUTOR=0x... SALT=0x... NETWORK=sepolia ACCOUNT=deployer
deploy-safe-module: validate-signer-vars
ifndef SAFE
	$(error SAFE is required. Set SAFE=<safe-address>)
endif
ifndef EXECUTOR
	$(error EXECUTOR is required. Set EXECUTOR=<executor-eoa-address>)
endif
ifndef SALT
	$(error SALT is required. Set SALT=<bytes32-salt>)
endif
	@echo "Deploying SafeEOAExecutorModule..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Safe: $(SAFE)"
	@echo "  Executor: $(EXECUTOR)"
	forge script script/safe-module/DeploySafeEOAExecutorModule.s.sol:DeploySafeEOAExecutorModule \
		--sig "run(address,address,address,bytes32)" $(FACTORY_ADDRESS) $(SAFE) $(EXECUTOR) $(SALT) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Compute module address without deploying
compute-module-address:
ifndef SAFE
	$(error SAFE is required. Set SAFE=<safe-address>)
endif
ifndef EXECUTOR
	$(error EXECUTOR is required. Set EXECUTOR=<executor-eoa-address>)
endif
ifndef SALT
	$(error SALT is required. Set SALT=<bytes32-salt>)
endif
	@echo "Computing SafeEOAExecutorModule address..."
	forge script script/safe-module/DeploySafeEOAExecutorModule.s.sol:DeploySafeEOAExecutorModule \
		--sig "computeAddress(address,address,address,bytes32)" $(FACTORY_ADDRESS) $(SAFE) $(EXECUTOR) $(SALT) \
		--rpc-url $(RPC_URL)

# Add module to Safe (onchain approval)
# Set EXECUTE=true to execute if threshold is met after approval
safe-add-module: validate-signer-vars
ifndef SAFE
	$(error SAFE is required. Set SAFE=<safe-address>)
endif
ifndef MODULE
	$(error MODULE is required. Set MODULE=<module-address>)
endif
	@echo "Approving module addition to Safe..."
	@echo "  Safe: $(SAFE)"
	@echo "  Module: $(MODULE)"
	@echo "  Execute if ready: $(EXECUTE)"
	forge script script/safe-module/SafeModuleTransaction.s.sol:SafeModuleTransaction \
		--sig "run(address,address,uint8,bool)" $(SAFE) $(MODULE) 0 $(if $(EXECUTE),true,false) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Remove module from Safe (onchain approval)
safe-remove-module: validate-signer-vars
ifndef SAFE
	$(error SAFE is required. Set SAFE=<safe-address>)
endif
ifndef MODULE
	$(error MODULE is required. Set MODULE=<module-address>)
endif
	@echo "Approving module removal from Safe..."
	@echo "  Safe: $(SAFE)"
	@echo "  Module: $(MODULE)"
	@echo "  Execute if ready: $(EXECUTE)"
	forge script script/safe-module/SafeModuleTransaction.s.sol:SafeModuleTransaction \
		--sig "run(address,address,uint8,bool)" $(SAFE) $(MODULE) 1 $(if $(EXECUTE),true,false) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Check module transaction approval status
safe-module-status:
ifndef SAFE
	$(error SAFE is required. Set SAFE=<safe-address>)
endif
ifndef MODULE
	$(error MODULE is required. Set MODULE=<module-address>)
endif
ifndef ACTION
	$(error ACTION is required. Set ACTION=add or ACTION=remove)
endif
	@echo "Checking module transaction status..."
	forge script script/safe-module/SafeModuleTransaction.s.sol:SafeModuleTransaction \
		--sig "checkApprovalStatus(address,address,uint8)" $(SAFE) $(MODULE) $(if $(filter add,$(ACTION)),0,1) \
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
2. Implement `run()` function with all safety checks
3. Implement `computeAddress()` function
4. Add Makefile targets: `deploy-safe-module`, `deploy-safe-module-dry-run`, `compute-module-address`

### Phase 3: Safe Transaction Script

1. Create `script/safe-module/SafeModuleTransaction.s.sol`
2. Implement `run()` for both ADD and REMOVE actions
3. Implement `checkApprovalStatus()` view function
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

## Open Questions

1. **Executor Service Identification:** How should different executor services be identified in the salt? (e.g., `service-1`, `guardian-executor`, etc.)

2. **Module Address Tracking:** Should module addresses be added to `DeploymentConfig.sol` like other contract addresses, or tracked separately since they're per-Safe?

3. **Removal Prev Module:** The `disableModule` function requires the previous module in the linked list. The script can compute this automatically, but should we also provide a utility to query it manually?

4. **Gas Optimization:** The current design uses custom errors. Should we add `unchecked` blocks where safe (e.g., for the address comparisons)?
