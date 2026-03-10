/**
 * Create2Factory - 确定性合约部署工厂
 *
 * 基于 EIP-1014 (CREATE2) 和 Nick's Factory 确定性部署代理，
 * 实现在任意链上通过相同 salt + initCode 得到相同合约地址的部署能力。
 * 用于 ERC-4337 账户抽象中预测 SimpleAccount 等合约地址。
 *
 * @see https://github.com/Arachnid/deterministic-deployment-proxy
 */
import { BigNumber, BigNumberish, ethers, Signer } from 'ethers'
import { arrayify, hexConcat, hexlify, hexZeroPad, keccak256 } from 'ethers/lib/utils'
import { Provider } from '@ethersproject/providers'
import { TransactionRequest } from '@ethersproject/abstract-provider'

export class Create2Factory {
  /** 是否已部署过链上工厂（避免重复部署） */
  factoryDeployed = false

  /** 确定性部署代理合约的预设地址（各链相同） */
  static readonly contractAddress = '0x4e59b44847b379578588920ca78fbf26c0b4956c'
  /** 部署该代理的原始交易数据（无 nonce 依赖，可重放） */
  static readonly factoryTx = '0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222'
  /** 需要向其转 ETH 以触发 factoryTx 的部署者地址 */
  static readonly factoryDeployer = '0x3fab184622dc19b6109349b94811493bf2a45362'
  static readonly deploymentGasPrice = 100e9
  static readonly deploymentGasLimit = 100000
  /** 部署工厂所需 ETH = gasPrice * gasLimit */
  static readonly factoryDeploymentFee = (Create2Factory.deploymentGasPrice * Create2Factory.deploymentGasLimit).toString()

  constructor (readonly provider: Provider,
    readonly signer = (provider as ethers.providers.JsonRpcProvider).getSigner()) {
  }

  /**
   * 使用确定性部署代理部署合约（CREATE2）。
   * 会先确保链上代理已部署，再通过代理执行部署。
   * 注意：若该地址已有代码，会直接返回地址而不再发交易。
   *
   * @param initCode 部署字节码，可为 hex 或 factory.getDeploymentTransaction(..) 的 data
   * @param salt CREATE2 盐值，相同 initCode + salt 得到相同地址
   * @param gasLimit 可选：数值、'estimate' 用 estimateGas，不传则按 initCode 长度估算
   * @returns 部署后的合约地址
   */
  async deploy (initCode: string | TransactionRequest, salt: BigNumberish = 0, gasLimit?: BigNumberish | 'estimate'): Promise<string> {
    await this.deployFactory()
    if (typeof initCode !== 'string') {
      // eslint-disable-next-line @typescript-eslint/no-base-to-string
      initCode = (initCode as TransactionRequest).data!.toString()
    }

    const addr = Create2Factory.getDeployedAddress(initCode, salt)
    if (await this.provider.getCode(addr).then(code => code.length) > 2) {
      return addr
    }

    const deployTx = {
      to: Create2Factory.contractAddress,
      data: this.getDeployTransactionCallData(initCode, salt)
    }
    if (gasLimit === 'estimate') {
      gasLimit = await this.signer.estimateGas(deployTx)
    }

    // manual estimation (its bit larger: we don't know actual deployed code size)
    if (gasLimit === undefined) {
      gasLimit = arrayify(initCode)
        .map(x => x === 0 ? 4 : 16)
        .reduce((sum, x) => sum + x) +
        200 * initCode.length / 2 + // actual is usually somewhat smaller (only deposited code, not entire constructor)
        6 * Math.ceil(initCode.length / 64) + // hash price. very minor compared to deposit costs
        32000 +
        21000

      // deployer requires some extra gas
      gasLimit = Math.floor(gasLimit * 64 / 63)
    }

    await this.signer.sendTransaction({ ...deployTx, gasLimit }).then(async tx => tx.wait())

    if (await this.provider.getCode(addr).then(code => code.length) === 2) {
      throw new Error('failed to deploy')
    }
    return addr
  }

  /**
   * 构造调用确定性部署代理的 calldata：keccak256(salt || initCode) 后由代理 CREATE2 部署。
   */
  getDeployTransactionCallData (initCode: string, salt: BigNumberish = 0): string {
    const saltBytes32 = hexZeroPad(hexlify(salt), 32)
    return hexConcat([
      saltBytes32,
      initCode
    ])
  }

  /**
   * 根据 initCode 和 salt 计算将部署出的合约地址（不发起交易）。
   * 公式：address = last20(keccak256(0xff || proxyAddress || salt || keccak256(initCode)))
   *
   * @param initCode 部署字节码
   * @param salt CREATE2 盐值
   * @returns 部署后的合约地址
   */
  static getDeployedAddress (initCode: string, salt: BigNumberish): string {
    const saltBytes32 = hexZeroPad(hexlify(salt), 32)
    return '0x' + keccak256(hexConcat([
      '0xff',
      Create2Factory.contractAddress,
      saltBytes32,
      keccak256(initCode)
    ])).slice(-40)
  }

  // deploy the factory, if not already deployed.
  async deployFactory (signer?: Signer): Promise<void> {
    if (await this._isFactoryDeployed()) {
      return
    }

    await (signer ?? this.signer).sendTransaction({
      to: Create2Factory.factoryDeployer,
      value: BigNumber.from(Create2Factory.factoryDeploymentFee)
    })
    // (with latest geth, can't tx.wait on the very first tx: reverts with "transaction indexing is in progress")
    await new Promise(resolve => setTimeout(resolve, 100))

    await this.provider.sendTransaction(Create2Factory.factoryTx).then(async tx => tx.wait())

    if (!await this._isFactoryDeployed()) {
      throw new Error('fatal: failed to deploy deterministic deployer')
    }
  }

  async _isFactoryDeployed (): Promise<boolean> {
    if (!this.factoryDeployed) {
      const deployed = await this.provider.getCode(Create2Factory.contractAddress)
      if (deployed.length > 2) {
        this.factoryDeployed = true
      }
    }
    return this.factoryDeployed
  }
}
