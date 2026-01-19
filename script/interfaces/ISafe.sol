// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title ISafe
 * @notice Interface for Safe (Gnosis Safe) multisig wallet
 * @dev Minimal interface for Safe setup and configuration
 * @author Den Technologies Inc
 */
interface ISafe {
    /**
     * @notice Sets up the Safe with initial configuration
     * @param _owners List of Safe owners
     * @param _threshold Number of required confirmations for a Safe transaction
     * @param to Contract address for optional delegate call
     * @param data Data payload for optional delegate call
     * @param fallbackHandler Handler for fallback calls to this contract
     * @param paymentToken Token that should be used for the payment (0 is ETH)
     * @param payment Value that should be paid
     * @param paymentReceiver Address that should receive the payment (or 0 if tx.origin)
     */
    function setup(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;

    /**
     * @notice Returns the list of owners
     * @return owners List of Safe owners
     */
    function getOwners() external view returns (address[] memory owners);

    /**
     * @notice Returns the number of required confirmations
     * @return threshold The Safe threshold
     */
    function getThreshold() external view returns (uint256 threshold);

    /**
     * @notice Returns if the address is an owner
     * @param owner The address to check
     * @return isOwner True if the address is an owner
     */
    function isOwner(address owner) external view returns (bool isOwner);
}


/**
 * @title ISafeProxyFactory
 * @notice Interface for Safe Proxy Factory
 * @dev Used to deploy Safe proxy instances deterministically
 * @author Den Technologies Inc
 */
interface ISafeProxyFactory {
    /**
     * @notice Deploys a new proxy with CREATE2
     * @param singleton Address of singleton contract (master copy)
     * @param initializer Payload for message call sent to new proxy contract
     * @param saltNonce Nonce that will be used to generate the salt
     * @return proxy Address of the deployed Safe proxy
     */
    function createProxyWithNonce(address singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);

    /**
     * @notice Computes the address of a proxy that would be deployed
     * @param singleton Address of singleton contract (master copy)
     * @param initializer Payload for message call sent to new proxy contract
     * @param saltNonce Nonce that will be used to generate the salt
     * @return proxy Address of the proxy that would be deployed
     */
    function calculateCreateProxyWithNonceAddress(address singleton, bytes calldata initializer, uint256 saltNonce)
        external
        returns (address proxy);

    /**
     * @notice Returns the chain ID stored in the proxy factory
     * @return chainId The chain ID
     */
    function getChainId() external view returns (uint256 chainId);

    /**
     * @notice Returns the creation code of the proxy
     * @return creationCode The proxy creation code
     */
    function proxyCreationCode() external pure returns (bytes memory creationCode);
}
