"""Local Kev-4B server using the prebuilt 8-bit MLX weights (RoderickQiu/kev-4b-mlx-8bit).

Kev's own server (kev.serve) loads the 9 GB bf16 base and merges the adapter itself. This patches its MLX loader
to read the 4.5 GB prebuilt 8-bit weights instead (~6.6 GB RAM while scoring), then runs kev.serve unchanged,
so the API is the standard POST /v1/systemone. Approach adapted from Qualm's src/qualm/kevserve.py.

Run from the repo root:
    uv run --project vendor/kev python local/kev_server.py --port 8009
"""
import runpy
import sys
from pathlib import Path

# The 8-bit weights were built from this exact Kev checkpoint; tokenizer, head and temperature come from it too.
KEV_CHECKPOINT = "jaredpalmer/kev-4b@139fdd94f1b6a6ad80cc15e08fcb99cac885a101"
WEIGHTS_REPO = "RoderickQiu/kev-4b-mlx-8bit"


def main():
    import mlx.core as mx
    from huggingface_hub import snapshot_download
    from kev.checkpoint import Checkpoint
    from kev.mlx_model import MLXDecisionModel
    from kev.model import PointerHead, pad_id

    mx.set_cache_limit(1 << 30)  # hand freed Metal buffers back to macOS instead of hoarding them

    print(f"fetching {WEIGHTS_REPO} (4.5 GB the first time)", flush=True)
    weights = Path(snapshot_download(WEIGHTS_REPO, allow_patterns=["config.json", "model.safetensors"]))

    def load_8bit(self, tok, opts):
        m = MLXDecisionModel(weights, pad_id(tok), head_dim=self.meta.head_dim)
        # The head is sized from the embedding width, which is packed in quantized weights: use the real one.
        m.head = PointerHead(m.text.embed_tokens.dims, dp=self.meta.head_dim).eval()
        return m  # Checkpoint.load then loads the fp32 head weights and the fitted temperature

    Checkpoint._load_mlx = load_8bit

    port = sys.argv[sys.argv.index("--port") + 1] if "--port" in sys.argv else "8009"
    sys.argv = ["kev.serve", "--run", KEV_CHECKPOINT, "--port", port]
    runpy.run_module("kev.serve", run_name="__main__")


if __name__ == "__main__":
    main()
