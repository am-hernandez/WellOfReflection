<!-- Improved compatibility of back to top link: See: https://github.com/othneildrew/Best-README-Template/pull/73 -->

<a id="readme-top"></a>

<!-- PROJECT SHIELDS -->

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]

<!-- PROJECT LOGO -->
<br />
<div align="center">

<h3 align="center">Well of Reflection</h3>

  <p align="center">
    A provably fair Ethereum lottery powered by Chainlink VRF v2.5
    <br />
    <a href="#how-it-works"><strong>Explore how it works »</strong></a>
    <br />
    <br />
    <a href="#usage">Run Locally</a>
    &middot;
    <a href="https://github.com/am-hernandez/wellOfReflection/issues/new?labels=bug">Report Bug</a>
    &middot;
    <a href="https://github.com/am-hernandez/wellOfReflection/issues/new?labels=enhancement">Request Feature</a>
  </p>
</div>

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#how-it-works">How It Works</a></li>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#contract-details">Contract Details</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>

## About the Project

Well of Reflection is a provably fair onchain game where visitors add ETH to a shared pool (“the Well”). Each visit triggers verifiable randomness via Chainlink VRF v2.5. That randomness is compared against a visitor-chosen imprint to determine whether the Well reflects the entire accumulated depth to the visitor.

### How It Works

1. **Make an Offering**  
   A visitor sends a fixed ETH offering (0.003 ETH) along with an imprint value.

2. **Request Verifiable Randomness**  
   The Well requests a random word from Chainlink VRF, recording the request ID and visitor.

3. **Resolve the Reflection**  
   The Chainlink VRF Coordinator fulfills the request by delivering a verifiable random word to the Well and the word is compared to the requestor's imprint for a match.

4. **Claim the Reflection**  
   If the imprint matches the random word under modulo comparison, the Well reflects and awards the entire accumulated depth to the visitor.

### Well Lifecycle

The Well operates in discrete, VRF-gated cycles:

- Each offering temporarily pauses the Well while randomness is pending.
- If no reflection occurs the Well unpauses for further offerings from other visitors.
- If a reflection occurs, the Well reflects its accumulated offerings to the visitor and a new cycle begins.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Built With

- [![Solidity][Solidity-badge]][Solidity-url]
- [![Foundry][Foundry-badge]][Foundry-url]
- [![Chainlink][Chainlink-badge]][Chainlink-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- GETTING STARTED -->

## Getting Started

To get a local copy up and running, follow these steps.

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) - Smart contract development toolkit
  ```sh
  curl -L https://foundry.paradigm.xyz | bash
  foundryup
  ```

### Installation

1. Clone the repo

   ```sh
   git clone https://github.com/am-hernandez/wellOfReflection.git
   cd well_of_reflection
   ```

2. Install dependencies

   ```sh
   forge install
   ```

3. Copy the environment file and configure

   ```sh
   cp .env.example .env
   ```

4. Build the contracts
   ```sh
   forge build
   ```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- USAGE EXAMPLES -->

## Usage

### Run Tests

```sh
forge test -vvv
```

### Local Development (Anvil)

1. **Start a local Anvil node** (in a separate terminal):

   ```sh
   make anvil
   ```

2. **Deploy contracts** (VRF infrastructure + Well; use `deploy` if infra is already deployed):

   ```sh
   make deploy-all
   ```

   Or in two steps: `make deploy-infra` then `make deploy`.

3. **Make an offering** (as a visitor; use a funded Anvil private key and an imprint):

   ```sh
   make offer PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 IMPRINT=42
   ```

4. **Fulfill the VRF request** (local only; uses mock coordinator; request ID from step 3):

   ```sh
   make fulfill REQUEST_ID=1 RANDOM_WORD=42
   ```

   Then the visitor can call `receiveReflection()` to claim if the well reflected.

### Clean Build Artifacts

```sh
make clean      # Remove build artifacts
make clean-all  # Remove build artifacts + deployments
```

### Makefile Commands

