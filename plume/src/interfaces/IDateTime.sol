// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

interface IDateTime {

    function isLeapYear(
        uint16 year
    ) external view returns (bool);
    function getYear(
        uint256 timestamp
    ) external view returns (uint16);
    function getMonth(
        uint256 timestamp
    ) external view returns (uint8);
    function getDay(
        uint256 timestamp
    ) external view returns (uint8);
    function getHour(
        uint256 timestamp
    ) external view returns (uint8);
    function getMinute(
        uint256 timestamp
    ) external view returns (uint8);
    function getSecond(
        uint256 timestamp
    ) external view returns (uint8);
    function getWeekday(
        uint256 timestamp
    ) external view returns (uint8);
    function toTimestamp(uint16 year, uint8 month, uint8 day) external view returns (uint256 timestamp);
    function toTimestamp(uint16 year, uint8 month, uint8 day, uint8 hour) external view returns (uint256 timestamp);
    function toTimestamp(
        uint16 year,
        uint8 month,
        uint8 day,
        uint8 hour,
        uint8 minute
    ) external view returns (uint256 timestamp);
    function toTimestamp(
        uint16 year,
        uint8 month,
        uint8 day,
        uint8 hour,
        uint8 minute,
        uint8 second
    ) external view returns (uint256 timestamp);

    function getWeekNumber(
        uint256 timestamp
    ) external view returns (uint8);

}
