// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IArbitrumDepositor {
    struct EnforcedOptionParam {
        uint32 eid;
        uint16 msgType;
        bytes options;
    }

    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    struct MessagingReceipt {
        bytes32 guid;
        uint64 nonce;
        MessagingFee fee;
    }

    struct Origin {
        uint32 srcEid;
        bytes32 sender;
        uint64 nonce;
    }

    error InvalidDelegate();
    error InvalidEndpointCall();
    error InvalidOptions(bytes options);
    error LzTokenUnavailable();
    error NoPeer(uint32 eid);
    error NotDepositor();
    error NotEnoughNative(uint256 msgValue);
    error OnlyEndpoint(address addr);
    error OnlyPeer(uint32 eid, bytes32 sender);
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);
    error SafeERC20FailedOperation(address token);

    event EnforcedOptionSet(EnforcedOptionParam[] _enforcedOptions);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event PeerSet(uint32 eid, bytes32 peer);

    function allowInitializePath(
        Origin memory origin
    ) external view returns (bool);

    function combineOptions(
        uint32 _eid,
        uint16 _msgType,
        bytes memory _extraOptions
    ) external view returns (bytes memory);

    function depositIntoHyperEVM(
        bytes memory _message,
        bytes memory _options
    ) external payable returns (MessagingReceipt memory receipt);

    function depositor() external view returns (address);

    function endpoint() external view returns (address);

    function enforcedOptions(
        uint32 eid,
        uint16 msgType
    ) external view returns (bytes memory enforcedOption);

    function isComposeMsgSender(
        Origin memory,
        bytes memory,
        address _sender
    ) external view returns (bool);

    function lzReceive(
        Origin memory _origin,
        bytes32 _guid,
        bytes memory _message,
        address _executor,
        bytes memory _extraData
    ) external payable;

    function nextNonce(uint32, bytes32) external view returns (uint64 nonce);

    function oAppVersion()
        external
        pure
        returns (uint64 senderVersion, uint64 receiverVersion);

    function owner() external view returns (address);

    function peers(uint32 eid) external view returns (bytes32 peer);

    function quote(
        uint32 _dstEid,
        string memory _message,
        bytes memory _options,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee);

    function renounceOwnership() external;

    function setDelegate(address _delegate) external;

    function setEnforcedOptions(
        EnforcedOptionParam[] memory _enforcedOptions
    ) external;

    function setPeer(uint32 _eid, bytes32 _peer) external;

    function transferOwnership(address newOwner) external;
}
