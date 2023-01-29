// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "contracts/interfaces/IStrategy.sol";
import "contracts/Registry.sol";
import "contracts/libraries/OndoLibrary.sol";
import "contracts/OndoRegistryClient.sol";
import "contracts/interfaces/IPairVault.sol";

//All LP strategies should inherit this strategy

abstract contract BasePairLPStrategy is OndoRegistryClient, IStrategy {
  using SafeERC20 for IERC20;

  modifier onlyOrigin(uint256 _vaultId) {
    require(
      msg.sender == address(vaults[_vaultId].origin),
      "Unauthorized: Only Vault contract"
    );
    _;
  }

  event Invest(uint256 indexed vault, uint256 lpTokens);
  event Redeem(uint256 indexed vault);
  event Harvest(address indexed pool, uint256 lpTokens);

  mapping(uint256 => Vault) public override vaults;

  constructor(address _registry) OndoRegistryClient(_registry) {}


  function addLp(uint256 _vaultId, uint256 _amount)
    external
    virtual
    override
    whenNotPaused
    onlyOrigin(_vaultId)
  {
    Vault storage vault_ = vaults[_vaultId];
    vault_.shares += _amount;
  }

  function removeLp(
    uint256 _vaultId,
    uint256 _amount,
    address to
  ) external virtual override whenNotPaused onlyOrigin(_vaultId) {
    Vault storage vault_ = vaults[_vaultId];
    vault_.shares -= _amount;
    IERC20(vault_.pool).safeTransfer(to, _amount);
  }


  function getVaultInfo(uint256 _vaultId)
    external
    view
    override
    returns (IERC20, uint256)
  {
    Vault storage c = vaults[_vaultId];
    return (c.pool, c.shares);
  }


  function withdrawExcess(
    uint256 _vaultId,
    OLib.Tranche tranche,
    address to,
    uint256 amount
  ) external override onlyOrigin(_vaultId) {
    Vault storage _vault = vaults[_vaultId];
    if (tranche == OLib.Tranche.Senior) {
      uint256 excess = _vault.seniorExcess;
      require(amount <= excess, "excessive amount...");
      _vault.seniorExcess -= amount;
      _vault.senior.safeTransfer(to, amount);
    } else {
      uint256 excess = _vault.juniorExcess;
      require(amount <= excess, "excessive amount...");
      _vault.juniorExcess -= amount;
      _vault.junior.safeTransfer(to, amount);
    }
  }
}