# Independent OAuth response cleanup probe

Lead source review, synthetic transport only; no real stores/network. See
../provider-auth/README.md for the lead reading (open after your own).
late-response.mjs is the unchanged probe. late-response-01 is retained setup
failure (relative module path); -02 is actual uncancelled-body RED, exit 1;
-03 is corrected lateBodyCancelled=true, calls 1, unchanged source, exit 0.
Each output records command/runtime/source identity. Worker immutable correction
2a6360c1 integrated 29f0dd24; subsequent full offline acceptance is separately
retained in ../provider-auth/attempt-01. No live authentication claim.
