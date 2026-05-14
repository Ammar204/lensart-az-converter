# ── Stage 1: Build Node dependencies ─────────────────────────────────────────
FROM node:20-slim AS deps

WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

# ── Stage 2: Runtime image ────────────────────────────────────────────────────
FROM node:20-slim AS runtime

# Install Python 3, pip, and build tools needed by usd2gltf
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    libglib2.0-0 \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Install usd2gltf in a virtual env to avoid PEP 668 "externally managed" errors
RUN python3 -m venv /opt/usdenv \
    && /opt/usdenv/bin/pip install --no-cache-dir usd2gltf

# Patch upstream bug: usd2gltf concatenates `uv_map_name` (sometimes None) with strings.
# https://github.com/.../usd2gltf — usd_material.py:148 raises TypeError on iOS LiDAR USDZ.
RUN sed -i 's/+ uv_map_name +/+ str(uv_map_name) +/g' \
    /opt/usdenv/lib/python3.11/site-packages/usd2gltf/converters/usd_material.py

# Make usd2gltf available on PATH
ENV PATH="/opt/usdenv/bin:$PATH"

WORKDIR /app

# Copy Node deps from build stage
COPY --from=deps /app/node_modules ./node_modules

# Copy application source
COPY package.json ./
COPY src/ ./src/

# Run as non-root for security
RUN useradd --uid 1001 --no-create-home appuser
USER appuser

# The container exits after the job finishes (ECS task, not a server)
ENTRYPOINT ["node", "src/index.js"]
