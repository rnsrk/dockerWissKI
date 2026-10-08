# OpenGDB authproxy with the patches from this directory applied.
# "upstream" is the untouched image built from the opengdb submodule
# (service authproxy-upstream in docker-compose.yml).
FROM upstream

USER root
COPY *.patch /tmp/patches/
# The patches are made against the open_gdb repository root, where the app
# lives in authproxy/. In the image it is /app, hence -p2.
RUN set -eux; \
    for patch in /tmp/patches/*.patch; do \
      patch -p2 -d /app < "${patch}"; \
    done; \
    rm -rf /tmp/patches
USER www-data:www-data
