// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./RewardDistributor.sol";
import "./BonusDistributor.sol";

contract StakedMvxDistributor is RewardDistributor {
    constructor(address _rewardToken, address _rewardTracker) public RewardDistributor(_rewardToken, _rewardTracker) {}
}

contract BonusMvxDistributor is BonusDistributor {
    constructor(address _rewardToken, address _rewardTracker) public BonusDistributor(_rewardToken, _rewardTracker) {}
}

contract FeeMvxDistributor is RewardDistributor {
    constructor(address _rewardToken, address _rewardTracker) public RewardDistributor(_rewardToken, _rewardTracker) {}
}

contract StakedMvlpDistributor is RewardDistributor {
    constructor(address _rewardToken, address _rewardTracker) public RewardDistributor(_rewardToken, _rewardTracker) {}
}

contract FeeMvlpDistributor is RewardDistributor {
    constructor(address _rewardToken, address _rewardTracker) public RewardDistributor(_rewardToken, _rewardTracker) {}
}
