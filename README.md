# Understanding Video Data at Scale
### A Hands-On Workshop with Action100M and FiftyOne

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/harpreetsahota204/fiftyone_video_workshop/blob/main/workshop.ipynb) [![Slides](https://img.shields.io/badge/Slides-Google%20Slides-4285F4?logo=google-slides&logoColor=white)](https://docs.google.com/presentation/d/18tVFu-Gw9QEtNFhopo6me0Oc2szs8b62mFlsz2ok4Z4/edit?usp=sharing)

---

Video is a hard modality to work with. You're dealing with more data, temporal complexity, and annotation workflows that don't scale. This workshop tackles a practical question: **given a large video dataset, how do you understand what's in it without manually watching thousands of clips?**

We work with a subset of [**Action100M preview**](https://www.arxiv.org/abs/2601.10592) [![arXiv](https://img.shields.io/badge/arXiv-2601.10592-b31b1b.svg)](https://arxiv.org/abs/2601.10592) — 1,144 YouTube videos, each clipped to 90 seconds, annotated with a hierarchical *Tree-of-Captions* structure produced by a fully automated AI pipeline. Every label in this dataset was written by a model. None of it was seen by a human annotator.

As AI-generated datasets become the norm, **the skill of interrogating machine-generated annotations is increasingly important**. This workshop shows you how to do that systematically.

---

## What We'll Build

|  | Question | Tools |
|---|---|---|
| 1. What We Were Given | What does this dataset claim to contain? | FiftyOne App |
| 2. Three Lenses | What does the raw data actually look like? | Qwen3-VL-Embedding, Molmo2, Sentence Transformers |
| 3. The Second Opinion | Does a second model agree with the first? | Qwen3-VL |
| 4. Measuring Agreement | How much do they agree, per sample? | Text Evaluation Plugin |

By the end, you'll have a **confidence map** of the dataset's annotations and a reusable workflow for understanding any video dataset with AI-generated labels.

---

## Setup

### Requirements

Install all dependencies with:

```bash
pip install -r requirements.txt
```

> **Running on Google Colab?** Uninstall `torchcodec` after installing requirements — it conflicts with Colab's video decoding stack:
> ```bash
> pip uninstall torchcodec -y
> ```

### Flash Attention (Optional)

`flash-attn` is not included in `requirements.txt` because it requires a compatible CUDA environment and can take a while to build. It is **not required**, but will significantly speed up inference with the transformer-based models in this workshop. If your environment supports it:

```bash
pip install flash-attn --no-build-isolation
```

---

## Dataset

### Option A: Start from scratch (follow along with the notebook)

Download the base Action100M subset from [the Voxel51 Hugging Face org](https://huggingface.co/datasets/Voxel51/action100m_tiny_subset):

```python
from fiftyone.utils.huggingface import load_from_hub

dataset = load_from_hub(
    "Voxel51/action100m_tiny_subset",
    dataset_name="action100m",
    overwrite=True,
    persistent=True,
)
```

### Option B: Use the pre-enriched dataset

If your compute is limited, the fully enriched dataset (with all embeddings, model outputs, and evaluation scores from the notebook already computed) is [available here](https://huggingface.co/datasets/harpreetsahota/fo_video_workshop_enriched):

```python
from fiftyone.utils.huggingface import load_from_hub

dataset = load_from_hub(
    "harpreetsahota/fo_video_workshop_enriched",
    dataset_name="action100m_enriched",
    overwrite=True,
    persistent=True,
)
```

#### Natural language search with the enriched dataset

The enriched dataset includes Qwen3-VL-Embedding vectors. To use the natural language search feature in the FiftyOne App, you need to register and download the model locally so FiftyOne can use it for query encoding:

```python
import fiftyone.zoo as foz

foz.register_zoo_model_source(
    "https://github.com/harpreetsahota204/qwen3vl_embeddings",
    overwrite=True
)

foz.download_zoo_model(
    "https://github.com/harpreetsahota204/qwen3vl_embeddings",
    model_name="Qwen/Qwen3-VL-Embedding-2B",
)
```

---

## Plugins

This workshop uses three FiftyOne plugins. Install them before running the notebook.

### Text Evaluation Metrics

Used in Section 4 to compute per-sample agreement scores between model outputs:

```bash
fiftyone plugins download https://github.com/harpreetsahota204/text_evaluation_metrics --overwrite
```

### Caption Viewer

Some captions in this dataset are long. This plugin renders any `StringField` in a formatted panel inside the FiftyOne App, making them much easier to read:

```bash
fiftyone plugins download https://github.com/harpreetsahota204/caption_viewer --overwrite
```

### FiftyComfy (Experimental)

An experimental panel used to demonstrate a few additional workflows in the notebook:

```bash
fiftyone plugins download https://github.com/harpreetsahota204/FiftyComfy --overwrite
```

---

## References and Citations

### Action100M

[![GitHub](https://img.shields.io/badge/GitHub-Action100M-181717?logo=github)](https://github.com/facebookresearch/Action100M)
[![arXiv](https://img.shields.io/badge/arXiv-2601.10592-b31b1b.svg)](https://arxiv.org/abs/2601.10592)
[![HuggingFace](https://img.shields.io/badge/🤗%20Dataset-action100m--preview-FFD21E)](https://huggingface.co/datasets/facebook/action100m-preview)

```bibtex
@article{chen2026action100m,
  title={Action100M: A Large-scale Video Action Dataset},
  author={Chen, Delong and Kasarla, Tejaswi and Bang, Yejin and Shukor, Mustafa and Chung, Willy and Yu, Jade and Bolourchi, Allen and Moutakanni, Théo and Fung, Pascale},
  journal={arXiv preprint arXiv:2601.10592},
  year={2026}
}
```

### Qwen3-VL-Embedding

[![GitHub](https://img.shields.io/badge/GitHub-Qwen3--VL--Embedding-181717?logo=github)](https://github.com/QwenLM/Qwen3-VL-Embedding)
[![arXiv](https://img.shields.io/badge/arXiv-2601.04720-b31b1b.svg)](https://arxiv.org/abs/2601.04720)
[![HuggingFace](https://img.shields.io/badge/🤗%20Model-Qwen3--VL--Embedding--2B-FFD21E)](https://huggingface.co/Qwen/Qwen3-VL-Embedding-2B)

```bibtex
@article{qwen3vlembedding,
  title={Qwen3-VL-Embedding and Qwen3-VL-Reranker: A Unified Framework for State-of-the-Art Multimodal Retrieval and Ranking},
  author={Li, Mingxin and Zhang, Yanzhao and Long, Dingkun and Chen, Keqin and Song, Sibo and Bai, Shuai and Yang, Zhibo and Xie, Pengjun and Yang, An and Liu, Dayiheng and Zhou, Jingren and Lin, Junyang},
  journal={arXiv},
  year={2026}
}
```

### Qwen3-VL

[![GitHub](https://img.shields.io/badge/GitHub-Qwen3--VL-181717?logo=github)](https://github.com/QwenLM/Qwen3-VL)
[![arXiv](https://img.shields.io/badge/arXiv-2511.21631-b31b1b.svg)](https://arxiv.org/abs/2511.21631)
[![HuggingFace](https://img.shields.io/badge/🤗%20Model-Qwen3--VL--8B--Instruct-FFD21E)](https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct)

```bibtex
@article{Qwen3-VL,
  title={Qwen3-VL Technical Report},
  author={Shuai Bai and Yuxuan Cai and Ruizhe Chen and Keqin Chen and Xionghui Chen and Zesen Cheng and Lianghao Deng and Wei Ding and Chang Gao and Chunjiang Ge and Wenbin Ge and Zhifang Guo and Qidong Huang and Jie Huang and Fei Huang and Binyuan Hui and Shutong Jiang and Zhaohai Li and Mingsheng Li and Mei Li and Kaixin Li and Zicheng Lin and Junyang Lin and Xuejing Liu and Jiawei Liu and Chenglong Liu and Yang Liu and Dayiheng Liu and Shixuan Liu and Dunjie Lu and Ruilin Luo and Chenxu Lv and Rui Men and Lingchen Meng and Xuancheng Ren and Xingzhang Ren and Sibo Song and Yuchong Sun and Jun Tang and Jianhong Tu and Jianqiang Wan and Peng Wang and Pengfei Wang and Qiuyue Wang and Yuxuan Wang and Tianbao Xie and Yiheng Xu and Haiyang Xu and Jin Xu and Zhibo Yang and Mingkun Yang and Jianxin Yang and An Yang and Bowen Yu and Fei Zhang and Hang Zhang and Xi Zhang and Bo Zheng and Humen Zhong and Jingren Zhou and Fan Zhou and Jing Zhou and Yuanzhi Zhu and Ke Zhu},
  journal={arXiv preprint arXiv:2511.21631},
  year={2025}
}
```

### Molmo2

[![GitHub](https://img.shields.io/badge/GitHub-Molmo2-181717?logo=github)](https://github.com/allenai/molmo2)
[![arXiv](https://img.shields.io/badge/arXiv-2601.10611-b31b1b.svg)](https://arxiv.org/abs/2601.10611)
[![HuggingFace](https://img.shields.io/badge/🤗%20Model-Molmo2--4B-FFD21E)](https://huggingface.co/allenai/Molmo2-4B)

```bibtex
@misc{clark2026molmo2,
      title={Molmo2: Open Weights and Data for Vision-Language Models with Video Understanding and Grounding},
      author={Christopher Clark and Jieyu Zhang and Zixian Ma and Jae Sung Park and Mohammadreza Salehi and Rohun Tripathi and Sangho Lee and Zhongzheng Ren and Chris Dongjoo Kim and Yinuo Yang and Vincent Shao and Yue Yang and Weikai Huang and Ziqi Gao and Taira Anderson and Jianrui Zhang and Jitesh Jain and George Stoica and Winson Han and Ali Farhadi and Ranjay Krishna},
      year={2026},
      eprint={2601.10611},
      archivePrefix={arXiv},
      primaryClass={cs.CV},
      url={https://arxiv.org/abs/2601.10611},
}
```

### jina-embeddings-v5-text

[![arXiv](https://img.shields.io/badge/arXiv-2602.15547-b31b1b.svg)](https://arxiv.org/abs/2602.15547)
[![HuggingFace](https://img.shields.io/badge/🤗%20Model-jina--embeddings--v5--text--nano--classification-FFD21E)](https://huggingface.co/jinaai/jina-embeddings-v5-text-nano-classification)
[![HuggingFace](https://img.shields.io/badge/🤗%20Model-jina--embeddings--v5--text--nano--clustering-FFD21E)](https://huggingface.co/jinaai/jina-embeddings-v5-text-nano-clustering)

```bibtex
@misc{akram2026jinaembeddingsv5texttasktargetedembeddingdistillation,
      title={jina-embeddings-v5-text: Task-Targeted Embedding Distillation},
      author={Mohammad Kalim Akram and Saba Sturua and Nastia Havriushenko and Quentin Herreros and Michael Günther and Maximilian Werk and Han Xiao},
      year={2026},
      eprint={2602.15547},
      archivePrefix={arXiv},
      primaryClass={cs.CL},
      url={https://arxiv.org/abs/2602.15547},
}
```

---

## License

The code and workshop content in this repository are licensed under [Apache 2.0](LICENSE).

Models and datasets referenced in this workshop are subject to their own respective licenses — please consult each project directly before use.

---

## Issues

Found a bug or have a question? [Open an issue](https://github.com/harpreetsahota204/fiftyone_video_workshop/issues).

Contributions are not being accepted.
