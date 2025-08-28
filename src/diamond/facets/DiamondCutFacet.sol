// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Author: Nick Mudge
 * EIP-2535 Diamond Standard: https://eips.ethereum.org/EIPS/eip-2535
 *
 * Modified for Solidity ^0.8.24 and enhanced with guardian protection
 */
import "../interfaces/IDiamondCut.sol";
import "../libraries/LibDiamond.sol";
import "../../storage/AccountStorage.sol";
import "../../storage/OrganizationStorage.sol";

/**
 * @title Admin Facet Interface
 * @notice Interface for admin validation functions
 */
interface IAdminFacet {
    function validateAdminAuthorization(
        OrganizationStorage.AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        external;
}

contract DiamondCutFacet is IDiamondCut {
    /**
     * @notice Error thrown when admin validation fails
     */
    error AdminValidationFailed(string reason);

    /**
     * @notice Modifier to restrict function access to the guardian address only
     */
    modifier onlyGuardian() {
        LibDiamond.enforceIsGuardian();
        _;
    }

    /// @notice Add/replace/remove any number of functions and optionally execute
    ///         a function with delegatecall
    /// @param _diamondCut Contains the facet addresses and function selectors
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call, including function selector and arguments
    ///                  _calldata is executed with delegatecall on _init
    /// @param salt A user-provided salt for nonce computation (admin approval)
    /// @param chainId The chain ID for cross-chain replay protection
    /// @param signatures Admin signatures authorizing this diamond cut
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata,
        uint256 salt,
        uint256 chainId,
        bytes calldata signatures
    )
        external
        override
        onlyGuardian
    {
        // Validate admin authorization
        _validateAdminAuthorization(_diamondCut, _init, _calldata, salt, chainId, signatures);

        // Perform the diamond cut using the internal function (no admin validation)
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }

    /**
     * @notice Validates admin authorization for diamond cutting operations
     * @dev Determines if this is an Account or Organization diamond and calls the appropriate admin facet
     * @param _diamondCut The diamond cut operations
     * @param _init The initialization contract address
     * @param _calldata The initialization call data
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection
     * @param signatures The signatures from admin(s) authorizing this operation
     */
    function _validateAdminAuthorization(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata,
        uint256 salt,
        uint256 chainId,
        bytes calldata signatures
    )
        internal
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(_diamondCut, _init, _calldata);

        // This is an Account diamond - validate through AccountAdminFacet
        try IAdminFacet(address(this)).validateAdminAuthorization(
            OrganizationStorage.AdminOperationType.DiamondCut, operationData, salt, chainId, signatures
        ) {
            return; // Validation successful
        } catch Error(string memory reason) {
            revert AdminValidationFailed(reason);
        } catch {
            revert AdminValidationFailed("Admin validation failed");
        }
    }
}
