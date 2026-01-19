// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";

/**
 * @title DeploySafeSingletonFactory
 * @notice Script to deploy the Safe Singleton Factory on chains where it doesn't exist
 * @dev CRITICAL: This script uses a special deployer key that MUST maintain nonce = 0.
 *      The Safe Singleton Factory is deployed deterministically using a pre-signed transaction.
 *      If the nonce is burned, the factory cannot be deployed at the expected address.
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
    /// @dev The expected factory address after deployment
    address internal constant EXPECTED_FACTORY_ADDRESS = 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7;

    /// @dev The deployer address that must have nonce 0
    address internal constant EXPECTED_DEPLOYER = 0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37;

    /// @dev Gas price for the deployment transaction (125 gwei - works on most chains)
    uint256 internal constant DEPLOYMENT_GAS_PRICE = 125_000_000_000;

    /// @dev Gas limit for the deployment transaction
    uint256 internal constant DEPLOYMENT_GAS_LIMIT = 101_616;

    /// @dev Required ETH balance for the deployer (gas price * gas limit + buffer)
    uint256 internal constant REQUIRED_ETH_BALANCE = DEPLOYMENT_GAS_PRICE * DEPLOYMENT_GAS_LIMIT * 2;

    // solhint-disable-next-line max-line-length
    /// @dev Pre-signed raw transaction for deploying Safe Singleton Factory (from @safe-global/safe-singleton-factory)
    bytes internal constant DEPLOYMENT_TX =
    // solhint-disable-next-line max-line-length
        hex"f8a780851d1a94a20083018cf08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578082fd5b8082525050506014600cf3820a2ca0a5a32f19deecd09cd0c0d9f55650089385545a0749c12b5d9131ad7ad63bc748a050db15972c02b6e44c171cad539b11feaa4c70c1c034fac02cc4971c8f557d80";

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
        address deployer = vm.addr(deployerPrivateKey);

        // Final verification that deployer matches expected
        if (deployer != EXPECTED_DEPLOYER) {
            console.log(unicode"  ❌ ERROR: Deployer address mismatch!");
            console.log("     Expected: %s", EXPECTED_DEPLOYER);
            console.log("     Got: %s", deployer);
            revert("Deployer address mismatch");
        }

        // Broadcast the pre-signed transaction
        vm.startBroadcast(deployerPrivateKey);

        // Note: The actual deployment uses the pre-signed raw transaction
        // This is handled by sending the raw transaction bytes directly
        // For Foundry, we deploy the factory bytecode directly
        _deployFactory();

        vm.stopBroadcast();

        // Verify deployment
        if (EXPECTED_FACTORY_ADDRESS.code.length == 0) {
            console.log(unicode"  ❌ ERROR: Factory deployment failed!");
            revert("Factory deployment failed");
        }

        console.log("");
        console.log(unicode"  ✅ Safe Singleton Factory deployed successfully!");
        console.log("     Address: %s", EXPECTED_FACTORY_ADDRESS);
        console.log("");
    }

    /**
     * @notice Runs all safety checks before deployment
     * @return passed True if all checks pass
     */
    function _runSafetyChecks() internal view returns (bool passed) {
        console.log("  Running safety checks...");
        console.log("");

        bool allPassed = true;

        // Check 1: Factory not already deployed
        console.log("  [1/4] Checking if factory already deployed...");
        if (EXPECTED_FACTORY_ADDRESS.code.length > 0) {
            console.log(unicode"       ❌ FAIL: Factory already deployed at %s", EXPECTED_FACTORY_ADDRESS);
            allPassed = false;
        } else {
            console.log(unicode"       ✅ PASS: Factory not yet deployed");
        }

        // Check 2: Deployer private key provided
        console.log("  [2/4] Checking deployer private key...");
        try vm.envUint("SAFE_FACTORY_DEPLOYER_PRIVATE_KEY") returns (uint256 pk) {
            address deployer = vm.addr(pk);
            if (deployer == EXPECTED_DEPLOYER) {
                console.log(unicode"       ✅ PASS: Deployer key matches expected address");
            } else {
                console.log(unicode"       ❌ FAIL: Deployer address mismatch");
                console.log("              Expected: %s", EXPECTED_DEPLOYER);
                console.log("              Got: %s", deployer);
                allPassed = false;
            }
        } catch {
            console.log(unicode"       ❌ FAIL: SAFE_FACTORY_DEPLOYER_PRIVATE_KEY not set");
            allPassed = false;
        }

        // Check 3: Deployer nonce is 0
        console.log("  [3/4] Checking deployer nonce...");
        uint256 nonce = vm.getNonce(EXPECTED_DEPLOYER);
        if (nonce == 0) {
            console.log(unicode"       ✅ PASS: Deployer nonce is 0");
        } else {
            console.log(unicode"       ❌ FAIL: Deployer nonce is %s (expected 0)", nonce);
            console.log("              CRITICAL: Nonce has been burned! Cannot deploy factory.");
            allPassed = false;
        }

        // Check 4: Deployer has sufficient ETH
        console.log("  [4/4] Checking deployer ETH balance...");
        uint256 balance = EXPECTED_DEPLOYER.balance;
        if (balance >= REQUIRED_ETH_BALANCE) {
            console.log(unicode"       ✅ PASS: Deployer has sufficient ETH (%s wei)", balance);
        } else {
            console.log(unicode"       ⚠️  WARN: Deployer may need more ETH");
            console.log("              Current: %s wei", balance);
            console.log("              Recommended: %s wei", REQUIRED_ETH_BALANCE);
            // This is a warning, not a failure
        }

        return allPassed;
    }

    /**
     * @notice Deploys the Safe Singleton Factory
     * @dev Uses the factory bytecode directly since Foundry handles broadcasting
     */
    function _deployFactory() internal {
        // Safe Singleton Factory bytecode (minimal CREATE2 factory)
        // This is the init code that produces a contract at the expected address
        bytes memory factoryBytecode =
            hex"604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578082fd5b8082525050506014600cf3";

        address deployed;
        assembly {
            deployed := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
        }

        if (deployed == address(0)) {
            revert("Factory deployment failed in assembly");
        }

        // The address should match due to CREATE from nonce 0
        if (deployed != EXPECTED_FACTORY_ADDRESS) {
            console.log("  Deployed at: %s", deployed);
            console.log("  Expected: %s", EXPECTED_FACTORY_ADDRESS);
            revert("Deployed address mismatch");
        }
    }

    /**
     * @notice Helper to fund the deployer address
     * @dev Can be called separately to fund the deployer before running the main script
     */
    function fundDeployer() external {
        uint256 fundingPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("");
        console.log("  Funding Safe Singleton Factory deployer...");
        console.log("  Target: %s", EXPECTED_DEPLOYER);
        console.log("  Amount: %s wei", REQUIRED_ETH_BALANCE);
        console.log("");

        vm.startBroadcast(fundingPrivateKey);
        payable(EXPECTED_DEPLOYER).transfer(REQUIRED_ETH_BALANCE);
        vm.stopBroadcast();

        console.log(unicode"  ✅ Deployer funded successfully");
    }
}
