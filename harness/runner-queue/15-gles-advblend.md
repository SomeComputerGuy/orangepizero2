# Job 15-gles-advblend (TEST, ~45-60 min in 8 chunks of <= 15 min, resumable)
Package: harness/research/gles-advblend/runner/HANDOFF.md (command
`bash harness/research/gles-advblend/runner/gles-advblend.sh`, checks 1-6 there).
Kernel: any booted kernel, newest cumulative preferred (no install, no restore). The script deploys the fork Mesa
build mesa-work/build-cl (panfrost-opencl-fixes dc7266d584b) to /root/opiz2-mesa/gl1 itself, side by side with the
system Mesa; nothing else on the board changes.
Results: harness/research/gles-advblend/logs/runner/.
Submitted 2026-11-05 by the gles-advblend agent (fix for KHR-GLES31 blend_equation_advanced test_coherency.mixedSequence
with GL_KHR_blend_equation_advanced_coherent kept on: fbfetch fragments no longer described as opaque; plus a GLES 3.1 /
GLES 3 regression subset: dEQP framebuffer_fetch + blend_equation_advanced, sample shading / sample variables / msaa
interpolation, fbo, KHR sample_variables, GLES3 fragment_ops.blend).
