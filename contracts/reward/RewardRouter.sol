// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/token/TransferHelper.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IVester.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../core/interfaces/IMvlpManager.sol";
import "../core/interfaces/IVault.sol";
import "../access/Governable.sol";
import "../peripherals/interfaces/ISwapRouter.sol";

contract RewardRouter is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;


    ISwapRouter public immutable swapRouter;

    address public vault;
    address public usdc;
    address public mvx;
    address public esMvx;
    address public bnMvx;

    address public mvlp; // MVX Liquidity Provider token

    address public stakedMvxTracker;
    address public bonusMvxTracker;
    address public feeMvxTracker;

    address public stakedMvlpTracker;
    address public feeMvlpTracker;

    address public mvlpManager;

    address public mvxVester;
    address public mvlpVester;

    mapping(address => address) public pendingReceivers;

    event StakeMvx(address account, address token, uint256 amount);
    event UnstakeMvx(address account, address token, uint256 amount);

    event StakeMvlp(address account, uint256 amount);
    event UnstakeMvlp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    uint24 public constant MVX_USDC_POOL_FEE = 10000;

    constructor(address _swapRouter,
        address _weth,
        address _mvx,
        address _esMvx,
        address _bnMvx,
        address _mvlp,       
        address _usdc,
        address _vault    
    ) public{
        swapRouter = ISwapRouter(_swapRouter);
        weth = _weth;
        mvx = _mvx;
        esMvx = _esMvx;
        bnMvx = _bnMvx;
        mvlp = _mvlp;        
        usdc = _usdc;
        vault = _vault;
    }

    function initialize(
        address _stakedMvxTracker,
        address _bonusMvxTracker,
        address _feeMvxTracker,
        address _feeMvlpTracker,
        address _stakedMvlpTracker,
        address _mvlpManager,
        address _mvxVester,
        address _mvlpVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        stakedMvxTracker = _stakedMvxTracker;
        bonusMvxTracker = _bonusMvxTracker;
        feeMvxTracker = _feeMvxTracker;

        feeMvlpTracker = _feeMvlpTracker;
        stakedMvlpTracker = _stakedMvlpTracker;

        mvlpManager = _mvlpManager;

        mvxVester = _mvxVester;
        mvlpVester = _mvlpVester;

    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeMvxForAccount(address[] memory _accounts, uint256[] memory _amounts) external nonReentrant onlyGov {
        address _mvx = mvx;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeMvx(msg.sender, _accounts[i], _mvx, _amounts[i]);
        }
    }

    function stakeMvxForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeMvx(msg.sender, _account, mvx, _amount);
    }

    function stakeMvx(uint256 _amount) external nonReentrant {
        _stakeMvx(msg.sender, msg.sender, mvx, _amount);
    }

    function stakeEsMvx(uint256 _amount) external nonReentrant {
        _stakeMvx(msg.sender, msg.sender, esMvx, _amount);
    }

    function unstakeMvx(uint256 _amount) external nonReentrant {
        _unstakeMvx(msg.sender, mvx, _amount, true);
    }

    function unstakeEsMvx(uint256 _amount) external nonReentrant {
        _unstakeMvx(msg.sender, esMvx, _amount, true);
    }

    function mintAndStakeMvlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdm,
        uint256 _minMvlp
    ) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 mvlpAmount = IMvlpManager(mvlpManager).addLiquidityForAccount(account, account, _token, _amount, _minUsdm, _minMvlp);
        IRewardTracker(feeMvlpTracker).stakeForAccount(account, account, mvlp, mvlpAmount);
        IRewardTracker(stakedMvlpTracker).stakeForAccount(account, account, feeMvlpTracker, mvlpAmount);

        emit StakeMvlp(account, mvlpAmount);

        return mvlpAmount;
    }

    function mintAndStakeMvlpETH(uint256 _minUsdm, uint256 _minMvlp) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        return _mintAndStakeMvlpETH(msg.value,_minUsdm, _minMvlp);
    }

    function _mintAndStakeMvlpETH(uint256 _amount,uint256 _minUsdm, uint256 _minMvlp) private returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IERC20(weth).approve(mvlpManager, _amount);

        address account = msg.sender;
        uint256 mvlpAmount = IMvlpManager(mvlpManager).addLiquidityForAccount(address(this), account, weth, _amount, _minUsdm, _minMvlp);

        IRewardTracker(feeMvlpTracker).stakeForAccount(account, account, mvlp, mvlpAmount);
        IRewardTracker(stakedMvlpTracker).stakeForAccount(account, account, feeMvlpTracker, mvlpAmount);

        emit StakeMvlp(account, mvlpAmount);

        return mvlpAmount;
    }

    function unstakeAndRedeemMvlp(
        address _tokenOut,
        uint256 _mvlpAmount,
        uint256 _minOut,
        address _receiver
    ) external nonReentrant returns (uint256) {
        require(_mvlpAmount > 0, "RewardRouter: invalid _mvlpAmount");

        address account = msg.sender;
        IRewardTracker(stakedMvlpTracker).unstakeForAccount(account, feeMvlpTracker, _mvlpAmount, account);
        IRewardTracker(feeMvlpTracker).unstakeForAccount(account, mvlp, _mvlpAmount, account);
        uint256 amountOut = IMvlpManager(mvlpManager).removeLiquidityForAccount(account, _tokenOut, _mvlpAmount, _minOut, _receiver);

        emit UnstakeMvlp(account, _mvlpAmount);

        return amountOut;
    }

    function unstakeAndRedeemMvlpETH(
        uint256 _mvlpAmount,
        uint256 _minOut,
        address payable _receiver
    ) external nonReentrant returns (uint256) {
        require(_mvlpAmount > 0, "RewardRouter: invalid _mvlpAmount");

        address account = msg.sender;
        IRewardTracker(stakedMvlpTracker).unstakeForAccount(account, feeMvlpTracker, _mvlpAmount, account);
        IRewardTracker(feeMvlpTracker).unstakeForAccount(account, mvlp, _mvlpAmount, account);
        uint256 amountOut = IMvlpManager(mvlpManager).removeLiquidityForAccount(account, weth, _mvlpAmount, _minOut, address(this));

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeMvlp(account, _mvlpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeMvxTracker).claimForAccount(account, account);
        IRewardTracker(feeMvlpTracker).claimForAccount(account, account);

        IRewardTracker(stakedMvxTracker).claimForAccount(account, account);
        IRewardTracker(stakedMvlpTracker).claimForAccount(account, account);
    }

    function claimEsMvx() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedMvxTracker).claimForAccount(account, account);
        IRewardTracker(stakedMvlpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeMvxTracker).claimForAccount(account, account);
        IRewardTracker(feeMvlpTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

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
    ) external nonReentrant returns (uint256 amountOut) {
        address account = msg.sender;

        uint256 mvxAmount = 0;
        if (_shouldClaimMvx) {
            uint256 mvxAmount0 = IVester(mvxVester).claimForAccount(account, account);
            uint256 mvxAmount1 = IVester(mvlpVester).claimForAccount(account, account);
            mvxAmount = mvxAmount0.add(mvxAmount1);
        }

        if (_shouldStakeMvx && mvxAmount > 0) {
            _stakeMvx(account, account, mvx, mvxAmount);
        }

        uint256 esMvxAmount = 0;
        if (_shouldClaimEsMvx) {
            uint256 esMvxAmount0 = IRewardTracker(stakedMvxTracker).claimForAccount(account, account);
            uint256 esMvxAmount1 = IRewardTracker(stakedMvlpTracker).claimForAccount(account, account);
            esMvxAmount = esMvxAmount0.add(esMvxAmount1);
        }

        if (_shouldStakeEsMvx && esMvxAmount > 0) {
            _stakeMvx(account, account, esMvx, esMvxAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnMvxAmount = IRewardTracker(bonusMvxTracker).claimForAccount(account, account);
            if (bnMvxAmount > 0) {
                IRewardTracker(feeMvxTracker).stakeForAccount(account, account, bnMvx, bnMvxAmount);
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth || _shouldAddIntoMVLP || _shouldConvertMvxAndStake) {
                uint256 weth0 = IRewardTracker(feeMvxTracker).claimForAccount(account, address(this));
                uint256 weth1 = IRewardTracker(feeMvlpTracker).claimForAccount(account, address(this));

                uint256 wethAmount = weth0.add(weth1);
                

                if(_shouldAddIntoMVLP){
                    amountOut = _mintAndStakeMvlpETH(wethAmount,0,0);
                }else if(_shouldConvertMvxAndStake){
                    //convert weth->usdc->mvx and stake

                    IERC20(weth).safeTransfer(vault, wethAmount);

                    //convert weth->usdc via vault
                    uint256 usdcAmountOut = IVault(vault).swap(weth, usdc, address(this));

                    //convert usdc->mvx via uniswap
                     uint256 mvxAmountOut = _swapExactInputSingle(usdcAmountOut);

                    if (mvxAmountOut > 0) {
                        TransferHelper.safeApprove(mvx, stakedMvxTracker, mvxAmountOut);
                        _stakeMvx(address(this), account, mvx, mvxAmountOut);
                        amountOut = mvxAmountOut;
                    }

                }else{
                    IWETH(weth).withdraw(wethAmount);
                    payable(account).sendValue(wethAmount);
                }
            } else {
                IRewardTracker(feeMvxTracker).claimForAccount(account, account);
                IRewardTracker(feeMvlpTracker).claimForAccount(account, account);
            }
        }
    }

    function _swapExactInputSingle(uint256 amountIn) private returns (uint256 amountOut) {
        TransferHelper.safeApprove(usdc, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: usdc,
                tokenOut: mvx,
                fee: MVX_USDC_POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function signalTransfer(address _receiver) external nonReentrant {
        require(IERC20(mvxVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(mvlpVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(IERC20(mvxVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(mvlpVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedMvx = IRewardTracker(stakedMvxTracker).depositBalances(_sender, mvx);
        if (stakedMvx > 0) {
            _unstakeMvx(_sender, mvx, stakedMvx, false);
            _stakeMvx(_sender, receiver, mvx, stakedMvx);
        }

        uint256 stakedEsMvx = IRewardTracker(stakedMvxTracker).depositBalances(_sender, esMvx);
        if (stakedEsMvx > 0) {
            _unstakeMvx(_sender, esMvx, stakedEsMvx, false);
            _stakeMvx(_sender, receiver, esMvx, stakedEsMvx);
        }

        uint256 stakedBnMvx = IRewardTracker(feeMvxTracker).depositBalances(_sender, bnMvx);
        if (stakedBnMvx > 0) {
            IRewardTracker(feeMvxTracker).unstakeForAccount(_sender, bnMvx, stakedBnMvx, _sender);
            IRewardTracker(feeMvxTracker).stakeForAccount(_sender, receiver, bnMvx, stakedBnMvx);
        }

        uint256 esMvxBalance = IERC20(esMvx).balanceOf(_sender);
        if (esMvxBalance > 0) {
            IERC20(esMvx).transferFrom(_sender, receiver, esMvxBalance);
        }

        uint256 mvlpAmount = IRewardTracker(feeMvlpTracker).depositBalances(_sender, mvlp);
        if (mvlpAmount > 0) {
            IRewardTracker(stakedMvlpTracker).unstakeForAccount(_sender, feeMvlpTracker, mvlpAmount, _sender);
            IRewardTracker(feeMvlpTracker).unstakeForAccount(_sender, mvlp, mvlpAmount, _sender);

            IRewardTracker(feeMvlpTracker).stakeForAccount(_sender, receiver, mvlp, mvlpAmount);
            IRewardTracker(stakedMvlpTracker).stakeForAccount(receiver, receiver, feeMvlpTracker, mvlpAmount);
        }

        IVester(mvxVester).transferStakeValues(_sender, receiver);
        IVester(mvlpVester).transferStakeValues(_sender, receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(IRewardTracker(stakedMvxTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedMvxTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedMvxTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedMvxTracker.cumulativeRewards > 0");

        require(IRewardTracker(bonusMvxTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: bonusMvxTracker.averageStakedAmounts > 0");
        require(IRewardTracker(bonusMvxTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: bonusMvxTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeMvxTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeMvxTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeMvxTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeMvxTracker.cumulativeRewards > 0");

        require(IVester(mvxVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: mvxVester.transferredAverageStakedAmounts > 0");
        require(IVester(mvxVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: mvxVester.transferredCumulativeRewards > 0");

        require(IRewardTracker(stakedMvlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedMvlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedMvlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedMvlpTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeMvlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeMvlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeMvlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeMvlpTracker.cumulativeRewards > 0");

        require(IVester(mvlpVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: mvxVester.transferredAverageStakedAmounts > 0");
        require(IVester(mvlpVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: mvxVester.transferredCumulativeRewards > 0");

        require(IERC20(mvxVester).balanceOf(_receiver) == 0, "RewardRouter: mvxVester.balance > 0");
        require(IERC20(mvlpVester).balanceOf(_receiver) == 0, "RewardRouter: mvlpVester.balance > 0");
    }

    function _compound(address _account) private {
        _compoundMvx(_account);
        _compoundMvlp(_account);
    }

    function _compoundMvx(address _account) private {
        uint256 esMvxAmount = IRewardTracker(stakedMvxTracker).claimForAccount(_account, _account);
        if (esMvxAmount > 0) {
            _stakeMvx(_account, _account, esMvx, esMvxAmount);
        }

        uint256 bnMvxAmount = IRewardTracker(bonusMvxTracker).claimForAccount(_account, _account);
        if (bnMvxAmount > 0) {
            IRewardTracker(feeMvxTracker).stakeForAccount(_account, _account, bnMvx, bnMvxAmount);
        }
    }

    function _compoundMvlp(address _account) private {
        uint256 esMvxAmount = IRewardTracker(stakedMvlpTracker).claimForAccount(_account, _account);
        if (esMvxAmount > 0) {
            _stakeMvx(_account, _account, esMvx, esMvxAmount);
        }
    }

    function _stakeMvx(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedMvxTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusMvxTracker).stakeForAccount(_account, _account, stakedMvxTracker, _amount);
        IRewardTracker(feeMvxTracker).stakeForAccount(_account, _account, bonusMvxTracker, _amount);

        emit StakeMvx(_account, _token, _amount);
    }

    function _unstakeMvx(
        address _account,
        address _token,
        uint256 _amount,
        bool _shouldReduceBnMvx
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedMvxTracker).stakedAmounts(_account);

        IRewardTracker(feeMvxTracker).unstakeForAccount(_account, bonusMvxTracker, _amount, _account);
        IRewardTracker(bonusMvxTracker).unstakeForAccount(_account, stakedMvxTracker, _amount, _account);
        IRewardTracker(stakedMvxTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceBnMvx) {
            uint256 bnMvxAmount = IRewardTracker(bonusMvxTracker).claimForAccount(_account, _account);
            if (bnMvxAmount > 0) {
                IRewardTracker(feeMvxTracker).stakeForAccount(_account, _account, bnMvx, bnMvxAmount);
            }

            uint256 stakedBnMvx = IRewardTracker(feeMvxTracker).depositBalances(_account, bnMvx);
            if (stakedBnMvx > 0) {
                uint256 reductionAmount = stakedBnMvx.mul(_amount).div(balance);
                IRewardTracker(feeMvxTracker).unstakeForAccount(_account, bnMvx, reductionAmount, _account);
                IMintable(bnMvx).burn(_account, reductionAmount);
            }
        }

        emit UnstakeMvx(_account, _token, _amount);
    }
}
