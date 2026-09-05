FROM odoo:19.0

LABEL org.opencontainers.image.source="https://github.com/marcelo-m7/facodi-deploy"
LABEL org.opencontainers.image.title="FACODI Odoo"

USER root
COPY addons/ /opt/facodi-addon-sources/
COPY vendor/odoo-design-themes/theme_common/ /opt/theme-common/theme_common/
COPY docker/entrypoint.sh /usr/local/bin/facodi-entrypoint
COPY docker/migrate.py /usr/local/lib/facodi/migrate.py
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends python3-venv; \
    rm -rf /var/lib/apt/lists/*; \
    python3 -m venv --system-site-packages /opt/facodi-venv; \
    /opt/facodi-venv/bin/pip install --no-cache-dir -r /opt/facodi-addon-sources/facodi-ai/requirements.txt; \
    /opt/facodi-venv/bin/python3 -c "import OpenSSL, cryptography, pydantic_ai"; \
    printf '%s\n' '#!/bin/sh' 'exec /opt/facodi-venv/bin/python3 /usr/bin/odoo "$@"' > /usr/local/bin/odoo; \
    chmod 0755 /usr/local/bin/odoo; \
    chmod 0755 /usr/local/bin/facodi-entrypoint; \
    chmod 0644 /usr/local/lib/facodi/migrate.py; \
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
    test ! -e /mnt/extra-addons/theme_common; \
    cp -a /opt/theme-common/theme_common /mnt/extra-addons/theme_common; \
    chown -R odoo:odoo /mnt/extra-addons
USER odoo
ENTRYPOINT ["/usr/local/bin/facodi-entrypoint"]
CMD ["serve"]
