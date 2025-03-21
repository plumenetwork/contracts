# Arc Smart Contracts
![Arc Icon](https://cdn.prod.website-files.com/670fc97cba6a0b3f2e579538/6720cf35961f6a507c874342_Arc_Icon.avif)
## Bring Anything Onchain

Put your assets onchain with **Arc**, Plume's open source full stack tokenization engine for real-world assets.

[Get Early Access](https://forms.plumenetwork.xyz/arc-waitlist)

---

## Arc Platform

### Tokenize in minutes, not months

Tokenizing anything today takes months and thousands of dollars. With Arc, you can now do it in minutes for much less and get legal help.

- **Tokenize in minutes**
- **Distribute right away**
- **Compose across RWAfi**

---

## Step by Step Process

Abstracted complexity in a simple step by step guide:

- **Fastest in the industry:** Create your asset tokens for free in a matter of minutes.
- **In great company:** Get supported by accredited infra, finance, and legal partners.
- **One-click storefronts:** Storefronts let users buy your tokenized assets seamlessly.
- **KYC/AML in place:** Distribute your assets with KYC and AML guarantees and rules.
- **Yield distribution:** Distribute yield in crypto or fiat to your token holders.
- **Collateralize:** Issue assets as collateral for stablecoin borrowing.
- **Unlock liquidity:** Deposit real-world assets into lending pools and earn interest.
- **And more...**

*Asset tokens from Arc are composable by design for RWAfi.*

---

## Infrastructure Partners

Integrated with industry-leading partners, Arc brings together the best in class for a superior tokenization experience.

[Become a partner](https://forms.plumenetwork.xyz/arc-waitlist)

- **Infrastructure providers:** Robust technological partnerships to strengthen your asset token's technical features.
- **Compliance and accreditation:** Third-party solutions that deliver advanced best practices in privacy and compliance.
- **Institutional-grade asset management:** Institutional-grade asset management and custody for those who need the very best.
- **Accredited legal partners:** Expert legal partners in SPV creation, asset management, jurisdiction compliance, and more.

---

## Upcoming Assets

Arc is bringing **$5.5B** of real-world assets onchain. With billions in committed assets ready to be tokenized and distributed, we are poised to realize an unparalleled RWAfi vision.

- **$2B in Private Credit:** ABL lending and specialty finance.
- **$1B in Energy Transition:** Solar energy assets and carbon credits.
- **$1B in Global Gov Bonds:** International government bonds.
- **$500M in Royalty Assets:** Music royalties and film/TV rights.
- **$500M in Metals & Mining:** Precious metals and critical commodities.
- **$500M in Digital Infra:** GPUs and BTC mining.

[Submit Application](https://forms.plumenetwork.xyz/arc-waitlist)

---

## ArcToken Role-Based Access Control

The ArcToken smart contract implements a robust role-based access control system that allows for fine-grained permission management. This enables asset issuers to delegate specific responsibilities to different team members or third-party service providers without granting them full control over the token.

### Available Roles

Each role has specific permissions and responsibilities:

#### DEFAULT_ADMIN_ROLE
- **Permissions**: Can grant and revoke any role, including other admin roles
- **Usage**: This is the most powerful role for managing the access control system itself
- **Best Practice**: Assign this to a secure multi-sig wallet or trusted entity

#### ADMIN_ROLE
- **Permissions**: Controls transfer restrictions (whitelist mode on/off)
- **Usage**: Used to toggle between restricted and unrestricted transfer modes
- **Best Practice**: Assign to compliance officers or regulatory supervisors

#### MANAGER_ROLE
- **Permissions**: 
  - Whitelist management (add/remove addresses)
  - Minting and burning tokens
  - Asset information management (name, valuation)
  - Metadata management (token URI)
  - Financial metrics management (issue price, accrual rates)
- **Usage**: Day-to-day operations and management of the token
- **Best Practice**: Assign to asset managers or token administrators

#### YIELD_MANAGER_ROLE
- **Permissions**: Configure the yield token address used for distributions
- **Usage**: Update which token is used for yield payouts (e.g., USDC)
- **Best Practice**: Assign to financial controllers or treasury managers

#### YIELD_DISTRIBUTOR_ROLE
- **Permissions**: Distribute yield to token holders
- **Usage**: Execute yield distribution to all token holders proportionally
- **Best Practice**: Assign to yield operators or automated distribution services

### Role Management

Roles can be managed using the following functions:

```solidity
// Grant a role
function grantRole(bytes32 role, address account) external;

// Revoke a role
function revokeRole(bytes32 role, address account) external;

// Check if an account has a role
function hasRole(bytes32 role, address account) external view returns (bool);
```

### Command Line Examples

Using the [Foundry](https://book.getfoundry.sh/)'s `cast` tool, you can interact with the role system:

```bash
# Grant MANAGER_ROLE to a new address
cast send TOKEN_ADDRESS "grantRole(bytes32,address)" MANAGER_ROLE_HASH NEW_MANAGER_ADDRESS --from ADMIN_ADDRESS

# Check if an address has MANAGER_ROLE
cast call TOKEN_ADDRESS "hasRole(bytes32,address)(bool)" MANAGER_ROLE_HASH ADDRESS_TO_CHECK

# Revoke YIELD_DISTRIBUTOR_ROLE from an address
cast send TOKEN_ADDRESS "revokeRole(bytes32,address)" YIELD_DISTRIBUTOR_ROLE_HASH DISTRIBUTOR_ADDRESS --from ADMIN_ADDRESS
```

### Best Practices

1. **Separation of Duties**: Assign different roles to different entities for better security
2. **Minimal Privileges**: Grant only the permissions necessary for each role
3. **Multi-sig Security**: Use multi-signature wallets for admin roles
4. **Regular Audits**: Periodically review role assignments and revoke unnecessary permissions
5. **Document Assignments**: Keep detailed records of which entities hold which roles
