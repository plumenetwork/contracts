import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { TwoWayConfig, generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OAppEnforcedOption } from '@layerzerolabs/toolbox-hardhat'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

const ethereumContract: OmniPointHardhat = {
    eid: EndpointId.ETHEREUM_V2_MAINNET,
    contractName: 'OrbitERC20OFTAdapterUpgradeable',
}

const plumeContract: OmniPointHardhat = {
    eid: EndpointId.PLUMEPHOENIX_V2_MAINNET,
    contractName: 'OrbitNativeOFTAdapterUpgradeable',
}

const existingEthereumPlumeOFTAdapterContract: OmniPointHardhat = {
    eid: EndpointId.ETHEREUM_V2_MAINNET,
    address: '0xbDA8a2285F4C3e75b37E467C4DB9bC633FfbD29d',
}

const plumeDummyContract: OmniPointHardhat = {
    eid: EndpointId.PLUMEPHOENIX_V2_MAINNET,
    contractName: 'PlumeOFTMock',
}

// To connect all the above chains to each other, we need the following pathways:
// Optimism <-> Arbitrum

// For this example's simplicity, we will use the same enforced options values for sending to all chains
// For production, you should ensure `gas` is set to the correct value through profiling the gas usage of calling OFT._lzReceive(...) on the destination chain
// To learn more, read https://docs.layerzero.network/v2/concepts/applications/oapp-standard#execution-options-and-enforced-settings
const EVM_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
    {
        msgType: 1,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 80000,
        value: 0,
    },
]
// With the config generator, pathways declared are automatically bidirectional
// i.e. if you declare A,B there's no need to declare B,A
const pathways: TwoWayConfig[] = [
    [
        ethereumContract, // Chain A contract
        plumeContract, // Chain C contract
        [['LayerZero Labs'], []], // [ requiredDVN[], [ optionalDVN[], threshold ] ] // TODO update dvns
        [1, 1], // [A to B confirmations, B to A confirmations] // TODO update confirmations
        [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Chain C enforcedOptions, Chain A enforcedOptions // TODO confirm this
    ],
    [
        // TODO this cannot be done by LZ -- Plume owns existing PlumeOFTAdapter contract on Ethereum
        existingEthereumPlumeOFTAdapterContract, // Chain A contract
        plumeDummyContract, // Chain C contract
        [['LayerZero Labs'], []], // [ requiredDVN[], [ optionalDVN[], threshold ] ] // TODO update dvns
        [1, 1], // [A to B confirmations, B to A confirmations] // TODO update confirmations
        [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Chain C enforcedOptions, Chain A enforcedOptions // TODO confirm this
    ],
]

export default async function () {
    // Generate the connections config based on the pathways
    const connections = await generateConnectionsConfig(pathways)
    return {
        contracts: [{ contract: ethereumContract }, { contract: plumeContract }],
        connections,
    }
}
