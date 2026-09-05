FROM odoo:19.0

LABEL org.opencontainers.image.source="https://github.com/marcelo-m7/facodi-deploy"
LABEL org.opencontainers.image.title="FACODI Odoo"

USER root
COPY addons/ /opt/facodi-addon-sources/
COPY docker/entrypoint.sh /usr/local/bin/facodi-entrypoint
RUN set -eux; \
    chmod 0755 /usr/local/bin/facodi-entrypoint; \
    mkdir -p /mnt/extra-addons; \
    found=0; \
    for manifest in /opt/facodi-addon-sources/*/*/__manifest__.py; do \
      [ -e "$manifest" ] || continue; \
      d="$(dirname "$manifest")"; \
      n="$(basename "$d")"; \
      test ! -e "/mnt/extra-addons/$n"; \
      cp -a "$d" "/mnt/extra-addons/$n"; \
      found=1; \
    done; \
    test "$found" -eq 1; \
    chown -R odoo:odoo /mnt/extra-addons
USER odoo
ENTRYPOINT ["/usr/local/bin/facodi-entrypoint"]
CMD ["serve"]
