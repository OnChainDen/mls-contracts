// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";

import {Create2Deployer} from "script/libraries/Create2Deployer.sol";

/**
 * @title DeploySafeSingletonFactory
 * @notice Script to deploy the Safe Singleton Factory on chains where it doesn't exist
 * @dev CRITICAL: This script uses a special deployer key that MUST maintain nonce = 0.
 *      If the nonce is burned, the factory cannot be deployed at the expected address.
 *
 *      The Safe Singleton Factory is normally deployed via pre-signed raw transactions
 *      (see https://github.com/safe-global/safe-singleton-factory). This script instead
 *      deploys the bytecode directly for Foundry compatibility and multi-chain support,
 *      since pre-signed transactions are chain-specific (signature includes chainId).
 *
 *      SAFETY CHECKS:
 *      1. Verifies deployer nonce is exactly 0
 *      2. Verifies factory is not already deployed
 *      3. Requires explicit CONFIRM_DEPLOYMENT=true environment variable
 *      4. Runs in dry-run mode by default
 *
 * @author Den Technologies Inc
 */
contract DeploySafeSingletonFactory is Script {
    /// @dev Expected factory address after deployment (deterministic via nonce-0 CREATE)
    address internal constant _EXPECTED_FACTORY_ADDRESS = 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7;

    /// @dev Deployer address that must have nonce 0 for deterministic deployment
    address internal constant _EXPECTED_DEPLOYER = 0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37;

    /// @dev Gas price for the deployment transaction (125 gwei - works on most chains)
    uint256 internal constant _DEPLOYMENT_GAS_PRICE = 125_000_000_000;

    /// @dev Gas limit for the deployment transaction
    uint256 internal constant _DEPLOYMENT_GAS_LIMIT = 101_616;

    /// @dev Required ETH balance for the deployer (gas price * gas limit * 2 for buffer)
    uint256 internal constant _REQUIRED_ETH_BALANCE = _DEPLOYMENT_GAS_PRICE * _DEPLOYMENT_GAS_LIMIT * 2;

    /**
     * @notice Main entry point for the deployment script
     * @dev Runs comprehensive safety checks before allowing deployment
     */
    function run() external {
        console.log("");
        console.log("================================================================================");
        console.log("  Safe Singleton Factory Deployment");
        console.log("================================================================================");
        console.log("");

        // Check if deployment is confirmed
        bool confirmDeployment = vm.envOr("CONFIRM_DEPLOYMENT", false);

        // Run all safety checks
        bool allChecksPassed = _runSafetyChecks();

        if (!allChecksPassed) {
            console.log("");
            console.log(unicode"  ❌ SAFETY CHECKS FAILED - Deployment aborted");
            console.log("");
            revert("Safety checks failed");
        }

        if (!confirmDeployment) {
            console.log("");
            console.log("--------------------------------------------------------------------------------");
            console.log("  DRY RUN MODE");
            console.log("--------------------------------------------------------------------------------");
            console.log("");
            console.log("  All safety checks passed. To deploy, run with:");
            console.log("");
            console.log("    CONFIRM_DEPLOYMENT=true forge script DeploySafeSingletonFactory ...");
            console.log("");
            console.log("  WARNING: This will use nonce 0 of the deployer account.");
            console.log("  Make sure this is the correct chain before confirming.");
            console.log("");
            return;
        }

        console.log("");
        console.log("--------------------------------------------------------------------------------");
        console.log("  DEPLOYING SAFE SINGLETON FACTORY");
        console.log("--------------------------------------------------------------------------------");
        console.log("");

        // Get the deployer private key
        uint256 deployerPrivateKey = vm.envUint("SAFE_FACTORY_DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Final verification that deployer matches expected
        if (deployerAddress != _EXPECTED_DEPLOYER) {
            console.log(unicode"  ❌ ERROR: Deployer address mismatch!");
            console.log("     Expected: %s", _EXPECTED_DEPLOYER);
            console.log("     Got: %s", deployerAddress);
            revert("Deployer address mismatch");
        }

        vm.startBroadcast(deployerPrivateKey);

        _deployFactory();

        vm.stopBroadcast();

        // Verify deployment
        if (!Create2Deployer.isContractDeployedAtAddress(_EXPECTED_FACTORY_ADDRESS)) {
            console.log(unicode"  ❌ ERROR: Factory deployment failed!");
            revert("Factory deployment failed");
        }

        console.log("");
        console.log(unicode"  ✅ Safe Singleton Factory deployed successfully!");
        console.log("     Address: %s", _EXPECTED_FACTORY_ADDRESS);
        console.log("");
    }

    /// @notice Funds the Safe Singleton Factory deployer address with ETH
    /// @dev Can be called separately to fund the deployer before running the main script.
    ///      Requires PRIVATE_KEY environment variable to be set for the funding account.
    function fundDeployer() external {
        uint256 fundingPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("");
        console.log("  Funding Safe Singleton Factory deployer...");
        console.log("  Target: %s", _EXPECTED_DEPLOYER);
        console.log("  Amount: %s wei", _REQUIRED_ETH_BALANCE);
        console.log("");

        vm.startBroadcast(fundingPrivateKey);
        payable(_EXPECTED_DEPLOYER).transfer(_REQUIRED_ETH_BALANCE);
        vm.stopBroadcast();

        console.log(unicode"  ✅ Deployer funded successfully");
    }

    /// @dev Deploys the Safe Singleton Factory using inline assembly
    ///      Uses CREATE opcode from nonce 0 to achieve deterministic address
    function _deployFactory() internal {
        // Safe Singleton Factory bytecode (minimal CREATE2 factory)
        // This is the init code that produces a contract at the expected address
        bytes memory factoryBytecode =
            hex"604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578082fd5b8082525050506014600cf3";

        address deployedAtAddress;

        // slither-disable-next-line assembly
        assembly {
            deployedAtAddress := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
        }

        if (deployedAtAddress == address(0)) {
            revert("Factory deployment failed in assembly");
        }

        // The address should match due to CREATE from nonce 0
        if (deployedAtAddress != _EXPECTED_FACTORY_ADDRESS) {
            console.log("  Deployed at: %s", deployedAtAddress);
            console.log("  Expected: %s", _EXPECTED_FACTORY_ADDRESS);
            revert("Deployed address mismatch");
        }
    }

    /// @dev Runs all safety checks before deployment
    ///      Checks: factory not deployed, deployer key valid, nonce is 0, sufficient ETH
    /// @return passed True if all critical checks pass
    function _runSafetyChecks() internal view returns (bool passed) {
        console.log("  Running safety checks...");
        console.log("");

        bool allPassed = true;

        // Check 1: Factory not already deployed
        console.log("  [1/4] Checking if factory already deployed...");
        if (Create2Deployer.isContractDeployedAtAddress(_EXPECTED_FACTORY_ADDRESS)) {
            console.log(unicode"       ❌ FAIL: Factory already deployed at %s", _EXPECTED_FACTORY_ADDRESS);
            allPassed = false;
        } else {
            console.log(unicode"       ✅ PASS: Factory not yet deployed");
        }

        // Check 2: Deployer private key provided
        console.log("  [2/4] Checking deployer private key...");
        try vm.envUint("SAFE_FACTORY_DEPLOYER_PRIVATE_KEY") returns (uint256 pk) {
            address deployerAddress = vm.addr(pk);
            if (deployerAddress == _EXPECTED_DEPLOYER) {
                console.log(unicode"       ✅ PASS: Deployer key matches expected address");
            } else {
                console.log(unicode"       ❌ FAIL: Deployer address mismatch");
                console.log("              Expected: %s", _EXPECTED_DEPLOYER);
                console.log("              Got: %s", deployerAddress);
                allPassed = false;
            }
        } catch {
            console.log(unicode"       ❌ FAIL: SAFE_FACTORY_DEPLOYER_PRIVATE_KEY not set");
            allPassed = false;
        }

        // Check 3: Deployer nonce is 0
        console.log("  [3/4] Checking deployer nonce...");
        uint256 nonce = vm.getNonce(_EXPECTED_DEPLOYER);
        if (nonce == 0) {
            console.log(unicode"       ✅ PASS: Deployer nonce is 0");
        } else {
            console.log(unicode"       ❌ FAIL: Deployer nonce is %s (expected 0)", nonce);
            console.log("              CRITICAL: Nonce has been burned! Cannot deploy factory.");
            allPassed = false;
        }

        // Check 4: Deployer has sufficient ETH
        console.log("  [4/4] Checking deployer ETH balance...");
        uint256 balance = _EXPECTED_DEPLOYER.balance;
        if (balance >= _REQUIRED_ETH_BALANCE) {
            console.log(unicode"       ✅ PASS: Deployer has sufficient ETH (%s wei)", balance);
        } else {
            console.log(unicode"       ⚠️  WARN: Deployer may need more ETH");
            console.log("              Current: %s wei", balance);
            console.log("              Recommended: %s wei", _REQUIRED_ETH_BALANCE);
            // This is a warning, not a failure
        }

        return allPassed;
    }
}
