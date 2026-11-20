# Security Policy

## Reporting a vulnerability

Please report security issues privately to the repository maintainers. Do not open a
public issue containing exploit details, credentials, or personal information. If GitHub
private vulnerability reporting is enabled for this repository, use that feature.

Include the affected component, impact, and steps to reproduce in your private report.
The maintainers will acknowledge the report and coordinate a fix before public disclosure.

## Automated security checks

Pull requests are checked for exposed secrets, vulnerable dependencies, and high or
critical vulnerabilities in the built container images. A failed check blocks merging
when branch protection is enabled.

No scan exceptions are currently documented. Any future exception must identify the
finding, affected component, reason for acceptance, compensating controls, owner, and
review or expiry date.
