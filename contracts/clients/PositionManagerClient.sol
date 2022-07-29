/// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

pragma experimental ABIEncoderV2;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/Address.sol";

import "../libraries/access/Ownable.sol";

import "./interfaces/IPositionManagerClient.sol";
import "./interfaces/IRouterClient.sol";


contract PositionManagerClient is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public positionManager;
    address public router;


    function initialize(address _positionManager,address _router) external onlyOwner {
        require(_positionManager != address(0), "Address not valid.");
        require(_router != address(0), "Address not valid.");
        positionManager = _positionManager;
        router = _router;
        IRouterClient(router).approvePlugin(positionManager);
    }
    receive() external payable {}

    function setPositionManager(address _positionManager) public onlyOwner {
        require(_positionManager != address(0), "Address not valid.");
        positionManager = _positionManager;
    }

    function setRouter(address _router) public onlyOwner {
        require(_router != address(0), "Address not valid.");
        router = _router;
    }

    function setRouterApprovePlugin() public onlyOwner {
        IRouterClient(router).approvePlugin(positionManager);
    }

    function approve(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).approve(router, _amount);
    }


    function increasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price,
        bytes32 _referralCode
    ) external  {
        IPositionManagerClient(positionManager).increasePosition(
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _price,
            _referralCode
        );
    }

    function increasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price,
        bytes32 _referralCode
    ) external payable  {
        IPositionManagerClient(positionManager).increasePositionETH{value:msg.value}(
            _path,
            _indexToken,
            _minOut,
            _sizeDelta,
            _isLong,
            _price,
            _referralCode
        );
    }

    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price
    ) external  {
        IPositionManagerClient(positionManager).decreasePosition(
         _collateralToken,
         _indexToken,
         _collateralDelta,
         _sizeDelta,
         _isLong,
         _receiver,
         _price
        );
    }

    function decreasePositionETH(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address payable _receiver,
        uint256 _price
    ) external  {
        IPositionManagerClient(positionManager).decreasePositionETH(
         _collateralToken,
         _indexToken,
         _collateralDelta,
         _sizeDelta,
         _isLong,
         _receiver,
         _price
        );
    }

    function decreasePositionAndSwap(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price,
        uint256 _minOut
    ) external {
        IPositionManagerClient(positionManager).decreasePositionAndSwap(
        _path,
        _indexToken,
        _collateralDelta,
        _sizeDelta,
        _isLong,
        _receiver,
        _price,
        _minOut
        );
    }

    function decreasePositionAndSwapETH(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address payable _receiver,
        uint256 _price,
        uint256 _minOut
    ) external  {
        IPositionManagerClient(positionManager).decreasePositionAndSwapETH(
        _path,
        _indexToken,
        _collateralDelta,
        _sizeDelta,
        _isLong,
        _receiver,
        _price,
        _minOut
        );
    }
    
}
