FROM sha256:debdba9954b1065ab1ce723c6c1f2f22e52a78c164f863b938d58cc2c9f0d337
COPY --chown=0:0 toolchain/ /opt/mo/
USER 65534:65534
WORKDIR /workspace
ENV PATH=/opt/mo:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV HOME=/build TMPDIR=/tmp ZIG_GLOBAL_CACHE_DIR=/build/zig-global ZIG_LOCAL_CACHE_DIR=/build/zig-local
