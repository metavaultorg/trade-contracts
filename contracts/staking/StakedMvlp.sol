// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";

import "../core/interfaces/IMvlpManager.sol";

import "./interfaces/IRewardTracker.sol";

contract StakedMvlp {
    using SafeMath for uint256;

    string public constant name = "StakedMvlp";
    string public constant symbol = "sMVLP";
    uint8 public constant decimals = 18;

    address public mvlp;
    IMvlpManager public mvlpManager;
    address public stakedMvlpTracker;
    address public feeMvlpTracker;

    mapping(address => mapping(address => uint256)) public allowances;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        address _mvlp,
        IMvlpManager _mvlpManager,
        address _stakedMvlpTracker,
        address _feeMvlpTracker
    ) public {
        mvlp = _mvlp;
        mvlpManager = _mvlpManager;
        stakedMvlpTracker = _stakedMvlpTracker;
        feeMvlpTracker = _feeMvlpTracker;
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(_amount, "StakedMvlp: transfer amount exceeds allowance");
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function balanceOf(address _account) external view returns (uint256) {
        IRewardTracker(stakedMvlpTracker).depositBalances(_account, mvlp);
    }

    function totalSupply() external view returns (uint256) {
        IERC20(stakedMvlpTracker).totalSupply();
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) private {
        require(_owner != address(0), "StakedMvlp: approve from the zero address");
        require(_spender != address(0), "StakedMvlp: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) private {
        require(_sender != address(0), "StakedMvlp: transfer from the zero address");
        require(_recipient != address(0), "StakedMvlp: transfer to the zero address");

        require(mvlpManager.lastAddedAt(_sender).add(mvlpManager.cooldownDuration()) <= block.timestamp, "StakedMvlp: cooldown duration not yet passed");

        IRewardTracker(stakedMvlpTracker).unstakeForAccount(_sender, feeMvlpTracker, _amount, _sender);
        IRewardTracker(feeMvlpTracker).unstakeForAccount(_sender, mvlp, _amount, _sender);

        IRewardTracker(feeMvlpTracker).stakeForAccount(_sender, _recipient, mvlp, _amount);
        IRewardTracker(stakedMvlpTracker).stakeForAccount(_recipient, _recipient, feeMvlpTracker, _amount);
    }
}
