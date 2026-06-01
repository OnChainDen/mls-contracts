// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity >=0.7.0 <0.9.0;

/**
 * @title ISafe
 * @notice Minimal interface for Safe v1.4.1 functions needed by deployment/management scripts
 * @dev We define this locally rather than importing from the Safe library to avoid
 *      compiler version mismatch (Safe uses Solidity 0.7.6, platform scripts use 0.8.33).
 *
 *      This interface uses a floating pragma (>=0.7.0 <0.9.0) so it can be shared by scripts
 *      compiled under either toolchain.
 *
 * @author Den Technologies Inc
 */
interface ISafe {
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
