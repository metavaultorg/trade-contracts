// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IMvlpManager.sol";
import "../tokens/interfaces/IUSDM.sol";
import "../tokens/interfaces/IMintable.sol";
import "../access/Governable.sol";

contract MvlpManager is ReentrancyGuard, Governable, IMvlpManager {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant PRICE_PRECISION = 10**30;
    uint256 public constant USDM_DECIMALS = 18;
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours;

    IVault public vault;
    address public override usdm;
    address public mvlp;

    uint256 public override cooldownDuration;
    mapping(address => uint256) public override lastAddedAt;

    uint256 public aumAddition;
    uint256 public aumDeduction;

    bool public inPrivateMode;
    mapping(address => bool) public isHandler;

    event AddLiquidity(address account, address token, uint256 amount, uint256 aumInUsdm, uint256 mvlpSupply, uint256 usdmAmount, uint256 mintAmount);

    event RemoveLiquidity(address account, address token, uint256 mvlpAmount, uint256 aumInUsdm, uint256 mvlpSupply, uint256 usdmAmount, uint256 amountOut);

    constructor(
        address _vault,
        address _usdm,
        address _mvlp,
        uint256 _cooldownDuration
    ) public {
        gov = msg.sender;
        vault = IVault(_vault);
        usdm = _usdm;
        mvlp = _mvlp;
        cooldownDuration = _cooldownDuration;
    }

    function setInPrivateMode(bool _inPrivateMode) external onlyGov {
        inPrivateMode = _inPrivateMode;
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    function setCooldownDuration(uint256 _cooldownDuration) external override onlyGov {
        require(_cooldownDuration <= MAX_COOLDOWN_DURATION, "MvlpManager: invalid _cooldownDuration");
        cooldownDuration = _cooldownDuration;
    }

    function setAumAdjustment(uint256 _aumAddition, uint256 _aumDeduction) external onlyGov {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }

    function addLiquidity(
        address _token,
        uint256 _amount,
        uint256 _minUsdm,
        uint256 _minMvlp
    ) external override nonReentrant returns (uint256) {
        if (inPrivateMode) {
            revert("MvlpManager: action not enabled");
        }
        return _addLiquidity(msg.sender, msg.sender, _token, _amount, _minUsdm, _minMvlp);
    }

    function addLiquidityForAccount(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsdm,
        uint256 _minMvlp
    ) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _addLiquidity(_fundingAccount, _account, _token, _amount, _minUsdm, _minMvlp);
    }

    function removeLiquidity(
        address _tokenOut,
        uint256 _mvlpAmount,
        uint256 _minOut,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        if (inPrivateMode) {
            revert("MvlpManager: action not enabled");
        }
        return _removeLiquidity(msg.sender, _tokenOut, _mvlpAmount, _minOut, _receiver);
    }

    function removeLiquidityForAccount(
        address _account,
        address _tokenOut,
        uint256 _mvlpAmount,
        uint256 _minOut,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _removeLiquidity(_account, _tokenOut, _mvlpAmount, _minOut, _receiver);
    }

    function getAums() public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = getAum(true);
        amounts[1] = getAum(false);
        return amounts;
    }

    function getAumInUsdm(bool maximise) public view returns (uint256) {
        uint256 aum = getAum(maximise);
        return aum.mul(10**USDM_DECIMALS).div(PRICE_PRECISION);
    }

    function getAum(bool maximise) public view returns (uint256) {
        uint256 length = vault.allWhitelistedTokensLength();
        uint256 aum = aumAddition;
        uint256 shortProfits = 0;

        for (uint256 i = 0; i < length; i++) {
            address token = vault.allWhitelistedTokens(i);
            bool isWhitelisted = vault.whitelistedTokens(token);

            if (!isWhitelisted) {
                continue;
            }

            uint256 price = maximise ? vault.getMaxPrice(token) : vault.getMinPrice(token);
            uint256 poolAmount = vault.poolAmounts(token);
            uint256 decimals = vault.tokenDecimals(token);

            if (vault.stableTokens(token)) {
                aum = aum.add(poolAmount.mul(price).div(10**decimals));
            } else {
                // add global short profit / loss
                uint256 size = vault.globalShortSizes(token);
                if (size > 0) {
                    uint256 averagePrice = vault.globalShortAveragePrices(token);
                    uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                    uint256 delta = size.mul(priceDelta).div(averagePrice);
                    if (price > averagePrice) {
                        // add losses from shorts
                        aum = aum.add(delta);
                    } else {
                        shortProfits = shortProfits.add(delta);
                    }
                }

                aum = aum.add(vault.guaranteedUsd(token));

                uint256 reservedAmount = vault.reservedAmounts(token);
                aum = aum.add(poolAmount.sub(reservedAmount).mul(price).div(10**decimals));
            }
        }

        aum = shortProfits > aum ? 0 : aum.sub(shortProfits);
        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);
    }

    function _addLiquidity(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsdm,
        uint256 _minMvlp
    ) private returns (uint256) {
        require(_amount > 0, "MvlpManager: invalid _amount");

        // calculate aum before buyUSDM
        uint256 aumInUsdm = getAumInUsdm(true);
        uint256 mvlpSupply = IERC20(mvlp).totalSupply();

        IERC20(_token).safeTransferFrom(_fundingAccount, address(vault), _amount);
        uint256 usdmAmount = vault.buyUSDM(_token, address(this));
        require(usdmAmount >= _minUsdm, "MvlpManager: insufficient USDM output");

        uint256 mintAmount = aumInUsdm == 0 ? usdmAmount : usdmAmount.mul(mvlpSupply).div(aumInUsdm);
        require(mintAmount >= _minMvlp, "MvlpManager: insufficient MVLP output");

        IMintable(mvlp).mint(_account, mintAmount);

        lastAddedAt[_account] = block.timestamp;

        emit AddLiquidity(_account, _token, _amount, aumInUsdm, mvlpSupply, usdmAmount, mintAmount);

        return mintAmount;
    }

    function _removeLiquidity(
        address _account,
        address _tokenOut,
        uint256 _mvlpAmount,
        uint256 _minOut,
        address _receiver
    ) private returns (uint256) {
        require(_mvlpAmount > 0, "MvlpManager: invalid _mvlpAmount");
        require(lastAddedAt[_account].add(cooldownDuration) <= block.timestamp, "MvlpManager: cooldown duration not yet passed");

        // calculate aum before sellUSDM
        uint256 aumInUsdm = getAumInUsdm(false);
        uint256 mvlpSupply = IERC20(mvlp).totalSupply();

        uint256 usdmAmount = _mvlpAmount.mul(aumInUsdm).div(mvlpSupply);
        uint256 usdmBalance = IERC20(usdm).balanceOf(address(this));
        if (usdmAmount > usdmBalance) {
            IUSDM(usdm).mint(address(this), usdmAmount.sub(usdmBalance));
        }

        IMintable(mvlp).burn(_account, _mvlpAmount);

        IERC20(usdm).transfer(address(vault), usdmAmount);
        uint256 amountOut = vault.sellUSDM(_tokenOut, _receiver);
        require(amountOut >= _minOut, "MvlpManager: insufficient output");

        emit RemoveLiquidity(_account, _tokenOut, _mvlpAmount, aumInUsdm, mvlpSupply, usdmAmount, amountOut);

        return amountOut;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "MvlpManager: forbidden");
    }
}
