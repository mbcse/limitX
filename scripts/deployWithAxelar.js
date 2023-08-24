const { artifacts, ethers, upgrades } = require('hardhat')
const getNamedSigners = require('../utils/getNamedSigners')
const saveToConfig = require('../utils/saveToConfig')
const readFromConfig = require('../utils/readFromConfig')
const deploySettings = require('./deploySettings')

async function main () {

  const chainId = await hre.getChainId()
  console.log("STARTING LimitX DEPLOYMENT ON ", chainId)

  const CHAIN_NAME = deploySettings[chainId].CHAIN_NAME
  
  const AXELAR_GATEWAY_ADDRESS = deploySettings[chainId].AXELAR_GATEWAY_ADDRESS
  const AXELAR_GAS_RECIEVER_ADDRESS = deploySettings[chainId].AXELAR_GAS_RECIEVER_ADDRESS
  const LINK_TOKEN_ADDRESS = deploySettings[chainId].LINK_TOKEN_ADDRESS
  const WETH_ADDRESS = deploySettings[chainId].WETH_ADDRESS
  const SWAP_ROUTER_ADDRESS = deploySettings[chainId].SWAP_ROUTER_ADDRESS
  const UPKEEPER_REGISTRAR_ADDRESS = deploySettings[chainId].UPKEEPER_REGISTRAR_ADDRESS
  const UPKEEPER_REGISTRY_ADDRESS = deploySettings[chainId].UPKEEPER_REGISTRY_ADDRESS
  const WRAPPED_NATIVE_TOKEN_ADDRESS = deploySettings[chainId].WRAPPED_NATIVE_TOKEN_ADDRESS


  console.log('Deploying LimitX Smart Contract')
  const {payDeployer} =  await getNamedSigners();

  const LIMITX_CONTRACT = await ethers.getContractFactory('LimitX')
  LIMITX_CONTRACT.connect(payDeployer)


  const ABI = (await artifacts.readArtifact('LimitX')).abi
  await saveToConfig(`LimitX_${CHAIN_NAME}`, 'ABI', ABI)

  const limitXDeployer = await LIMITX_CONTRACT.deploy(
    AXELAR_GATEWAY_ADDRESS,
    AXELAR_GAS_RECIEVER_ADDRESS,
    SWAP_ROUTER_ADDRESS,
    LINK_TOKEN_ADDRESS,
    UPKEEPER_REGISTRAR_ADDRESS,
    UPKEEPER_REGISTRY_ADDRESS,
    WETH_ADDRESS,
    WRAPPED_NATIVE_TOKEN_ADDRESS
  )
  await limitXDeployer.deployed()

  await saveToConfig(`LIMITX_${CHAIN_NAME}`, 'ADDRESS', limitXDeployer.address)
  console.log('LimitX contract deployed to:', limitXDeployer.address, ` on ${CHAIN_NAME}`)

  await new Promise((resolve) => setTimeout(resolve, 40 * 1000));
  console.log('Verifying Contract...')

  try {
    await run('verify:verify', {
      address: limitXDeployer.address || "0xDCD300706887ac0E4d69433c3a5C2E75ED7F3c34",
      contract: 'contracts/LimitX.sol:LimitX', // Filename.sol:ClassName
      constructorArguments: [
        AXELAR_GATEWAY_ADDRESS,
        AXELAR_GAS_RECIEVER_ADDRESS,
        SWAP_ROUTER_ADDRESS,
        LINK_TOKEN_ADDRESS,
        UPKEEPER_REGISTRAR_ADDRESS,
        UPKEEPER_REGISTRY_ADDRESS,
        WETH_ADDRESS,
        WRAPPED_NATIVE_TOKEN_ADDRESS
      ],
      network: deploySettings[chainId].NETWORK_NAME
    })
  } catch (error) {
    console.log(error)
  }

}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
