// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IRewardRouter {
    function stakeMvx(uint256 _amount) external;
    
    function stakeEsMvx(uint256 _amount) external;

    function unstakeMvx(uint256 _amount) external;

    function unstakeEsMvx(uint256 _amount) external;

    function signalTransfer(address _receiver) external;

    function compound() external;

    function handleRewards(
        bool _shouldClaimMvx,
        bool _shouldStakeMvx,
        bool _shouldClaimEsMvx,
        bool _shouldStakeEsMvx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth,
        bool _shouldAddIntoMVLP,
        bool _shouldConvertMvxAndStake
    ) external returns (uint256 amountOut);
}
