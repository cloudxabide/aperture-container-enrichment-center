# NeuVector Overview

NeuVector is fully Open Source (as of 2022 when SUSE took this step). As such NeuVector is consumable in many ways:
- NeuVector (OSS)
- SUSE Security
- RGS NeuVector

---

All three are the same underlying codebase at different layers of packaging, support, and hardening:

**NeuVector OSS**
The upstream, community open-source project (Apache 2.0), open-sourced by SUSE in January 2022, making it the first end-to-end open-source container security platform. It has Deep Packet Inspection that analyzes network traffic up to Layer 7 to detect DDoS, tunneling, SQL injection, and Kubernetes-specific attacks, plus vulnerability scanning, admission control, and compliance auditing. This is the free, self-supported, community-maintained version — no SUSE subscription, no formal SLA, updates come straight from the GitHub project.

**SUSE Security**
SUSE Security is the evolution of what was previously called NeuVector — it's SUSE's commercially supported, branded distribution of the same engine. Same core capabilities as the OSS project, but wrapped with SUSE subscription support, SLAs, official hardened builds, and integration into the broader SUSE/Rancher Prime commercial stack (SLE Micro, Rancher Prime, etc.). It's aimed at general enterprise customers who want vendor support behind the open-source technology rather than running it unsupported.

**RGS NeuVector**
This is Rancher Government Solutions' own federal-specific branding and hardening layer on top of NeuVector, built for the DoD/IC/federal market RGS serves. Per RGS's own materials, RGS NeuVector provides embedded, FIPS-compliant runtime protection as part of the RGS government stack (alongside RGS Manager, RGS HCI, RGS Storage, etc.). Practically, that means:
- FIPS-validated cryptographic modules baked in
- Air-gapped/disconnected deployment support (no phone-home, offline vuln DB updates, etc.)
- STIG-aligned configurations out of the box
- Packaged and supported specifically for IL4/IL5/IL6 and classified environments
- Backed by RGS's US-citizen support staff (relevant for cleared/ITAR-sensitive environments) rather than generic SUSE commercial support

So the relationship is essentially: **NeuVector OSS** (community core) → **SUSE Security** (SUSE's commercial enterprise distribution) → **RGS NeuVector** (RGS's further-hardened, FIPS/STIG-aligned, air-gap-ready distribution purpose-built for U.S. federal/DoD/IC use cases). For your customer docs, the key differentiator to lead with is usually the compliance/support layer — RGS Security exists specifically because raw NeuVector OSS or standard SUSE Security don't carry the FIPS validation, STIG baseline, and disconnected-ops packaging federal buyers require out of the box.

---

While all three of these offerings are built on the exact same core zero-trust container security technology (NeuVector), the differences come down to support, target audience, compliance certifications, and lifecycle management. 

SUSE open-sourced NeuVector in 2022, meaning the core technology is identical across the board. Here is how the three specific distributions differ:

**1. NeuVector OSS (Open Source)**
* **Target Audience:** Individual developers, community users, and organizations with strong internal Kubernetes security expertise who do not need commercial backing.
* **Features:** It includes the full underlying technology, such as Deep Packet Inspection (DPI), vulnerability scanning, admission control, and runtime protection. (SUSE made NeuVector 100% open source, so features are not artificially paywalled).
* **Support:** Community-supported. There are no Service Level Agreements (SLAs), no guaranteed response times for bug fixes, and no indemnification.
* **Cost:** Free.

**2. SUSE Security (NeuVector Prime)**
* **Target Audience:** Global commercial enterprises and large organizations.
* **Features:** This is the commercially packaged, enterprise-ready version of NeuVector. It includes everything in the OSS version but is tested, validated, and integrated tightly with SUSE Rancher Prime.
* **Support:** Backed by SUSE's global enterprise support network. It includes 24/7 commercial support, guaranteed SLAs, enterprise lifecycle management, and indemnification.
* **Cost:** Paid enterprise subscription based on node counts.

**3. RGS NeuVector (Rancher Government Solutions)**
* **Target Audience:** The US Federal Government, Department of Defense (DoD), Intelligence Community (IC), and highly regulated US public sector entities.
* **Features:** This version is specifically hardened and packaged to meet strict US Government mandates. It includes FIPS 140-2/140-3 validated cryptography, DISA STIG (Security Technical Implementation Guide) compliance, and is often delivered through secure federal supply chains (like Platform One's Iron Bank). It is also heavily optimized for fully air-gapped and disconnected environments.
* **Support:** Exclusively supported by Rancher Government Solutions. Support is provided strictly by US citizens on US soil, with appropriately cleared personnel available for classified environments.
* **Cost:** Paid subscription procured through federal contracting channels. 

**Summary**
If you want to run it yourself for free, use **NeuVector OSS**. If you are a standard commercial enterprise needing reliable global support and SLAs, use **SUSE Security (NeuVector Prime)**. If you are a US government entity or defense contractor that requires FIPS validation, STIGs, and US-citizen support, you must use **RGS Security**.