| Command             | Description                                                   |
| ------------------- | ------------------------------------------------------------- |
| `make anvil`        | Start local Anvil node with 50 funded accounts                |
| `make deploy-all`   | Deploy VRF infra then Well (full local setup)                 |
| `make deploy-infra` | Deploy VRF coordinator, Link mock, feed, subscription only    |
| `make deploy`       | Deploy Well (and wrapper if local); run after deploy-infra    |
| `make offer`        | Make an offering; requires `PK=` and `IMPRINT=`               |
| `make fulfill`      | Fulfill a VRF request (local only); requires `REQUEST_ID=`    |
| `make read-well`    | Read Well state (e.g. on Sepolia; needs WELL_ADDRESS_TESTNET) |
| `make mineblock`    | Mine 10 blocks on Anvil                                       |
| `make clean`        | Remove build cache                                            |
| `make clean-all`    | Remove build cache and deployments                            |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRACT DETAILS -->

## Contract Details

### WellOfReflection.sol

| Constant                | Value     | Description                                |
| ----------------------- | --------- | ------------------------------------------ |
| `OFFERING_AMOUNT`       | 0.003 ETH | Required offering per visitor              |
| `REFLECTION_MODULUS`    | 10,000    | Odds of reflection (1 in 10,000)           |
| `CALLBACK_GAS_LIMIT`    | 100,000   | Gas limit for VRF callback                 |
| `REQUEST_CONFIRMATIONS` | 5         | Block confirmations before VRF fulfillment |

### Key Functions

```solidity
// Make an offering with your chosen imprint
function makeOffering(uint256 imprint) external payable;

// Claim your reflection
function receiveReflection() external;

// Quote the current VRF fee
function quoteVrfFee() external view returns (uint256);
```

### Events

```solidity
event RequestSent(uint256 indexed requestId, uint256 indexed wellId, address indexed visitor);
event RequestFulfilled(uint256 indexed requestId, uint256 indexed wellId, address indexed visitor, bool reflected, uint256 depthAtResolution);
event ReflectionReceived(address indexed recipient, uint256 amount);
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- ROADMAP -->

## Roadmap

- [x] Core Well contract with VRF integration
- [x] Local deployment scripts with mock VRF
- [x] Simulation framework for testing
- [ ] Testnet deployment (Sepolia)
- [ ] Frontend interface
- [ ] Mainnet deployment
- [ ] Multi-well support

See the [open issues](https://github.com/am-hernandez/wellOfReflection/issues) for a full list of proposed features and known issues.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRIBUTING -->

## Contributing

Contributions are always welcome and are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LICENSE -->

## License

Distributed under the MIT License. See `LICENSE` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- ACKNOWLEDGMENTS -->

## Acknowledgments

- [Chainlink VRF v2.5](https://docs.chain.link/vrf) - Verifiable Random Function
- [Foundry](https://book.getfoundry.sh/) - Ethereum development toolkit
- [Best-README-Template](https://github.com/othneildrew/Best-README-Template)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->

[contributors-shield]: https://img.shields.io/github/contributors/am-hernandez/wellOfReflection.svg?style=for-the-badge
[contributors-url]: https://github.com/am-hernandez/wellOfReflection/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/am-hernandez/wellOfReflection.svg?style=for-the-badge
[forks-url]: https://github.com/am-hernandez/wellOfReflection/network/members
[stars-shield]: https://img.shields.io/github/stars/am-hernandez/wellOfReflection.svg?style=for-the-badge
[stars-url]: https://github.com/am-hernandez/wellOfReflection/stargazers
[issues-shield]: https://img.shields.io/github/issues/am-hernandez/wellOfReflection.svg?style=for-the-badge
[issues-url]: https://github.com/am-hernandez/wellOfReflection/issues
[license-shield]: https://img.shields.io/github/license/am-hernandez/wellOfReflection.svg?style=for-the-badge
[license-url]: https://github.com/am-hernandez/wellOfReflection/blob/main/LICENSE
[Solidity-badge]: https://img.shields.io/badge/Solidity-363636?style=for-the-badge&logo=solidity&logoColor=white
[Solidity-url]: https://soliditylang.org/
[Foundry-badge]: https://img.shields.io/badge/Foundry-3C3C3D?style=for-the-badge&logo=ethereum&logoColor=white
[Foundry-url]: https://book.getfoundry.sh/
[Chainlink-badge]: https://img.shields.io/badge/Chainlink-375BD2?style=for-the-badge&logo=chainlink&logoColor=white
[Chainlink-url]: https://chain.link/
