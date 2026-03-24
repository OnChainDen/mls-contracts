// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {MockGuardianSafe} from "test/helpers/MockGuardianSafe.sol";

/**
 * @dev Guardian-safe mock that also supports ERC-1271 signer recovery for direct guardian matches.
 */
contract MockGuardianSafeERC1271 is MockGuardianSafe, IERC1271 {
    /// @dev Returns the ERC-1271 magic value for any signature.
    function isValidSignature(bytes32, bytes memory) external pure override returns (bytes4) {
        return IERC1271.isValidSignature.selector;
    }
}

/**
 * @dev Mock contract whose fallback always reverts.
 */
contract MockGuardianModuleReverter {
    fallback() external payable {
        revert("module-check-reverted");
    }
}

/**
 * @dev Mock contract returning non-boolean 32-byte data for module checks.
 */
contract MockGuardianModuleUnexpectedReturn {
    fallback() external payable {
        assembly {
            mstore(0x00, 2)
            return(0x00, 32)
        }
    }
}
