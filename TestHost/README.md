# iOS test host

Not part of the SDK, and not an example to copy: it trusts any TLS certificate, so that it can reach a test install. `scripts/test-ios-sim.sh` uses it to put the SDK's real views on a simulator and drive them against a live install.
