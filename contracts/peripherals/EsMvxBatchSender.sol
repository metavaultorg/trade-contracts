// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/token/IERC20.sol";
import "../libraries/math/SafeMath.sol";

import "../staking/interfaces/IVester.sol";
import "../staking/interfaces/IRewardTracker.sol";
import "../access/Governable.sol";


contract EsMvxBatchSender is Governable{
    using SafeMath for uint256;

    address public esMvx;

    constructor(address _esMvx) public {
        esMvx = _esMvx;
    }

    function send(
        IVester _vester,
        uint256 _minRatio,
        address[] memory _accounts,
        uint256[] memory _amounts
    ) external onlyGov {
        IRewardTracker rewardTracker = IRewardTracker(_vester.rewardTracker());

        for (uint256 i = 0; i < _accounts.length; i++) {
            IERC20(esMvx).transferFrom(msg.sender, _accounts[i], _amounts[i]);

            uint256 nextTransferredCumulativeReward = _vester.transferredCumulativeRewards(_accounts[i]).add(_amounts[i]);
            _vester.setTransferredCumulativeRewards(_accounts[i], nextTransferredCumulativeReward);

            uint256 cumulativeReward = rewardTracker.cumulativeRewards(_accounts[i]);
            uint256 totalCumulativeReward = cumulativeReward.add(nextTransferredCumulativeReward);

            uint256 combinedAverageStakedAmount = _vester.getCombinedAverageStakedAmount(_accounts[i]);

            if (combinedAverageStakedAmount > totalCumulativeReward.mul(_minRatio)) {
                continue;
            }

            uint256 nextTransferredAverageStakedAmount = _minRatio.mul(totalCumulativeReward);
            nextTransferredAverageStakedAmount = nextTransferredAverageStakedAmount.sub(
                rewardTracker.averageStakedAmounts(_accounts[i]).mul(cumulativeReward).div(totalCumulativeReward)
            );

            nextTransferredAverageStakedAmount = nextTransferredAverageStakedAmount.mul(totalCumulativeReward).div(nextTransferredCumulativeReward);

            _vester.setTransferredAverageStakedAmounts(_accounts[i], nextTransferredAverageStakedAmount);
        }
    }
}
