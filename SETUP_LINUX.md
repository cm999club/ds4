# Setup ds4 (DwarfStar) su Linux con GPU AMD — ROCm

Aggiornato: 2026-07-07, repo su `main` (ROCm integrato upstream, il vecchio branch `rocm` non esiste più).

Macchina di riferimento: Ubuntu 26.04 LTS, Ryzen 9 9950X3D (16 core),
Radeon AI PRO R9700 32GB (RDNA4, arch ROCm `gfx1201`), 128GB RAM.

## Stato del supporto

- **ROCm è un backend di prima classe** insieme a Metal e CUDA (`ds4_rocm.cu` + `rocm/*.cuh`, kernel condivisi con CUDA via HIP).
- Il target primario upstream è **Strix Halo** (`gfx1151`, memoria unificata). La R9700 (`gfx1201`) è compatibile — kernel wave32, rocWMMA e hipBLASLt supportano gfx12 con ROCm 7.x — ma è **meno testata**: sei tra i primi su dGPU. Riporta risultati/problemi nella issue [#16](https://github.com/antirez/ds4/issues/16).
- Con 32GB di VRAM il modello q2 (~81GB) **non è residente**: si usa `--ssd-streaming` (ora supportato anche su ROCm, non più solo Metal). Con 128GB di RAM la page cache tiene quasi tutto il GGUF, quindi i cache-miss viaggiano a velocità RAM/PCIe, non SSD.

## 1. Installare ROCm 7.x

```sh
sudo apt-get update
sudo apt-get install -y \
  hipcc rocminfo rocm-smi \
  libamdhip64-dev \
  libhipblas-dev libhipblaslt-dev \
  librocblas-dev \
  librocwmma-dev \
  libhipcub-dev
```

Il pacchetto `librocwmma-dev` di Ubuntu 26.04 non include gli header
`rocwmma/internal/`. Installa l'albero header completo:

```sh
git clone --depth 1 --branch rocm-7.1.0 https://github.com/ROCm/rocWMMA.git /tmp/rocWMMA-rocm-7.1.0
sudo mkdir -p /usr/local/include
sudo cp -a /tmp/rocWMMA-rocm-7.1.0/library/include/rocwmma /usr/local/include/
```

Se il tooling si aspetta `/opt/rocm`:

```sh
sudo mkdir -p /opt/rocm/bin
sudo ln -sf /usr/bin/hipcc /opt/rocm/bin/hipcc
sudo ln -sfn /usr/lib/x86_64-linux-gnu /opt/rocm/lib
sudo ln -sfn /usr/include /opt/rocm/include
```

## 2. Accesso alla GPU

```sh
sudo usermod -aG render,video "$USER"
# logout/login o reboot, poi:
rocminfo | grep -i gfx1201
```

Se ds4 dice `no ROCm-capable device is detected`: verifica che `rocminfo`
apra `/dev/kfd` e che `groups` includa `render`.

**NON servono i parametri kernel di STRIXHALO.md §3** (`amdgpu.gttsize`,
`ttm.pages_limit`, ecc.): valgono solo per le APU a memoria unificata.
La R9700 ha 32GB di VRAM dedicata.

## 3. Build

```sh
make strix-halo ROCM_ARCH=gfx1201 -j"$(nproc)"
```

Il default è `ROCM_ARCH=gfx1151`: **va sempre sovrascritto** con `gfx1201`.
(`make rocm` è un alias di `make strix-halo`.) Produce `ds4`, `ds4-server`,
`ds4-bench`, `ds4-eval`, `ds4-agent`.

## 4. Modello

Il GGUF locale in `gguf/` è il vecchio q2 chat-v2 **non**-imatrix.
Il README ora raccomanda le versioni imatrix:

```sh
./download_model.sh q2-imatrix   # ~81GB, aggiorna il symlink ds4flash.gguf
./download_model.sh mtp          # ~3.5GB, opzionale: speculative decoding
```

Evita per ora `q2-q4-imatrix` (misto q2/q4) su ROCm: mette più pressione
di memoria sul path streaming.

## 5. Esecuzione

```sh
# Pre-carica il GGUF nella page cache (128GB RAM: ci sta tutto)
cat gguf/DeepSeek-V4-Flash-*imatrix*.gguf > /dev/null

./ds4 -m ds4flash.gguf --ssd-streaming --ctx 32768 --nothink
```

Con `--ssd-streaming` i pesi non-MoE restano residenti in VRAM e la cache
degli esperti routed si auto-dimensiona sulla VRAM libera (guarda la riga di
report all'avvio; se compare "cache capped/disabled" la VRAM è finita).
Puoi forzare la dimensione con `--ssd-streaming-cache-experts NGB`.

Quando è stabile:

```sh
# Speculative decoding (decode più veloce)
./ds4 -m ds4flash.gguf --ssd-streaming --ctx 32768 \
  --mtp gguf/DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf --mtp-draft 2

# Server OpenAI/Anthropic-compatibile con KV cache su disco
./ds4-server -m ds4flash.gguf --ssd-streaming --ctx 100000 \
  --kv-disk-dir /tmp/ds4-kv --kv-disk-space-mb 8192

# Coding agent nativo (alpha)
./ds4-agent
```

## 6. Troubleshooting

- Problemi di inferenza: rilancia con `--trace` e apri una issue con il trace completo.
- `hipcc` non trovato: controlla i symlink `/opt/rocm` del §1.
- Errori di compilazione su `rocwmma/internal/...`: header incompleti, rifai il fix rocWMMA del §1.
- Prestazioni prefill: il default ROCm è `--prefill-chunk 4096` (più sicuro); alzalo solo se hai margine VRAM.
- Benchmark: `./ds4-bench`, qualità: `./ds4-eval` (vedi `speed-bench/README.md`).
