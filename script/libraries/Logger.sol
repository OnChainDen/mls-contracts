// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {console} from "forge-std/console.sol";

/**
 * @title Logger
 * @notice Centralized logging utilities for deployment scripts
 * @dev Provides consistent formatting for console output across all scripts.
 *      All functions are internal pure/view to be inlined during compilation.
 *
 *      Icon Legend:
 *      - ✅ PASS/DEPLOYED/SUCCESS
 *      - ❌ FAIL/ERROR
 *      - ⏭️  SKIPPED/INFO
 *      - ⚠️  WARN
 *
 * @author Den Technologies Inc
 */
library Logger {
    // =========================================================================
    // Status Messages (generic, reusable)
    // =========================================================================

    /// @dev Logs a success/pass message with checkmark icon
    /// @param message The message to display
    function logPass(string memory message) internal pure {
        console.log(unicode"  ✅ %s", message);
    }

    /// @dev Logs a failure/error message with X icon
    /// @param message The message to display
    function logFail(string memory message) internal pure {
        console.log(unicode"  ❌ %s", message);
    }

    /// @dev Logs a warning message with warning icon
    /// @param message The message to display
    function logWarn(string memory message) internal pure {
        console.log(unicode"  ⚠️  %s", message);
    }

    /// @dev Logs an info/skip message with skip icon
    /// @param message The message to display
    function logInfo(string memory message) internal pure {
        console.log(unicode"  ⏭️  %s", message);
    }

    /// @dev Logs a successful deployment
    /// @param name Human-readable name of the deployed contract
    /// @param deployedAddress Address where the contract was deployed
    function logDeployed(string memory name, address deployedAddress) internal pure {
        console.log(unicode"  ✅ DEPLOYED: %s at %s", name, deployedAddress);
    }

    /// @dev Logs a skipped deployment (already deployed)
    /// @param name Human-readable name of the contract
    /// @param existingAddress Address where the contract already exists
    function logDeploymentSkipped(string memory name, address existingAddress) internal pure {
        console.log(unicode"  ⏭️  SKIPPED: %s (already deployed at %s)", name, existingAddress);
    }

    // =========================================================================
    // Safety Check Messages
    // =========================================================================

    /// @dev Logs the start of a safety check
    /// @param description What is being checked
    function logCheckStart(string memory description) internal pure {
        console.log("  %s", description);
    }

    /// @dev Logs a passed check result (7-space indent for alignment)
    /// @param message The pass message
    function logCheckPass(string memory message) internal pure {
        console.log(unicode"       ✅ PASS: %s", message);
    }

    /// @dev Logs a failed check result (7-space indent for alignment)
    /// @param message The failure message
    function logCheckFail(string memory message) internal pure {
        console.log(unicode"       ❌ FAIL: %s", message);
    }

    /// @dev Logs additional detail for a check (14-space indent)
    /// @param message The detail message
    function logCheckDetail(string memory message) internal pure {
        console.log("              %s", message);
    }

    // =========================================================================
    // Structural/Layout
    // =========================================================================

    /// @dev Logs a box header with a title
    /// @param title The title to display in the header
    function logBoxHeader(string memory title) internal pure {
        console.log("");
        console.log("================================================================================");
        console.log("  %s", title);
        console.log("================================================================================");
        logEmptyLine();
    }

    /// @dev Logs a section divider with a name
    /// @param name The section name
    function logSection(string memory name) internal pure {
        console.log("");
        console.log("--------------------------------------------------------------------------------");
        console.log("  %s", name);
        console.log("--------------------------------------------------------------------------------");
    }

    /// @dev Logs a box footer (closing line)
    function logBoxFooter() internal pure {
        console.log("================================================================================");
    }

    /// @dev Logs an empty line
    function logEmptyLine() internal pure {
        console.log("");
    }

    /// @dev Logs a message with standard 2-space indentation
    /// @param message The message to display
    function logIndented(string memory message) internal pure {
        console.log("  %s", message);
    }

    /// @dev Logs a key-value pair with standard indentation
    /// @param key The label/key
    /// @param value The value to display
    function logKeyValue(string memory key, string memory value) internal pure {
        console.log("  %s: %s", key, value);
    }

    /// @dev Logs a key-value pair with an address value
    /// @param key The label/key
    /// @param valueAddress The address value
    function logKeyAddress(string memory key, address valueAddress) internal pure {
        console.log("  %s: %s", key, valueAddress);
    }

    /// @dev Logs a key-value pair with a uint256 value
    /// @param key The label/key
    /// @param value The uint256 value
    function logKeyUint(string memory key, uint256 value) internal pure {
        console.log("  %s: %s", key, value);
    }

    // =========================================================================
    // Common Deployment Messages
    // =========================================================================

    /// @dev Logs successful deployment with environment variable instruction
    /// @param name Human-readable name of what was deployed
    /// @param deployedAddress Address where it was deployed
    /// @param envVarName Name of the environment variable to set
    function logDeploymentSuccess(string memory name, address deployedAddress, string memory envVarName) internal pure {
        console.log("");
        console.log(unicode"  ✅ %s deployed successfully!", name);
        console.log("     Address: %s", deployedAddress);
        console.log("");
        console.log("  Next step: Set the factory address in your environment:");
        console.log("    export %s=%s", envVarName, deployedAddress);
        console.log("");
    }

    /// @dev Logs deployment completion message
    function logDeploymentComplete() internal pure {
        console.log("");
        console.log("================================================================================");
        console.log(unicode"  ✅ Deployment Complete!");
        console.log("================================================================================");
        console.log("");
    }
}
