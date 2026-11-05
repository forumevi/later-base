// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title LATER — time capsules on Base
/// @notice Seal an encrypted message that unlocks on a chosen date.
///         No owner, no admin, no upgrade, no delete: once sealed, a capsule lives forever.
/// @dev The message is encrypted off-chain with drand timelock (tlock) to `drandRound`,
///      so nobody (including the sender and this app) can decrypt it before that round.
///      The full ciphertext is emitted in the `Sealed` event (cheap calldata/log storage);
///      only its hash is kept in storage so anyone can verify the payload later.
contract LaterCapsule {
    struct Capsule {
        address sender;
        uint64 sealedAt;
        uint64 unlockAt;
        address recipient; // address(0) = shared by private link
        uint64 drandRound;
        bool onSky;
        bool opened;
        bytes32 ciphertextHash;
    }

    uint256 public constant MAX_CIPHERTEXT = 8 * 1024; // 8 KB; photos/voice go off-chain via URI inside the ciphertext
    uint64 public constant MIN_LOCK = 10 minutes;
    uint64 public constant MAX_LOCK = 100 * 365 days;

    Capsule[] private _capsules;
    mapping(address => uint256[]) private _sentBy;
    mapping(address => uint256[]) private _receivedBy;

    event Sealed(
        uint256 indexed id,
        address indexed sender,
        address indexed recipient,
        uint64 unlockAt,
        uint64 drandRound,
        bool onSky,
        bytes ciphertext
    );
    event Opened(uint256 indexed id, address indexed opener, uint64 openedAt);

    error UnlockTooSoon();
    error UnlockTooFar();
    error EmptyCiphertext();
    error CiphertextTooLarge();
    error ZeroDrandRound();
    error UnknownCapsule();
    error StillLocked(uint64 unlockAt);
    error NotAllowed();
    error AlreadyOpened();

    /// @notice Seal a capsule. Works with any account, including Base Smart Wallets with sponsored gas.
    function seal(
        address recipient,
        uint64 unlockAt,
        uint64 drandRound,
        bool onSky,
        bytes calldata ciphertext
    ) external returns (uint256 id) {
        uint64 nowTs = uint64(block.timestamp);
        if (unlockAt < nowTs + MIN_LOCK) revert UnlockTooSoon();
        if (unlockAt > nowTs + MAX_LOCK) revert UnlockTooFar();
        if (drandRound == 0) revert ZeroDrandRound();
        if (ciphertext.length == 0) revert EmptyCiphertext();
        if (ciphertext.length > MAX_CIPHERTEXT) revert CiphertextTooLarge();

        id = _capsules.length;
        _capsules.push(
            Capsule({
                sender: msg.sender,
                sealedAt: nowTs,
                unlockAt: unlockAt,
                recipient: recipient,
                drandRound: drandRound,
                onSky: onSky,
                opened: false,
                ciphertextHash: keccak256(ciphertext)
            })
        );
        _sentBy[msg.sender].push(id);
        if (recipient != address(0) && recipient != msg.sender) _receivedBy[recipient].push(id);

        emit Sealed(id, msg.sender, recipient, unlockAt, drandRound, onSky, ciphertext);
    }

    /// @notice Mark a capsule as opened (the "it's open!" moment shown on the Capsule Sky).
    /// @dev Decryption itself happens off-chain once the drand round is published;
    ///      this only records the moment. Sender or recipient may open; link capsules can be opened by anyone.
    function open(uint256 id) external {
        if (id >= _capsules.length) revert UnknownCapsule();
        Capsule storage c = _capsules[id];
        if (block.timestamp < c.unlockAt) revert StillLocked(c.unlockAt);
        if (c.opened) revert AlreadyOpened();
        if (c.recipient != address(0) && msg.sender != c.recipient && msg.sender != c.sender) revert NotAllowed();
        c.opened = true;
        emit Opened(id, msg.sender, uint64(block.timestamp));
    }

    function getCapsule(uint256 id) external view returns (Capsule memory) {
        if (id >= _capsules.length) revert UnknownCapsule();
        return _capsules[id];
    }

    function totalCapsules() external view returns (uint256) {
        return _capsules.length;
    }

    function capsulesSentBy(address a) external view returns (uint256[] memory) {
        return _sentBy[a];
    }

    function capsulesFor(address a) external view returns (uint256[] memory) {
        return _receivedBy[a];
    }

    function isUnlocked(uint256 id) external view returns (bool) {
        if (id >= _capsules.length) revert UnknownCapsule();
        return block.timestamp >= _capsules[id].unlockAt;
    }

    /// @notice Verify a ciphertext (e.g. fetched from logs or an indexer) belongs to a capsule.
    function verifyCiphertext(uint256 id, bytes calldata ciphertext) external view returns (bool) {
        if (id >= _capsules.length) revert UnknownCapsule();
        return keccak256(ciphertext) == _capsules[id].ciphertextHash;
    }
}
