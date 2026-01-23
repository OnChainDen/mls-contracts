#! /bin/bash
pkill anvil

# Configuration
PORT="8001"
RPC_URL="http://127.0.0.1:$PORT"
ACCOUNT="test-singleton-factory-deployer"
SENDER="0x22002e8661A780d61EF4c86F4a9fFa843A6fea20"

# Start anvil local devnet
anvil --chain-id 420 --disable-default-create2-deployer -p $PORT &

# Wait for anvil to start
sleep 5

# Fund arachind funder
cast rpc anvil_setBalance $SENDER 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff --rpc-url $RPC_URL

# Fund Arachnid deployer
forge script script/DeployArachnidFactory.s.sol:DeployArachnidFactory --sig "fundDeployer()" --rpc-url $RPC_URL --account $ACCOUNT --sender $SENDER --broadcast -vvvv

# Deploy arachnid
forge script script/DeployArachnidFactory.s.sol:DeployArachnidFactory --sig "run()" --rpc-url $RPC_URL --account $ACCOUNT --sender $SENDER --broadcast -vvvv

# Deploy libraries using arachnid factory
forge script script/DeployLibraries.s.sol:DeployLibraries --sig "run(address)" "0x4e59b44847b379578588920cA78FbF26c0B4956C" --rpc-url $RPC_URL --account $ACCOUNT --sender $SENDER --broadcast -vvvv

# Deploy contracts using libraries
forge script script/DeployContracts.s.sol:DeployContracts \
      --sig "run(address)" "0x4e59b44847b379578588920cA78FbF26c0B4956C" \
      --rpc-url $RPC_URL \
      --account $ACCOUNT --sender $SENDER \
      --broadcast \
      -vvvv \
      --libraries src/organization/libraries/LibOrganizationPolicy.sol:LibOrganizationPolicy:0x0c39cb4F67AA70D53ceE37d4c88f11ffDb07E314 \
      --libraries src/organization/libraries/LibOrganizationAdmin.sol:LibOrganizationAdmin:0x744CaFa607273AF5664073d05BE066C6bDbf8201 \
      --libraries src/organization/libraries/LibOrganizationInitialization.sol:LibOrganizationInitialization:0x95A9CDA2a67E48b154d8EFa3B147f31eC6e8147E \
      --libraries src/organization/libraries/LibOrganizationAccountSignature.sol:LibOrganizationAccountSignature:0x6A6709A2c898E719A6Ee7635a3963122059655eB