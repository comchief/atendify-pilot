# Serves index.html for every path (SPA fallback), so real routes like
# /verify/{appNumber}, /portal, and /admin resolve instead of 404ing — Railway's
# auto-detected static-site build had no way to do this (confirmed: any
# non-root path 404s under it). This follows Railway's own documented pattern
# for SPA hosting (docs.railway.com/guides/spa-routing-configuration).
FROM caddy

WORKDIR /app

COPY Caddyfile ./
RUN caddy fmt Caddyfile --overwrite

# Only the one file that's actually served — atendify.html/atendify_artifact.html
# and everything under backend/ and scratch/ are working files, not site content.
COPY index.html ./

CMD ["caddy", "run", "--config", "Caddyfile", "--adapter", "caddyfile"]
