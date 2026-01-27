// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {ScriptUtils} from "script/libraries/ScriptUtils.sol";
import {StringUtils} from "script/libraries/StringUtils.sol";

/// @notice Minimal interface for Safe v1.3.0 functions needed by this script
/// @dev We define this locally rather than importing from the Safe library to avoid
///      Slither parsing errors that occur when analyzing cross-version Solidity imports.
interface IGnosisSafe {
    function isModuleEnabled(address module) external view returns (bool);
    function enableModule(address module) external;
    function disableModule(address prevModule, address module) external;
    function getThreshold() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
    function approvedHashes(address owner, bytes32 hash) external view returns (uint256);
    function approveHash(bytes32 hashToApprove) external;
    function nonce() external view returns (uint256);
    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory array, address next);
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);
}

/**
 * @title SafeModuleTransaction
 * @notice Script for Safe owners to approve and execute module add/remove transactions
 * @dev Uses onchain approvals (approveHash) instead of offchain signatures.
 *
 *      For adding a module:
 *        forge script script/safe-module/SafeModuleTransaction.s.sol:SafeModuleTransaction \
 *          --sig "addModule(address,string,bool)" <FACTORY_ADDRESS> <SAFE_TYPE> <EXECUTE_IF_READY> \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          -vvvv
 *
 *      For removing a module:
 *        forge script script/safe-module/SafeModuleTransaction.s.sol:SafeModuleTransaction \
 *          --sig "removeModule(address,string,bool)" <FACTORY_ADDRESS> <SAFE_TYPE> <EXECUTE_IF_READY> \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          -vvvv
 *
 *      Where:
 *        - FACTORY_ADDRESS: The CREATE2 factory used for deployment (to lookup addresses)
 *        - SAFE_TYPE: "guardian" or "deployer" - which Safe to modify
 *        - EXECUTE_IF_READY: true to execute if threshold is met after approval
 *
 * @author Den Technologies Inc
 */
