import { Contract, Wallet } from 'ethers'
import { Web3Provider } from 'ethers/providers'
import { defaultAbiCoder } from 'ethers/utils'
import { deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './utilities'

import ERC20 from '../../build/ERC20.json'
import WETH9 from '../../build/WETH9.json'
import DXswapFactory from '../../build/DXswapFactory.json'
import DXswapPair from '../../build/DXswapPair.json'
import DXswapDeployer from '../../build/DXswapDeployer.json'
import DXswapFeeSetter from '../../build/DXswapFeeSetter.json'
import DXswapFeeReceiver from '../../build/DXswapFeeReceiver.json'

interface FactoryFixture {
  factory: Contract
  feeSetter: Contract
  feeReceiver: Contract
}

const overrides = {
  gasLimit: 9999999
}

export async function factoryFixture(provider: Web3Provider, [dxdao]: Wallet[]): Promise<FactoryFixture> {
  const WETH = await deployContract(dxdao, WETH9)
  const dxSwapDeployer = await deployContract(
    dxdao, DXswapDeployer, [ dxdao.address, WETH.address, [], [], [], ], overrides
  )
  await dxdao.sendTransaction({to: dxSwapDeployer.address, gasPrice: 0, value: 1})
  const deployTx = await dxSwapDeployer.deploy()
  const deployTxReceipt = await provider.getTransactionReceipt(deployTx.hash);
  const factoryAddress = deployTxReceipt.logs !== undefined
    ? defaultAbiCoder.decode(['address'], deployTxReceipt.logs[0].data)[0]
    : null
  const factory = new Contract(factoryAddress, JSON.stringify(DXswapFactory.abi), provider).connect(dxdao)
  const feeSetterAddress = await factory.feeToSetter()
  const feeSetter = new Contract(feeSetterAddress, JSON.stringify(DXswapFeeSetter.abi), provider).connect(dxdao)
  const feeReceiverAddress = await factory.feeTo()
  const feeReceiver = new Contract(feeReceiverAddress, JSON.stringify(DXswapFeeReceiver.abi), provider).connect(dxdao)
  return { factory, feeSetter, feeReceiver }
}

interface PairFixture extends FactoryFixture {
  token0: Contract
  token1: Contract
  pair: Contract
}

export async function pairFixture(provider: Web3Provider, [dxdao]: Wallet[]): Promise<PairFixture> {
  const tokenA = await deployContract(dxdao, ERC20, [expandTo18Decimals(10000)], overrides)
  const tokenB = await deployContract(dxdao, ERC20, [expandTo18Decimals(10000)], overrides)
  const WETH = await deployContract(dxdao, WETH9)

  const dxSwapDeployer = await deployContract(
    dxdao, DXswapDeployer, [
      dxdao.address,
      WETH.address,
      [tokenA.address],
      [tokenB.address],
      [15],
    ], overrides
  )
  await dxdao.sendTransaction({to: dxSwapDeployer.address, gasPrice: 0, value: 1})
  const deployTx = await dxSwapDeployer.deploy()
  const deployTxReceipt = await provider.getTransactionReceipt(deployTx.hash);
  const factoryAddress = deployTxReceipt.logs !== undefined
    ? defaultAbiCoder.decode(['address'], deployTxReceipt.logs[0].data)[0]
    : null
  
  const factory = new Contract(factoryAddress, JSON.stringify(DXswapFactory.abi), provider).connect(dxdao)
  const feeSetterAddress = await factory.feeToSetter()
  const feeSetter = new Contract(feeSetterAddress, JSON.stringify(DXswapFeeSetter.abi), provider).connect(dxdao)
  const feeReceiverAddress = await factory.feeTo()
  const feeReceiver = new Contract(feeReceiverAddress, JSON.stringify(DXswapFeeReceiver.abi), provider).connect(dxdao)
  const pairAddress = await factory.getPair(tokenA.address, tokenB.address)
  const pair = new Contract(pairAddress, JSON.stringify(DXswapPair.abi), provider).connect(dxdao)

  const token0Address = await pair.token0()
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA

  return { factory, feeSetter, feeReceiver, token0, token1, pair }
}
