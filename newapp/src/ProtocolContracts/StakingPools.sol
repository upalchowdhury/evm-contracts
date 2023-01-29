// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./appToken.sol";

/*
 * @title Staking contract based heavily on MasterChef & V2
 *
 */
contract StakingPools is AccessControl {

  // Info of each user.
  struct UserInfo {
    uint256 amount; 
    uint256 rewardDebt;

  }
  // Info of each pool.
  struct PoolInfo {
    IERC20 lpToken; // Address of LP token contract.
    uint256 allocPoint; // How many allocation points assigned to this pool. apps to distribute per block.
    uint256 lastRewardBlock; // Last block number that apps distribution occurs.
    uint256 accappPerShare; // Accumulated apps per share, times 1e18. See below.
  }
  // The app TOKEN!
  app public app;
  // Block number when bonus app period ends.
  uint256 public bonusEndBlock;
  // app tokens created per block.
  uint256 public appPerBlock;
  // Bonus muliplier for early app makers.
  uint256 public constant BONUS_MULTIPLIER = 10;
  // Info of each pool.
  PoolInfo[] public poolInfo;
  // Info of each user that stakes LP tokens.
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;
  // Total allocation poitns. Must be the sum of all allocation points in all pools.
  uint256 public totalAllocPoint = 0;
  // The block number when app mining starts.
  uint256 public startBlock;
  // The role for vault
  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
  // minimum required balance for this contract
  uint256 public minimumRequiredappBalance;

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event EmergencyWithdraw(
    address indexed user,
    uint256 indexed pid,
    uint256 amount
  );

  /// @notice modifier to check for authorization, this is available in OZ:4.1, current version is OZ:4.0
  modifier onlyRole(bytes32 _role) {
    require(hasRole(_role, msg.sender), "Unauthorized: Invalid role");
    _;
  }

  constructor(
    address _governance,
    app _app,
    uint256 _appPerBlock,
    uint256 _startBlock,
    uint256 _bonusEndBlock
  ) {
    require(address(_app) != address(0), "Invalid target");
    app = _app;
    appPerBlock = _appPerBlock;
    bonusEndBlock = _bonusEndBlock;
    startBlock = _startBlock;
    _setupRole(DEFAULT_ADMIN_ROLE, _governance);
    _setupRole(MANAGER_ROLE, _governance);
  }

  function poolLength() external view returns (uint256) {
    return poolInfo.length;
  }
  function add(
    uint256 _allocPoint,
    IERC20 _lpToken,
    bool _withUpdate
  ) public onlyRole(MANAGER_ROLE) {
    if (_withUpdate) {
      massUpdatePools();
    }
    uint256 lastRewardBlock =
      block.number > startBlock ? block.number : startBlock;
    totalAllocPoint = totalAllocPoint.add(_allocPoint);
    poolInfo.push(
      PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accappPerShare: 0
      })
    );
  }

  function set(
    uint256 _pid,
    uint256 _allocPoint,
    bool _withUpdate
  ) public onlyRole(MANAGER_ROLE) {
    if (_withUpdate) {
      massUpdatePools();
    }
    totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
      _allocPoint
    );
    poolInfo[_pid].allocPoint = _allocPoint;
  }

  // Return reward multiplier over the given _from to _to block.
  function getMultiplier(uint256 _from, uint256 _to)
    public
    view
    returns (uint256)
  {
    if (_to <= bonusEndBlock) {
      return _to.sub(_from).mul(BONUS_MULTIPLIER);
    } else if (_from >= bonusEndBlock) {
      return _to.sub(_from);
    } else {
      return
        bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
          _to.sub(bonusEndBlock)
        );
    }
  }

  // View function to see pending apps on frontend.
  function pendingapp(uint256 _pid, address _user)
    external
    view
    returns (uint256)
  {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 accappPerShare = pool.accappPerShare;
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));
    if (block.number > pool.lastRewardBlock && lpSupply != 0) {
      uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
      uint256 appReward =
        multiplier.mul(appPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
      accappPerShare = accappPerShare.add(appReward.mul(1e18).div(lpSupply));
    }
    return user.amount.mul(accappPerShare).div(1e18).sub(user.rewardDebt);
  }

  // Update reward variables for all pools. Be careful of gas spending!
  function massUpdatePools() public {
    uint256 length = poolInfo.length;
    uint256 totalRewardTokens = 0;
    for (uint256 pid = 0; pid < length; ++pid) {
      totalRewardTokens += updatePool(pid);
    }
    require(
      app.balanceOf(address(this)) >= totalRewardTokens,
      "Not enough app for all pools."
    );
  }

  // Update reward variables of the given pool to be up-to-date.
  function updatePool(uint256 _pid) public returns (uint256) {
    PoolInfo storage pool = poolInfo[_pid];
    if (block.number <= pool.lastRewardBlock) {
      return 0;
    }
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));
    if (lpSupply == 0) {
      pool.lastRewardBlock = block.number;
      return 0;
    }
    uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
    uint256 appReward =
      multiplier.mul(appPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

    minimumRequiredappBalance += appReward;

    require(
      app.balanceOf(address(this)) >= minimumRequiredappBalance,
      "Not enough app for Staking contract"
    );

    pool.accappPerShare = pool.accappPerShare.add(
      appReward.mul(1e18).div(lpSupply)
    );
    pool.lastRewardBlock = block.number;
    return appReward;
  }

  // Deposit LP tokens to StakingPool for app allocation.
  function deposit(uint256 _pid, uint256 _amount) public {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    updatePool(_pid);
    if (user.amount > 0) {
      uint256 pending =
        user.amount.mul(pool.accappPerShare).div(1e18).sub(user.rewardDebt);
      safeappTransfer(msg.sender, pending);
    }
    pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
    user.amount = user.amount.add(_amount);
    user.rewardDebt = user.amount.mul(pool.accappPerShare).div(1e18);
    emit Deposit(msg.sender, _pid, _amount);
  }

  // Withdraw LP tokens from StakingPool.
  function withdraw(uint256 _pid, uint256 _amount) public {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.amount >= _amount, "withdraw: not good");
    updatePool(_pid);
    uint256 pending =
      user.amount.mul(pool.accappPerShare).div(1e18).sub(user.rewardDebt);
    safeappTransfer(msg.sender, pending);
    user.amount = user.amount.sub(_amount);
    user.rewardDebt = user.amount.mul(pool.accappPerShare).div(1e18);
    pool.lpToken.safeTransfer(address(msg.sender), _amount);
    emit Withdraw(msg.sender, _pid, _amount);
  }

  // Withdraw without caring about rewards. EMERGENCY ONLY.
  function emergencyWithdraw(uint256 _pid) public {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    pool.lpToken.safeTransfer(address(msg.sender), user.amount);
    emit EmergencyWithdraw(msg.sender, _pid, user.amount);
    user.amount = 0;
    user.rewardDebt = 0;
  }

  // Safe app transfer function, just in case if rounding error causes pool to not have enough apps.
  function safeappTransfer(address _to, uint256 _amount) internal {
    uint256 appBal = app.balanceOf(address(this));
    if (_amount > appBal) {
      app.transfer(_to, appBal);
      minimumRequiredappBalance -= appBal;
    } else {
      app.transfer(_to, _amount);
      minimumRequiredappBalance -= _amount;
    }
  }
}