// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @dev Shared array-construction helpers for tests.
 *      Centralizes small deterministic array builders so suites can stay focused on behavior under test.
 */
abstract contract ArrayBuilders {
    /**
     * @dev Builds a one-element address array.
     */
    function buildArray(address a) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = a;
    }

    /**
     * @dev Builds a two-element address array.
     */
    function buildArray(address a, address b) internal pure returns (address[] memory values) {
        values = new address[](2);
        values[0] = a;
        values[1] = b;
    }

    /**
     * @dev Builds a three-element address array.
     */
    function buildArray(address a, address b, address c) internal pure returns (address[] memory values) {
        values = new address[](3);
        values[0] = a;
        values[1] = b;
        values[2] = c;
    }

    /**
     * @dev Builds a four-element address array.
     */
    function buildArray(address a, address b, address c, address d) internal pure returns (address[] memory values) {
        values = new address[](4);
        values[0] = a;
        values[1] = b;
        values[2] = c;
        values[3] = d;
    }

    /**
     * @dev Builds an empty address array.
     */
    function buildEmptyAddressArray() internal pure returns (address[] memory values) {
        values = new address[](0);
    }

    /**
     * @dev Builds a one-element uint256 array.
     */
    function buildUint256Array(uint256 a) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = a;
    }

    /**
     * @dev Builds a two-element uint256 array.
     */
    function buildUint256Array(uint256 a, uint256 b) internal pure returns (uint256[] memory values) {
        values = new uint256[](2);
        values[0] = a;
        values[1] = b;
    }

    /**
     * @dev Builds a three-element uint256 array.
     */
    function buildUint256Array(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory values) {
        values = new uint256[](3);
        values[0] = a;
        values[1] = b;
        values[2] = c;
    }
}