contract SafeModuleTransaction is Script {
    /**
     * @notice Approve and optionally execute adding a module to a Safe
     * @param factoryAddress The CREATE2 factory address (to lookup Safe/module addresses)
     * @param safeType "guardian" or "deployer" - which Safe to modify
     * @param executeIfReady If true, execute the transaction if threshold is met after approval
     */
    function addModule(address factoryAddress, string calldata safeType, bool executeIfReady) external {
        // Get Safe and module addresses
        (address safeAddress, address moduleAddress) = _getAddresses(factoryAddress, safeType);

        // Validate the Safe and module are deployed
        require(Create2Utils.isContractDeployedAtAddress(safeAddress), "Safe not deployed");
        require(Create2Utils.isContractDeployedAtAddress(moduleAddress), "Module not deployed");

        // Check module is not already enabled
        require(!IGnosisSafe(safeAddress).isModuleEnabled(moduleAddress), "Module already enabled");

        // Build the transaction data for enableModule
        bytes memory txData = abi.encodeWithSelector(IGnosisSafe.enableModule.selector, moduleAddress);

        // Process the transaction
        _processTransaction(safeAddress, moduleAddress, txData, safeType, "ADD", executeIfReady);
    }

    /**
     * @notice Approve and optionally execute removing a module from a Safe
     * @param factoryAddress The CREATE2 factory address (to lookup Safe/module addresses)
     * @param safeType "guardian" or "deployer" - which Safe to modify
     * @param executeIfReady If true, execute the transaction if threshold is met after approval
     */
    function removeModule(address factoryAddress, string calldata safeType, bool executeIfReady) external {
        // Get Safe and module addresses
        (address safeAddress, address moduleAddress) = _getAddresses(factoryAddress, safeType);

        // Validate the Safe is deployed
        require(Create2Utils.isContractDeployedAtAddress(safeAddress), "Safe not deployed");

        // Check module is currently enabled
        require(IGnosisSafe(safeAddress).isModuleEnabled(moduleAddress), "Module not enabled");

        // Find the previous module in the linked list
        address prevModule = _findPrevModule(safeAddress, moduleAddress);

        // Build the transaction data for disableModule
        bytes memory txData = abi.encodeWithSelector(IGnosisSafe.disableModule.selector, prevModule, moduleAddress);

        // Process the transaction
        _processTransaction(safeAddress, moduleAddress, txData, safeType, "REMOVE", executeIfReady);
    }

    /**
     * @notice Check the approval status for a module transaction
     * @param factoryAddress The CREATE2 factory address
     * @param safeType "guardian" or "deployer"
     * @param action "add" or "remove"
     */
    function checkStatus(address factoryAddress, string calldata safeType, string calldata action) external view {
        // Get Safe and module addresses
        (address safeAddress, address moduleAddress) = _getAddresses(factoryAddress, safeType);

        // Build the transaction data
        // slither-disable-next-line uninitialized-local
        bytes memory txData;
        if (keccak256(bytes(action)) == keccak256("add")) {
            txData = abi.encodeWithSelector(IGnosisSafe.enableModule.selector, moduleAddress);
        } else if (keccak256(bytes(action)) == keccak256("remove")) {
            address prevModule = _findPrevModule(safeAddress, moduleAddress);
            txData = abi.encodeWithSelector(IGnosisSafe.disableModule.selector, prevModule, moduleAddress);
        } else {
            revert("Invalid action - must be 'add' or 'remove'");
        }

        // Get the transaction hash
        bytes32 txHash = _getTransactionHash(safeAddress, txData);

        // Get approval info
        uint256 threshold = IGnosisSafe(safeAddress).getThreshold();
        address[] memory owners = IGnosisSafe(safeAddress).getOwners();
        uint256 approvalCount = _countApprovals(safeAddress, txHash, owners);

        // Log status
        Logger.logBoxHeader("Module Transaction Status");
        Logger.logKeyValue("Safe", safeAddress);
        Logger.logKeyValue("Module", moduleAddress);
        Logger.logKeyValue("Action", action);
        Logger.logKeyValue("Threshold", threshold);
        Logger.logKeyValue("Approvals", approvalCount);
        Logger.logEmptyLine();

        if (approvalCount >= threshold) {
            Logger.logIndented("Status: READY TO EXECUTE");
        } else {
            Logger.logIndented(
                string(
                    abi.encodePacked(
                        "Status: NEEDS ", StringUtils.toString(threshold - approvalCount), " MORE APPROVAL(S)"
                    )
                )
            );
        }

        Logger.logEmptyLine();
        Logger.logIndented("Owners who have approved:");
        for (uint256 i = 0; i < owners.length; i++) {
            // slither-disable-next-line calls-loop
            if (IGnosisSafe(safeAddress).approvedHashes(owners[i], txHash) == 1) {
                Logger.logKeyValue("  ", owners[i]);
            }
        }

        Logger.logEmptyLine();
        Logger.logBoxFooter();
    }

    /// @dev Process a module transaction (approve and optionally execute)
    function _processTransaction(
        address safeAddress,
        address moduleAddress,
        bytes memory txData,
        string calldata safeType,
        string memory action,
        bool executeIfReady
    ) internal {
        // Prompt for confirmation when running with --broadcast
        ScriptUtils.confirmBroadcastOrDryRun(vm, "SafeModuleTransaction");

        // Get the transaction hash
        bytes32 txHash = _getTransactionHash(safeAddress, txData);

        // Get threshold and current approvals
        uint256 threshold = IGnosisSafe(safeAddress).getThreshold();
        address[] memory owners = IGnosisSafe(safeAddress).getOwners();

        // Log header
        Logger.logBoxHeader(string(abi.encodePacked("Safe Module Transaction - ", action)));
        Logger.logKeyValue("Safe Type", safeType);
        Logger.logKeyValue("Safe", safeAddress);
        Logger.logKeyValue("Module", moduleAddress);
        Logger.logKeyValue("Threshold", threshold);
        Logger.logEmptyLine();

        // Check if sender is an owner
        bool isOwner = false;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == msg.sender) {
                isOwner = true;
                break;
            }
        }
        require(isOwner, "Sender is not a Safe owner");

        // Check if sender has already approved
        bool alreadyApproved = IGnosisSafe(safeAddress).approvedHashes(msg.sender, txHash) == 1;

        vm.startBroadcast();

        // Approve if not already done
        if (!alreadyApproved) {
            Logger.logIndented("Submitting approval...");
            IGnosisSafe(safeAddress).approveHash(txHash);
            Logger.logIndented("Approval submitted successfully");
        } else {
            Logger.logIndented("Already approved by this owner");
        }

        // Count approvals after our approval (includes the one we just submitted)
        uint256 approvalCount = _countApprovals(safeAddress, txHash, owners);

        Logger.logKeyValue("Approvals after this", approvalCount);

        // Execute if ready and requested
        if (executeIfReady && approvalCount >= threshold) {
            Logger.logEmptyLine();
            Logger.logIndented("Threshold met - executing transaction...");

            // Build signatures from approved hashes
            bytes memory signatures = _buildApprovedSignatures(safeAddress, txHash, owners, threshold);

            // Execute the transaction
            bool success = IGnosisSafe(safeAddress)
                .execTransaction(
                    safeAddress, // to (call the Safe itself)
                    0, // value
                    txData, // data
                    0, // operation (0 = Call)
                    0, // safeTxGas
                    0, // baseGas
                    0, // gasPrice
                    address(0), // gasToken
                    payable(address(0)), // refundReceiver
                    signatures // signatures
                );

            require(success, "Transaction execution failed");
            Logger.logIndented("Transaction executed successfully!");
        } else if (approvalCount < threshold) {
            Logger.logEmptyLine();
            Logger.logIndented(
                string(
                    abi.encodePacked(
                        "Need ", StringUtils.toString(threshold - approvalCount), " more approval(s) to execute"
                    )
                )
            );
        }

        vm.stopBroadcast();

        Logger.logEmptyLine();
        Logger.logBoxFooter();
    }

    /// @dev Get Safe and module addresses from deployment.toml via DeploymentConfig
    function _getAddresses(address factoryAddress, string calldata safeType)
        internal
        view
        returns (address safeAddress, address moduleAddress)
    {
        bool isGuardian = keccak256(bytes(safeType)) == keccak256("guardian");
        bool isDeployer = keccak256(bytes(safeType)) == keccak256("deployer");
        require(isGuardian || isDeployer, "Invalid safeType - must be 'guardian' or 'deployer'");

        if (isGuardian) {
            safeAddress = DeploymentConfig.getExpectedGuardianSafeAddress(vm, factoryAddress);
        } else {
            safeAddress = DeploymentConfig.getExpectedDeployerSafeAddress(vm, factoryAddress);
        }

        (address guardianModule, address deployerModule) =
            DeploymentConfig.getExpectedSafeExecutorModuleAddresses(vm, factoryAddress);
        moduleAddress = isGuardian ? guardianModule : deployerModule;
    }

    /// @dev Find the previous module in the linked list (needed for disableModule)
    function _findPrevModule(address safeAddress, address moduleAddress) internal view returns (address prevModule) {
        // SENTINEL_MODULES = address(0x1)
        address SENTINEL = address(0x1);
        (address[] memory modules,) = IGnosisSafe(safeAddress).getModulesPaginated(SENTINEL, 100);

        prevModule = SENTINEL;
        for (uint256 i = 0; i < modules.length; i++) {
            if (modules[i] == moduleAddress) {
                return prevModule;
            }
            prevModule = modules[i];
        }
        revert("Module not found in Safe");
    }

    /// @dev Get the Safe transaction hash
    function _getTransactionHash(address safeAddress, bytes memory txData) internal view returns (bytes32) {
        uint256 safeNonce = IGnosisSafe(safeAddress).nonce();
        return IGnosisSafe(safeAddress)
            .getTransactionHash(
                safeAddress, // to (call the Safe itself for module management)
                0, // value
                txData, // data
                0, // operation (0 = Call)
                0, // safeTxGas
                0, // baseGas
                0, // gasPrice
                address(0), // gasToken
                address(0), // refundReceiver
                safeNonce // _nonce
            );
    }

    /// @dev Count the number of owners who have approved the hash
    function _countApprovals(address safeAddress, bytes32 txHash, address[] memory owners)
        internal
        view
        returns (uint256 count)
    {
        for (uint256 i = 0; i < owners.length; i++) {
            // slither-disable-next-line calls-loop
            if (IGnosisSafe(safeAddress).approvedHashes(owners[i], txHash) == 1) {
                count++;
            }
        }
    }

    /// @dev Build signatures from approved hashes (sorted by owner address)
    function _buildApprovedSignatures(address safeAddress, bytes32 txHash, address[] memory owners, uint256 threshold)
        internal
        view
        returns (bytes memory signatures)
    {
        // Collect approving owners
        address[] memory approvers = new address[](threshold);
        uint256 approverCount = 0;

        for (uint256 i = 0; i < owners.length && approverCount < threshold; i++) {
            // slither-disable-next-line calls-loop
            if (IGnosisSafe(safeAddress).approvedHashes(owners[i], txHash) == 1) {
                approvers[approverCount] = owners[i];
                approverCount++;
            }
        }

        require(approverCount >= threshold, "Not enough approvals");

        // Sort approvers by address (ascending) - Safe requires sorted signatures
        for (uint256 i = 0; i < threshold - 1; i++) {
            for (uint256 j = i + 1; j < threshold; j++) {
                if (approvers[i] > approvers[j]) {
                    address temp = approvers[i];
                    approvers[i] = approvers[j];
                    approvers[j] = temp;
                }
            }
        }

        // Build signatures using approved hash signature type
        // For pre-approved hashes: r = owner address, s = 0, v = 1
        signatures = new bytes(threshold * 65);
        for (uint256 i = 0; i < threshold; i++) {
            // r = padded owner address (32 bytes)
            // s = 0 (32 bytes)
            // v = 1 (1 byte) - indicates approved hash
            bytes32 r = bytes32(uint256(uint160(approvers[i])));
            bytes32 s = bytes32(0);
            uint8 v = 1;

            // slither-disable-next-line assembly
            assembly {
                let sigPos := add(signatures, add(32, mul(i, 65)))
                mstore(sigPos, r)
                mstore(add(sigPos, 32), s)
                mstore8(add(sigPos, 64), v)
            }
        }
    }
}
