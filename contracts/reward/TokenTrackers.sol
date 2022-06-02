// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./RewardTracker.sol";

contract StakedMvxTracker is RewardTracker {
    constructor() public RewardTracker("Staked MVX", "sMVX") {}
}

contract BonusMvxTracker is RewardTracker {
    constructor() public RewardTracker("Staked + Bonus MVX", "sbMVX") {}
}

contract FeeMvxTracker is RewardTracker {
    constructor() public RewardTracker("Staked + Bonus + Fee MVX", "sbfMVX") {}
}

contract StakedMvlpTracker is RewardTracker {
    constructor() public RewardTracker("Fee + Staked MVLP", "fsMVLP") {}
}

contract FeeMvlpTracker is RewardTracker {
    constructor() public RewardTracker("Fee MVLP", "fMVLP") {}
}
