// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import "../interfaces/IStakeManager.sol";

/* solhint-disable avoid-low-level-calls */
/* solhint-disable not-rely-on-time */

/**
 * @title StakeManager
 * @notice 存款与质押管理（由 EntryPoint 继承）
 *
 * ## 存款（Deposit）
 * - 账户或 Paymaster 可向 EntryPoint 存入 ETH，用于支付 UserOperation 的 gas
 * - handleOps 执行前会从对应地址的 deposit 中扣减 prefund，执行后按实际消耗结算，多退少不补（不足则 revert）
 *
 * ## 质押（Stake）
 * - 主要为 Paymaster 设计：锁定 ETH 并设置 unstakeDelaySec，到期前不可提取
 * - 用于防止恶意 Paymaster 作恶后立刻撤资；Bundler 可要求 Paymaster 具备足够 stake 才打包其 UserOp
 */
abstract contract StakeManager is IStakeManager {
    /// @dev 每个地址（账户或 Paymaster）的存款与质押信息
    mapping(address => DepositInfo) private deposits;

    /// @inheritdoc IStakeManager
    function getDepositInfo(
        address account
    ) external virtual view returns (DepositInfo memory info) {
        return deposits[account];
    }

    /**
     * Internal method to return just the stake info.
     * @param addr - The account to query.
     */
    function _getStakeInfo(
        address addr
    ) internal virtual view returns (StakeInfo memory info) {
        DepositInfo storage depositInfo = deposits[addr];
        info.stake = depositInfo.stake;
        info.unstakeDelaySec = depositInfo.unstakeDelaySec;
    }

    /// @inheritdoc IStakeManager
    function balanceOf(address account) public virtual view returns (uint256) {
        return deposits[account].deposit;
    }

    receive() external payable {
        depositTo(msg.sender);
    }

    /**
     * Increments an account's deposit.
     * @param account - The account to increment.
     * @param amount  - The amount to increment by.
     * @return the updated deposit of this account
     */
    function _incrementDeposit(address account, uint256 amount) internal virtual returns (uint256) {
        unchecked {
            DepositInfo storage info = deposits[account];
            uint256 newAmount = info.deposit + amount;
            info.deposit = newAmount;
            return newAmount;
        }
    }

    /**
     * Try to decrement the account's deposit.
     * @param account - The account to decrement.
     * @param amount  - The amount to decrement by.
     * @return true if the decrement succeeded (that is, previous balance was at least that amount)
     */
    function _tryDecrementDeposit(address account, uint256 amount) internal virtual returns (bool) {
        unchecked {
            DepositInfo storage info = deposits[account];
            uint256 currentDeposit = info.deposit;
            if (currentDeposit < amount) {
                return false;
            }
            info.deposit = currentDeposit - amount;
            return true;
        }
    }

    /// @inheritdoc IStakeManager
    function depositTo(address account) public virtual payable {
        uint256 newDeposit = _incrementDeposit(account, msg.value);
        emit Deposited(account, newDeposit);
    }

    /// @inheritdoc IStakeManager
    function addStake(uint32 unstakeDelaySec) external virtual payable {
        DepositInfo storage info = deposits[msg.sender];
        require(unstakeDelaySec > 0, InvalidUnstakeDelay(unstakeDelaySec, info.unstakeDelaySec));
        require(
            unstakeDelaySec >= info.unstakeDelaySec,
            InvalidUnstakeDelay(unstakeDelaySec, info.unstakeDelaySec)
        );
        uint256 stake = info.stake + msg.value;
        require(stake > 0, InvalidStake(msg.value, info.stake));
        require(stake <= type(uint112).max, InvalidStake(msg.value, info.stake));
        deposits[msg.sender] = DepositInfo(
            info.deposit,
            true,
            uint112(stake),
            unstakeDelaySec,
            0
        );
        emit StakeLocked(msg.sender, stake, unstakeDelaySec);
    }

    /// @inheritdoc IStakeManager
    function unlockStake() external virtual {
        DepositInfo storage info = deposits[msg.sender];
        require(info.unstakeDelaySec != 0, NotStaked(info.stake, info.unstakeDelaySec, info.staked));
        require(info.staked, NotStaked(info.stake, info.unstakeDelaySec, info.staked));
        uint48 withdrawTime = uint48(block.timestamp) + info.unstakeDelaySec;
        info.withdrawTime = withdrawTime;
        info.staked = false;
        emit StakeUnlocked(msg.sender, withdrawTime);
    }

    /// @inheritdoc IStakeManager
    function withdrawStake(address payable withdrawAddress) external virtual {
        DepositInfo storage info = deposits[msg.sender];
        uint256 stake = info.stake;
        require(stake > 0, NotStaked(info.stake, info.unstakeDelaySec, info.staked));
        require(info.withdrawTime > 0, StakeNotUnlocked(info.withdrawTime, block.timestamp));
        require(
            info.withdrawTime <= block.timestamp,
            WithdrawalNotDue(info.withdrawTime, block.timestamp)
        );
        info.unstakeDelaySec = 0;
        info.withdrawTime = 0;
        info.stake = 0;
        emit StakeWithdrawn(msg.sender, withdrawAddress, stake);
        (bool success, bytes memory ret) = withdrawAddress.call{value: stake}("");
        require(success, StakeWithdrawalFailed(msg.sender, withdrawAddress, stake, ret));
    }

    /// @inheritdoc IStakeManager
    function withdrawTo(
        address payable withdrawAddress,
        uint256 withdrawAmount
    ) external virtual {
        DepositInfo storage info = deposits[msg.sender];
        uint256 currentDeposit = info.deposit;
        require(withdrawAmount <= currentDeposit, InsufficientDeposit(currentDeposit, withdrawAmount));
        info.deposit = currentDeposit - withdrawAmount;
        emit Withdrawn(msg.sender, withdrawAddress, withdrawAmount);
        (bool success, bytes memory ret) = withdrawAddress.call{value: withdrawAmount}("");
        require(success, DepositWithdrawalFailed(msg.sender, withdrawAddress, withdrawAmount, ret));
    }
}
