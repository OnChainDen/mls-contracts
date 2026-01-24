// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import {Vm, VmSafe} from "forge-std/Vm.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Logger} from "script/libraries/Logger.sol";

/**
 * @title ScriptUtils
 * @dev Helpers for Foundry deployment scripts.
 *
 *      NOTE: Foundry's console.log output is buffered and only displayed after script execution,
 *      but vm.prompt displays immediately. Therefore, any context that needs to be visible
 *      before user confirmation MUST be embedded in the prompt message itself.
 *
 *      This library uses a floating pragma (>=0.7.0 <0.9.0) to allow reuse by both
 *      platform scripts (0.8.33) and Safe deployment scripts (0.7.6).
 */
library ScriptUtils {
    // ==================== String Utilities ====================
    // These replace OpenZeppelin's Strings library for 0.7.x compatibility

    /**
     * @dev Compares two strings for equality
     * @param a First string to compare
     * @param b Second string to compare
     * @return True if strings are equal
     */
    function stringEquals(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /**
     * @dev Converts a uint256 to its ASCII string decimal representation
     * @param value The uint256 value to convert
     * @return The string representation
     */
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts an address to its ASCII string hexadecimal representation with 0x prefix
     * @param addr The address to convert
     * @return The hex string representation (42 characters including 0x)
     */
    function toHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = new bytes(42);
        buffer[0] = "0";
        buffer[1] = "x";
        bytes memory hexAlphabet = "0123456789abcdef";
        uint160 value = uint160(addr);
        for (uint256 i = 41; i > 1; i--) {
            buffer[i] = hexAlphabet[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }

    // ==================== CREATE2 Utilities ====================
    // These replace OpenZeppelin's Create2 library for 0.7.x compatibility

    /**
     * @dev Computes the address of a contract deployed using CREATE2
     * @param salt The salt used for deployment
     * @param initCodeHash The keccak256 hash of the contract's init code
     * @param deployer The address of the CREATE2 factory
     * @return The computed address
     */
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash, address deployer)
        internal
        pure
        returns (address)
    {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
    }

    // ==================== Chain ID Utilities ====================
    // For 0.7.x compatibility (block.chainid was added in 0.8.0)

    /**
     * @dev Gets the current chain ID using inline assembly for 0.7.x compatibility
     * @return chainId The chain ID of the current network
     */
    function getChainId() internal view returns (uint256 chainId) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainId := chainid()
        }
    }

    // ==================== Confirmation Prompts ====================

    /**
     * @dev Prompts the user for confirmation with context and reverts if they don't type "yes".
     * @param vm The Foundry Vm cheatcode instance
     * @param context Context message to display before the prompt (will be shown immediately)
     */
    function promptForConfirmationOrRevert(Vm vm, string memory context) internal {
        // Build prompt with context embedded so it displays immediately
        // NOTE: console.log output is buffered, but vm.prompt displays immediately
        string memory promptMessage = string(abi.encodePacked(context, "\nType 'yes' to continue: "));
        string memory response = vm.prompt(promptMessage);
        string memory trimmedResponse = vm.trim(response);
        require(stringEquals(trimmedResponse, "yes"), "Confirmation not received");
    }

    /**
     * @dev Logs the execution mode (broadcast or dry run) and prompts the user for confirmation
     *      when broadcasting.
     * @param vm The Foundry Vm cheatcode instance
     * @param scriptName Human-readable script name for logging
     */
    function confirmBroadcastOrDryRun(Vm vm, string memory scriptName) internal {
        // Case: the script is being run with the --broadcast flag
        // Log the broadcast mode and prompt for confirmation
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            // Build the context message with all info embedded
            // solhint-disable-next-line func-named-parameters
            string memory context = string(
                abi.encodePacked(
                    "\n",
                    "  !! BROADCAST MODE DETECTED !!\n",
                    "  Script: ",
                    scriptName,
                    "\n",
                    "  Transactions WILL be sent to the network."
                )
            );

            promptForConfirmationOrRevert(vm, context);
            Logger.logEmptyLine();
        } else {
            // Case: the script is being run with the --dry-run flag
            // Log that we're in dry run mode
            Logger.logInfo("DRY RUN MODE - No transactions will be broadcast");
            Logger.logEmptyLine();
        }
    }

    /**
     * @dev Logs whether a production chain is detected and prompts for confirmation if so.
     * @param vm The Foundry Vm cheatcode instance
     * @param scriptName Human-readable script name for logging
     */
    function warnAndConfirmIfProductionChain(Vm vm, string memory scriptName) internal {
        // Get chain ID using assembly for 0.7.x compatibility
        uint256 chainId = getChainId();

        // Determine if the chain is a production chain
        bool isProdChain = DeploymentConfig.isProductionChain(chainId);

        // Case: the chain is a production chain
        // Prompt for confirmation with embedded context
        if (isProdChain) {
            // Build the context message with all info embedded
            // solhint-disable-next-line func-named-parameters
            string memory context = string(
                abi.encodePacked(
                    "\n",
                    "  !! PRODUCTION CHAIN DETECTED !!\n",
                    "  Script: ",
                    scriptName,
                    "\n",
                    "  Chain ID: ",
                    toString(chainId)
                )
            );

            promptForConfirmationOrRevert(vm, context);
            Logger.logEmptyLine();
        } else {
            // Case: the chain is a non-production chain
            // Log that we're on a non-production chain (no confirmation needed)
            Logger.logInfo("NON-PRODUCTION CHAIN DETECTED");
            Logger.logKeyValue("Script", scriptName);
            Logger.logKeyValue("Chain ID", chainId);
            Logger.logEmptyLine();
        }
    }
}
