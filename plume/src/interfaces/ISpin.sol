pragma solidity ^0.8.14;

interface ISpin {

    function updateRaffleTickets(address _user, uint256 _amount) external;
    function getUserData(
        address _user
    ) external view returns (uint256, uint256, uint256, uint256, uint256);

}
