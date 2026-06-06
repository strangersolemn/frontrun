// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// FRONTRUN — TESTNET PROOF (Sepolia).
// Goal: prove the mechanic end-to-end, fully on-chain:
//   • the art is derived from the CURRENT owner's wallet (read live in tokenURI)
//   • move a token to a new wallet -> its image + animation re-derive from that wallet
//   • image (thumbnail) is generated on-chain as SVG (NOT a stored screenshot),
//     so it updates per holder on metadata refresh
//   • animation_url is on-chain HTML (a small wallet-reactive address tunnel)
// This uses a COMPACT inline engine for the proof. The full glitch-lab art ships
// for mainnet via EthFS. Nothing here is final — it's the working testnet version.

import "@openzeppelin/contracts@5.0.2/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts@5.0.2/utils/Strings.sol";
import "@openzeppelin/contracts@5.0.2/utils/Base64.sol";

contract FrontrunTest is ERC721 {
    using Strings for uint256;
    using Strings for uint160;

    uint256 public nextId;
    uint256 public constant MAX = 420;

    constructor() ERC721("FRONTRUN (testnet)", "FRONTRUN") {}

    // free mint for testing
    function mint() external {
        require(nextId < MAX, "sold out");
        _safeMint(msg.sender, nextId);
        nextId++;
    }

    // ---- derive look from the wallet ----
    function _accent(address a) internal pure returns (string memory) {
        string[6] memory p = ["#ED1E79","#00F0FF","#00FF95","#FFAE00","#FF003C","#9D00FF"];
        return p[uint160(a) % 6];
    }
    function _addr(address a) internal pure returns (string memory) {
        return uint160(a).toHexString(20); // 0x + 40 hex, lowercase
    }

    // on-chain SVG "address tunnel" generated from the current owner
    function _svg(address owner) internal pure returns (string memory) {
        string memory acc = _accent(owner);
        string memory ad  = _addr(owner);
        string memory rows;
        for (uint256 i = 0; i < 9; i++) {
            uint256 y  = 70 + i * 44;
            uint256 fs = 8 + i * 2;          // grow outward = perspective
            uint256 op = 25 + i * 8;         // 0.25 -> 0.89
            rows = string(abi.encodePacked(
                rows,
                '<text x="250" y="', y.toString(),
                '" font-family="monospace" font-weight="bold" font-size="', fs.toString(),
                '" fill="', acc, '" fill-opacity="0.', op.toString(),
                '" text-anchor="middle">', ad, '</text>'
            ));
        }
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" width="500" height="500" viewBox="0 0 500 500">',
            '<rect width="500" height="500" fill="#05060a"/>', rows,
            '<text x="250" y="486" font-family="monospace" font-weight="bold" font-size="13"',
            ' letter-spacing="4" fill="', acc, '" text-anchor="middle">FRONTRUN</text></svg>'
        ));
    }

    // on-chain animated HTML, reads the current owner
    function _html(address owner) internal pure returns (string memory) {
        string memory acc = _accent(owner);
        string memory ad  = _addr(owner);
        return string(abi.encodePacked(
            "<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>",
            "<body style='margin:0;background:#05060a;overflow:hidden'><canvas id=c></canvas><script>",
            "var O='", ad, "',A='", acc, "';var c=document.getElementById('c'),x=c.getContext('2d');",
            "function R(){c.width=innerWidth;c.height=innerHeight}R();onresize=R;var t=0;",
            "function f(){t+=1.2;x.fillStyle='#05060a';x.fillRect(0,0,c.width,c.height);",
            "var w=c.width,h=c.height,cx=w/2,cy=h/2;x.textAlign='center';x.fillStyle=A;",
            "for(var i=0;i<16;i++){var s=((i*26+t)%416)/416;x.globalAlpha=Math.min(1,1-s);",
            "x.font=(6+s*52)+'px monospace';x.fillText(O,cx,cy-(s-0.5)*h*1.1);}",
            "x.globalAlpha=1;requestAnimationFrame(f)}f();</script></body>"
        ));
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        address owner = ownerOf(id); // reverts if not minted
        string memory img  = Base64.encode(bytes(_svg(owner)));
        string memory anim = Base64.encode(bytes(_html(owner)));
        string memory json = string(abi.encodePacked(
            '{"name":"FRONTRUN #', id.toString(),
            '","description":"FRONTRUN testnet proof. Fully on-chain. The art is generated from the wallet that holds it - send it to a new wallet and it re-renders.",',
            '"image":"data:image/svg+xml;base64,', img,
            '","animation_url":"data:text/html;base64,', anim,
            '","attributes":[{"trait_type":"Holder","value":"', _addr(owner), '"}]}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }
}
