// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { OFTCore } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import { IOFT, SendParam, OFTReceipt, MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

abstract contract NativeOFTAdapterMsgValueTransfer is OFTCore, ReentrancyGuard, ERC20 { // TODO has this been audited? should we use our audited NativeOFTAdapter example? but we would need to add the deposit / receive functions to it
    event Deposit(address indexed _dst, uint _amount);
    event Withdrawal(address indexed _src, uint _amount);

    error InsufficientBalance();
    error InsufficientMessageValue();
    error WithdrawalFailed();

    /**
     * @dev Constructor for the OFTAdapter contract.
     * @param _lzEndpoint The LayerZero endpoint address.
     * @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) OFTCore(18, _lzEndpoint, _delegate) ERC20(_name, _symbol) {}

    function token() external pure returns (address) {
        return address(0);
    }

    /**
     * @notice Indicates whether the OFT contract requires approval of the 'token()' to send.
     * @return requiresApproval Needs approval of the underlying token implementation.
     *
     * @dev In the case of default OFTAdapter, approval is required.
     * @dev In non-default OFTAdapter contracts with something like mint and burn privileges, it would NOT need approval.
     */
    function approvalRequired() external pure virtual returns (bool) {
        return false;
    }

    /**
     * @dev Burns tokens from the sender's specified balance, ie. pull method.
     * @param _amountLD The amount of tokens to send in local decimals.
     * @param _minAmountLD The minimum amount to send in local decimals.
     * @param _dstEid The destination chain ID.
     * @return amountSentLD The amount sent in local decimals.
     * @return amountReceivedLD The amount received in local decimals on the remote.
     *
     * @dev msg.sender will need to approve this _amountLD of tokens to be locked inside of the contract.
     * @dev WARNING: The default OFTAdapter implementation assumes LOSSLESS transfers, ie. 1 token in, 1 token out.
     * IF the 'innerToken' applies something like a transfer fee, the default will NOT work...
     * a pre/post balance check will need to be done to calculate the amountReceivedLD.
     */
    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        
        _burn(msg.sender, amountSentLD);
    }

    /**
     * @dev Credits tokens to the specified address.
     * @param _to The address to credit the tokens to.
     * @param _amountLD The amount of tokens to credit in local decimals.
     * @dev _srcEid The source chain ID.
     * @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
     *
     * @dev WARNING: The default OFTAdapter implementation assumes LOSSLESS transfers, ie. 1 token in, 1 token out.
     * IF the 'innerToken' applies something like a transfer fee, the default will NOT work...
     * a pre/post balance check will need to be done to calculate the amountReceivedLD.
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    ) internal virtual override returns (uint256 amountReceivedLD) {
        // @dev Unlock the tokens and transfer to the recipient.
        (bool success, ) = _to.call{value: _amountLD}("");
        if (!success) {
            revert WithdrawalFailed();
        }

        // @dev In the case of NON-default OFTAdapter, the amountLD MIGHT not be == amountReceivedLD.
        return _amountLD;
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint _amount) external nonReentrant {
        if (balanceOf(msg.sender) < _amount) {
            revert InsufficientBalance();
        }
        _burn(msg.sender, _amount);
        (bool success, ) = msg.sender.call{value: _amount}("");
        if (!success) {
            revert WithdrawalFailed();
        }
        emit Withdrawal(msg.sender, _amount);
    }

    receive() external payable {
        deposit();
    }

    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable override returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        uint msgSenderBalance = balanceOf(msg.sender);
        MessagingFee memory feeWithExtraAmount = MessagingFee({
            nativeFee: _fee.nativeFee,
            lzTokenFee: _fee.lzTokenFee
        });

        if (msgSenderBalance < _sendParam.amountLD) {
            if (msgSenderBalance + msg.value < _sendParam.amountLD) {
                revert InsufficientMessageValue();
            }

            // user can cover difference with additional msg.value ie. wrapping
            uint mintAmount = _sendParam.amountLD - msgSenderBalance;
            _mint(address(msg.sender), mintAmount);

            // update the messageFee to take out mintAmount
            feeWithExtraAmount.nativeFee = msg.value - mintAmount;
        } else if (msg.value != feeWithExtraAmount.nativeFee) {
            revert NotEnoughNative(msg.value);
        }

        // @dev Applies the token transfers regarding this send() operation.
        // - amountSentLD is the amount in local decimals that was ACTUALLY sent/debited from the sender.
        // - amountReceivedLD is the amount in local decimals that will be received/credited to the recipient on the remote OFT instance.
        (uint256 amountSentLD, uint256 amountReceivedLD) = _debit(
            _sendParam.amountLD,
            _sendParam.minAmountLD,
            _sendParam.dstEid
        );

        // @dev Builds the options and OFT message to quote in the endpoint.
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, amountReceivedLD);

        // @dev Sends the message to the LayerZero endpoint and returns the LayerZero msg receipt.
        msgReceipt = _lzSend(_sendParam.dstEid, message, options, feeWithExtraAmount, _refundAddress);
        // @dev Formulate the OFT receipt.
        oftReceipt = OFTReceipt(amountSentLD, amountReceivedLD);

        emit OFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, amountSentLD, amountReceivedLD);
    }

    function _payNative(uint256 _nativeFee) internal override returns (uint256 nativeFee) {
        if (msg.value < _nativeFee) revert NotEnoughNative(msg.value);
        return _nativeFee;
    }

    function oftVersion() external pure virtual returns (bytes4 interfaceId, uint64 version) {
        return (type(IOFT).interfaceId, 1);
    }
}