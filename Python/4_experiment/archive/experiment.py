import pandas as pd
import random

L2 = pd.read_excel('L2.xlsx')
VAGUE = pd.read_excel('Vague.xlsx')
QUESTIONS = pd.read_excel('Questions.xlsx')

l2_col = L2.columns[0]
vague_col = VAGUE.columns[0]
question_col = QUESTIONS.columns[0]

def sample_inputs():
    l2 = L2[l2_col].dropna().sample(1).values[0]
    vague = VAGUE[vague_col].dropna().sample(1).values[0]
    question = QUESTIONS[question_col].dropna().sample(1).values[0]
    return l2, vague, question

def prompt_expert(question, l2):
    return f"""You are a research assistant for computational archaeologists.

A researcher comes to you with the following problem:

"I am working on: {question}
I already know I want to apply {l2} to my analysis.
Which specific tools, algorithms, or variants of this method would you
recommend, and how would you apply them concretely to this problem?"

List the computational methods you would use, being as specific as possible.
For each method, provide a one-sentence justification."""

def prompt_intermediate(question, vague):
    return f"""You are a research assistant for computational archaeologists.

A researcher comes to you with the following problem:

"I am working on: {question}
I have a rough idea that I need {vague},
but I do not know which specific method to choose.
What would you recommend?"

List the computational methods you would use, being as specific as possible.
For each method, provide a one-sentence justification."""

def prompt_novice(question):
    return f"""You are a research assistant for computational archaeologists.

A researcher comes to you with the following problem:

"I am working on: {question}
I have no specific computational background.
Which digital methods could I use to address this research problem?"

List the computational methods you would use, being as specific as possible.
For each method, provide a one-sentence justification."""

def generate_prompts():
    l2, vague, question = sample_inputs()
    
    return {
        "inputs": {
            "question": question,
            "l2": l2,
            "vague": vague
        },
        "prompts": {
            "expert":       prompt_expert(question, l2),
            "intermediate": prompt_intermediate(question, vague),
            "novice":       prompt_novice(question)
        }
    }

# Test
result = generate_prompts()
print("=== INPUTS ===")
for k, v in result["inputs"].items():
    print(f"{k}: {v}")

for profile, prompt in result["prompts"].items():
    print(f"\n=== PROFILE: {profile.upper()} ===")
    print(prompt)