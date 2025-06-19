import { type DeployFunction } from 'hardhat-deploy/types'

import { EndpointId, endpointIdToNetwork } from '@layerzerolabs/lz-definitions'
import { getDeploymentAddressAndAbi } from '@layerzerolabs/lz-evm-sdk-v2'

const contractName = 'OrbitERC20OFTAdapter'

const deploy: DeployFunction = async (hre) => {
    const { deploy } = hre.deployments
    const signer = (await hre.ethers.getSigners())[0]
    console.log(`deploying ${contractName} on network: ${hre.network.name} with ${signer.address}`)

    const eid = hre.network.config.eid as EndpointId
    const lzNetworkName = endpointIdToNetwork(eid)

    const { address } = getDeploymentAddressAndAbi(lzNetworkName, 'EndpointV2')

    const plumeERC20Address = '0x4C1746A800D224393fE2470C70A35717eD4eA5F1' // Plume ERC20 Address on Ethereum
    const bridgeAddress = '0x35381f63091926750F43b2A7401B083263aDEF83' // ERC20Bridge Address for Plume token on Ethereum

    await deploy(contractName, {
        from: signer.address,
        args: [plumeERC20Address, address, signer.address, bridgeAddress], // replace '0x' with the address of the ERC-20 token
        log: true,
        waitConfirmations: 1,
        skipIfAlreadyDeployed: false,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
            owner: signer.address,
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [signer.address],
                },
            },
        },
    })
}

deploy.tags = [contractName]

export default deploy

// TODO for OrbitERC20OFTAdapter -- get arbitrum native ERC20 Brige address