// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Author: Nick Mudge
 * EIP-2535 Diamond Standard: https://eips.ethereum.org/EIPS/eip-2535
 *
 * Modified for Solidity ^0.8.24 and enhanced with guardian protection
 */
interface IDiamondCut {
    enum FacetCutAction {
        Add,
        Replace,
        Remove
    }
    // Add=0, Replace=1, Remove=2

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    /// @notice Add/replace/remove any number of functions and optionally execute
    ///         a function with delegatecall
    /// @param _diamondCut Contains the facet addresses and function selectors
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call, including function selector and arguments
    ///                  _calldata is executed with delegatecall on _init
    /// @param whitelistSetId The ID of the whitelisted facet set to validate against
    /// @param salt A user-provided salt for nonce computation (admin approval)
    /// @param chainId The chain ID for cross-chain replay protection
    /// @param signatures Admin signatures authorizing this diamond cut
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata,
        uint256 whitelistSetId,
        uint256 salt,
        uint256 chainId,
        bytes calldata signatures
    )
        external;

    event DiamondCut(FacetCut[] _diamondCut, address _init, bytes _calldata);
}
