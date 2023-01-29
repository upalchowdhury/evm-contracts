// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./RegistryClient.sol";
import "./IFeeCollector.sol";
import "./IPairVault.sol";
import {SaferERC20} from "./appLib.sol";

/*
 * @title Sample Fee Collector
 * @notice Send all fee directly to creator
 */
contract FeeCollector is RegistryClient, IFeeCollector {
  using SafeERC20 for IERC20;
  using OndoSaferERC20 for IERC20;

  IPairVault public immutable vaultManager;

  event ProcessFee(address indexed strategist, IERC20 token, uint256 fee);

  constructor(address vault, address registryAddress)
    OndoRegistryClient(registryAddress)
  {
    require(
      registry.authorized(OLib.VAULT_ROLE, vault),
      "Not a registered Vault"
    );
    vaultManager = IPairVault(vault);
  }


  function processFee(
    uint256 vaultId,
    IERC20 token,
    uint256 fee
  ) external override nonReentrant isAuthorized(OLib.VAULT_ROLE) {
    require(vaultId != 0, "Invalid Vault id");
    require(address(token) != address(0), "Invalid address for token");
    if (fee > 0) {
      IPairVault.VaultView memory vaultInfo =
        vaultManager.getVaultById(vaultId);
      address creator = vaultInfo.creator;
      token.safeTransfer(creator, fee);
      require(
        token.balanceOf(address(this)) == 0,
        "SampleFeeCollector should not hold tokens."
      );
      emit ProcessFee(creator, token, fee);
    }
  }
}