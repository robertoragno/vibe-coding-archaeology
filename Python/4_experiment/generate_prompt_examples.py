"""
Generate a txt file showing the three profile prompts for the same archaeological question.
Used to produce paper examples illustrating how prior knowledge shapes the input to the model.

Usage:
    python generate_prompt_examples.py [--question-index N] [--l2 "..."] [--vague "..."]

Defaults use question index 20 (settlement distribution) with a spatial-analysis framing.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from run_experiment import QUESTIONS_DATA, VAGUE_DATA, prompt_expert, prompt_intermediate, prompt_novice

DEFAULT_QUESTION_INDEX = 20   # "How do I analyse the distribution and organisation of human settlements..."
DEFAULT_L2  = "Spatial Analysis and Modelling"
DEFAULT_VAGUE = VAGUE_DATA[1]  # "some kind of spatial or geographic approach"

SEPARATOR = "=" * 72


def build_examples(question: str, l2: str, vague: str) -> str:
    blocks = [
        f"ARCHAEOLOGICAL QUESTION (same for all profiles)\n{SEPARATOR}\n{question}\n",
        f"PROFILE A — Expert\n{SEPARATOR}\n{prompt_expert(question, l2)}",
        f"PROFILE B — Intermediate\n{SEPARATOR}\n{prompt_intermediate(question, vague)}",
        f"PROFILE C — Novice\n{SEPARATOR}\n{prompt_novice(question)}",
    ]
    return ("\n\n" + SEPARATOR + "\n\n").join(blocks)


def main():
    parser = argparse.ArgumentParser(description="Generate example prompts for the three researcher profiles.")
    parser.add_argument("--question-index", type=int, default=DEFAULT_QUESTION_INDEX,
                        help=f"Index into QUESTIONS_DATA (0–{len(QUESTIONS_DATA)-1})")
    parser.add_argument("--l2",    default=DEFAULT_L2,    help="L2 method category for Profile A (Expert)")
    parser.add_argument("--vague", default=DEFAULT_VAGUE, help="Vague family string for Profile B (Intermediate)")
    parser.add_argument("--out",   default="prompt_examples.txt", help="Output txt file path")
    args = parser.parse_args()

    if not (0 <= args.question_index < len(QUESTIONS_DATA)):
        print(f"Error: --question-index must be between 0 and {len(QUESTIONS_DATA)-1}.")
        sys.exit(1)

    question = QUESTIONS_DATA[args.question_index]
    content  = build_examples(question, args.l2, args.vague)

    out_path = os.path.join(os.path.dirname(__file__), args.out)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(content + "\n")

    print(f"Written to: {out_path}")
    print(f"Question [{args.question_index}]: {question}")


if __name__ == "__main__":
    main()
