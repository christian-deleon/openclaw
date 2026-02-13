# OpenClaw Docker Workflows
# Run with: just <recipe>

set dotenv-load := false
set shell := ["bash", "-cu"]

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

image := "openclaw:local"
container := "openclaw-gateway"
op_account := "my.1password.com"
op_env := "op.env"
config_volume := "openclaw-config"
workspace_volume := "openclaw-workspace"
gateway_port := env("OPENCLAW_GATEWAY_PORT", "18789")

# 1Password wrapper for commands needing secrets

op_run := "op run --env-file=" + op_env + " --account=" + op_account + " --"

# Docker compose shortcuts

dc := "docker compose"
dc_exec := dc + " exec " + container
dc_op := op_run + " " + dc
dc_exec_op := op_run + " " + dc_exec

# CLI inside container

cli_cmd := "node dist/index.js"

# ─────────────────────────────────────────────────────────────────────────────
# Default
# ─────────────────────────────────────────────────────────────────────────────

# Show available commands
default:
    @just --list

# ─────────────────────────────────────────────────────────────────────────────
# Setup & Build
# ─────────────────────────────────────────────────────────────────────────────

# Build the Docker image
build:
    docker build -t {{ image }} .

# Initialize volumes and copy config (first-time setup)
init: build
    docker volume create {{ config_volume }} || true
    docker volume create {{ workspace_volume }} || true
    docker run --rm -v {{ config_volume }}:/data -v "$(pwd)":/src alpine sh -c "cp /src/openclaw.json /data/openclaw.json && chown 1000:1000 /data/openclaw.json"
    @echo "Volumes initialized. Run 'just up' to start."

# Copy config into the volume
init-config:
    {{ dc }} cp openclaw.json {{ container }}:/home/node/.openclaw/openclaw.json
    {{ dc }} exec -u root {{ container }} chown node:node /home/node/.openclaw/openclaw.json
    {{ dc }} restart {{ container }}

# ─────────────────────────────────────────────────────────────────────────────
# Container Lifecycle
# ─────────────────────────────────────────────────────────────────────────────

# Start the gateway with 1Password secrets
up:
    {{ dc_op }} up -d

# Stop containers
down:
    {{ dc }} down

# Restart the gateway
restart:
    {{ dc }} restart {{ container }}

# Rebuild and restart
rebuild: build restart

# ─────────────────────────────────────────────────────────────────────────────
# Monitoring & Status
# ─────────────────────────────────────────────────────────────────────────────

# View gateway logs
logs:
    {{ dc }} logs -f {{ container }}

# Check channel status
status:
    {{ dc_exec_op }} {{ cli_cmd }} channels status

# Check health
health:
    {{ dc_exec_op }} {{ cli_cmd }} health

# ─────────────────────────────────────────────────────────────────────────────
# CLI & Commands
# ─────────────────────────────────────────────────────────────────────────────

# Run CLI command (usage: just cli <command>)
cli *args:
    {{ dc_exec_op }} {{ cli_cmd }} {{ args }}

# Approve a Telegram pairing code (usage: just approve <code>)
approve code:
    {{ dc_exec_op }} {{ cli_cmd }} pairing approve telegram {{ code }}

# Shell into the gateway container
shell:
    {{ dc_exec_op }} /bin/bash

# Open web UI with token
open:
    #!/usr/bin/env bash
    token=$(op read "op://kpunafc5jo6nt6f53sgj5geh5i/4y3xprwfmwxy5de4uftwd2eenu/password" --account={{ op_account }})
    open "http://localhost:{{ gateway_port }}/?token=${token}"

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────────────────────

# Clean up volumes (WARNING: destroys data)
clean:
    {{ dc }} down -v
    docker volume rm {{ config_volume }} {{ workspace_volume }} 2>/dev/null || true
