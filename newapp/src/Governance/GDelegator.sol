pragma solidity 0.8.13;

import "./GInterfaces.sol";

contract GDelegator is
  GDelegator,
  GEvents
{
  constructor(
    address timelock_,
    address ondo_,
    address admin_,
    address implementation_,
    uint256 votingPeriod_,
    uint256 votingDelay_,
    uint256 proposalThreshold_
  ) public {
    // Admin set to msg.sender for initialization
    admin = msg.sender;

    delegateTo(
      implementation_,
      abi.encodeWithSignature(
        "initialize(address,address,uint256,uint256,uint256)",
        timelock_,
        ondo_,
        votingPeriod_,
        votingDelay_,
        proposalThreshold_
      )
    );

    _setImplementation(implementation_);

    admin = admin_;
  }


  function _setImplementation(address implementation_) public {
    require(
      msg.sender == admin,
      "admin only"
    );
    require(
      implementation_ != address(0),
      "invalid implementation address"
    );

    address oldImplementation = implementation;
    implementation = implementation_;

    emit NewImplementation(oldImplementation, implementation);
  }


  function delegateTo(address callee, bytes memory data) internal {
    (bool success, bytes memory returnData) = callee.delegatecall(data);
    assembly {
      if eq(success, 0) {
        revert(add(returnData, 0x20), returndatasize)
      }
    }
  }


  function() external payable {
    // delegate all other functions to current implementation
    (bool success, ) = implementation.delegatecall(msg.data);

    assembly {
      let free_mem_ptr := mload(0x40)
      returndatacopy(free_mem_ptr, 0, returndatasize)

      switch success
        case 0 {
          revert(free_mem_ptr, returndatasize)
        }
        default {
          return(free_mem_ptr, returndatasize)
        }
    }
  }
}