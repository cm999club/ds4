#!/bin/bash
# Quick start ds4 (DwarfStar) — Ubuntu + ROCm, GPU AMD gfx1201 (R9700 32GB)
# Aggiornato: 2026-07-07. Dettagli: SETUP_LINUX.md
set -e
cd "$(dirname "$0")"

ROCM_ARCH="${ROCM_ARCH:-gfx1201}"
MODEL_LINK="./ds4flash.gguf"
MTP_FILE="gguf/DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  ds4 Quick Start — Linux + ROCm ($ROCM_ARCH)                  ║"
echo "╚═══════════════════════════════════════════════════════════════╝"

# ── 1/4 Prerequisiti ROCm ──────────────────────────────────────────
echo "[1/4] Verifica prerequisiti ROCm..."
HIPCC="$(command -v hipcc || echo /opt/rocm/bin/hipcc)"
if [ ! -x "$HIPCC" ]; then
    echo "❌ hipcc non trovato. Installa ROCm (SETUP_LINUX.md §1):"
    echo "   sudo apt-get install hipcc rocminfo rocm-smi libamdhip64-dev \\"
    echo "     libhipblas-dev libhipblaslt-dev librocblas-dev librocwmma-dev libhipcub-dev"
    exit 1
fi
if ! command -v rocminfo >/dev/null; then
    echo "❌ rocminfo non trovato (pacchetto rocminfo)."; exit 1
fi
if ! rocminfo 2>/dev/null | grep -qi "$ROCM_ARCH"; then
    echo "❌ GPU $ROCM_ARCH non visibile da rocminfo."
    echo "   Controlla /dev/kfd e i gruppi: sudo usermod -aG render,video \$USER (poi re-login)."
    exit 1
fi
ROCWMMA_INC=""
for d in /usr/local/include /usr/include /opt/rocm/include; do
    [ -f "$d/rocwmma/rocwmma.hpp" ] && ROCWMMA_INC="$d" && break
done
if [ -z "$ROCWMMA_INC" ] || [ ! -d "$ROCWMMA_INC/rocwmma/internal" ]; then
    echo "❌ Header rocWMMA incompleti (manca rocwmma/internal/). Fix (SETUP_LINUX.md §1):"
    echo "   git clone --depth 1 --branch rocm-7.1.0 https://github.com/ROCm/rocWMMA.git /tmp/rocWMMA"
    echo "   sudo cp -a /tmp/rocWMMA/library/include/rocwmma /usr/local/include/"
    exit 1
fi
echo "✓ hipcc, rocminfo ($ROCM_ARCH), rocWMMA ok"

# ── 2/4 Build ──────────────────────────────────────────────────────
echo "[2/4] Build (make strix-halo ROCM_ARCH=$ROCM_ARCH)..."
make strix-halo ROCM_ARCH="$ROCM_ARCH" -j"$(nproc)"
echo "✓ Binari: ds4 ds4-server ds4-bench ds4-eval ds4-agent"

# ── 3/4 Modello ────────────────────────────────────────────────────
echo "[3/4] Verifica modello..."
if [ ! -e "$MODEL_LINK" ]; then
    echo "❌ $MODEL_LINK mancante. Scarica il q2 imatrix (~81GB):"
    echo "   ./download_model.sh q2-imatrix"
    exit 1
fi
REAL_MODEL="$(readlink -f "$MODEL_LINK")"
case "$REAL_MODEL" in
    *imatrix*) echo "✓ Modello imatrix: $(basename "$REAL_MODEL")" ;;
    *) echo "⚠ Modello NON-imatrix ($(basename "$REAL_MODEL"))."
       echo "  Consigliato: ./download_model.sh q2-imatrix (aggiorna il symlink)." ;;
esac
[ -f "$MTP_FILE" ] || echo "ℹ MTP assente (opzionale, decode più veloce): ./download_model.sh mtp"

# ── 4/4 Smoke test ─────────────────────────────────────────────────
echo "[4/4] Warm della page cache (prima volta: qualche minuto)..."
cat "$REAL_MODEL" > /dev/null || true
echo "Smoke test (--ssd-streaming: 81GB > 32GB VRAM)..."
./ds4 -m "$MODEL_LINK" --ssd-streaming --ctx 8192 --nothink \
      --tokens 64 -p "Rispondi con una sola frase: perché il cielo è blu?"

cat <<'EOF'

✓ Tutto ok. Prossimi passi:
  CLI:    ./ds4 -m ds4flash.gguf --ssd-streaming --ctx 32768
  MTP:    aggiungi --mtp gguf/DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf --mtp-draft 2
  Server: ./ds4-server -m ds4flash.gguf --ssd-streaming --ctx 100000 \
            --kv-disk-dir /tmp/ds4-kv --kv-disk-space-mb 8192
  Agent:  ./ds4-agent
All'avvio controlla la riga di report della cache esperti (VRAM).
Problemi? Rilancia con --trace e apri una issue (riferimento dGPU: issue #16).
EOF
