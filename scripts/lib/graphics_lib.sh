#!/usr/bin/env bash
# Advanced graphics env helpers (Phase E): DXMT channel, MetalFX, MoltenVK presets.

cosmos_dxmt_channel_apply() {
  local channel="${COSMOS_DXMT_CHANNEL:-stable}"
  case "${channel}" in
    experimental)
      DXMT_VERSION="${DXMT_VERSION:-0.81}"
      export DXMT_VERSION
      export COSMOS_ALLOW_LGPL="${COSMOS_ALLOW_LGPL:-1}"
      DXMT_URL="${DXMT_URL:-https://github.com/3Shain/dxmt/releases/download/v${DXMT_VERSION}/dxmt-v${DXMT_VERSION}-builtin.tar.gz}"
      export DXMT_URL
      ;;
    stable|"") ;;
    *) COSMOS_DXMT_CHANNEL="stable" ;;
  esac
}

cosmos_metalfx_apply() {
  case "${COSMOS_METALFX:-0}" in
    1|true|yes)
      local existing="${DXMT_CONFIG:-}"
      if [[ "${existing}" != *"metalFxUpscale"* ]]; then
        DXMT_CONFIG="${existing}d3d11.metalFxUpscale=1;"
        export DXMT_CONFIG
      fi
      ;;
  esac
}

cosmos_moltenvk_preset_apply() {
  local preset="${COSMOS_MVK_PRESET:-default}"
  case "${preset}" in
    performance)
      export MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=0
      export MVK_CONFIG_FAST_MATH=1
      ;;
    compatibility)
      export MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1
      export MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0
      ;;
    default|"") ;;
    *) COSMOS_MVK_PRESET="default" ;;
  esac
}

cosmos_graphics_env_apply() {
  cosmos_dxmt_channel_apply
  cosmos_metalfx_apply
  cosmos_moltenvk_preset_apply
}
