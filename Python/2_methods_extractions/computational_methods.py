import os
import glob
import pandas as pd
from llama_cpp import Llama
from tqdm import tqdm

# --- 1. AUTOMATIC MODEL SEARCH ---
gguf_files = glob.glob("../Qwen3.5-9B-Q8_0.gguf")
if not gguf_files:
    raise FileNotFoundError("Error: No Q8_0.gguf file found in the directory. Did you download the model?")
GGUF_MODEL_PATH = gguf_files[0]
print(f"Model found: {GGUF_MODEL_PATH}")

# --- 2. INCREMENTAL SAVE CONFIGURATION ---
RESULTS_FILE = 'qwen_method_results_gguf.csv'

print("Loading Excel file...")
NOME_FILE_EXCEL = 'vibe-coding-archaeology/Python/1_dataset/df_cleaned.xlsx'
df = pd.read_excel(NOME_FILE_EXCEL)

if 'eid' not in df.columns:
    print("Column 'eid' not found. Creating it automatically based on index...")
    df['eid'] = df.index

if 'abstract' not in df.columns:
    raise KeyError("Error: Cannot find a column named 'abstract' in your Excel file!")

if os.path.exists(RESULTS_FILE):
    saved_df = pd.read_csv(RESULTS_FILE)
    completed_indices = set(saved_df['eid'])
    print(f"Save file found. Skipping {len(completed_indices)} already processed abstracts.")
else:
    pd.DataFrame(columns=['eid', 'computational_methods']).to_csv(RESULTS_FILE, index=False)
    completed_indices = set()

# --- 3. MODEL LOADING ---
print("Loading into VRAM...")
llm = Llama(
    model_path=GGUF_MODEL_PATH,
    n_gpu_layers=-1,
    n_ctx=4096,
    seed=42, # Added seed for reproducibility
    verbose=False
)

# --- 4. EXTRACTION FUNCTION (multiple methods) ---
def extract_computational_methods(abstract_text):
    messages = [
        {
            "role": "system",
"content": (
    "You are a strict scientific classifier. Read the scientific abstract below "
    "and identify ALL computational methods and techniques used in the research.\n\n"
    "Rules:\n"
    "1. List every specific computational or statistical technique, separated by ' | '.\n"
    "2. Use the EXACT common name (e.g. 'Random Forest', 'PCA', 'k-means', 'LSTM', 'Kriging').\n"
    "3. Match the level of specificity in the abstract: if it names a specific technique "
    "(e.g. 'CNN', 'Random Forest'), use that name. If it only mentions a broad category "
    "(e.g. 'deep learning', 'machine learning'), use that — do NOT infer a specific method "
    "that is not explicitly stated.\n"    
    "4. Do NOT list software or languages (e.g. 'Python', 'R', 'QGIS', 'ArcGIS').\n"
    "5. Use standard capitalization for well-known techniques.\n"
    "6. If NO computational method is present, respond ONLY with: None\n"
    "7. Output ONLY the technique name(s). No explanations, no categories.\n\n"
    "Valid output examples:\n"
    "  Random Forest | PCA\n"
    "  Viewshed Analysis | KDE | k-means\n"
    "  CNN | LSTM\n"
    "  Deep Learning\n"
    "  ANOVA\n"
    "  None\n\n"
)
    
        },
        {
            "role": "user",
            "content": f"Abstract: {abstract_text}"
        }
    ]

    response = llm.create_chat_completion(
        messages=messages,
        max_tokens=150,      # Enough space for multiple labels
        temperature=0.01,
        seed=42              # Setting seed here as well for deterministic generation
    )

    text_response = response['choices'][0]['message']['content'].strip()

    # Clean up: remove quotes, dots, leftover newlines
    text_response = text_response.strip('"\'.').replace('\n', ' ').strip()

    # Normalize variants of "None"
    if text_response.lower() in ('none', 'no', 'n/a', '', '-'):
        return 'None'

    # Clean each single method in the list
    methods = [m.strip().strip('"\'.') for m in text_response.split('|')]
    methods = [m for m in methods if m]  # Remove empty elements

    return ' | '.join(methods)


# --- 5. PROCESSING LOOP ---
print("\nStarting processing...")
df_to_process = df[~df['eid'].isin(completed_indices)]
total = len(df_to_process)

for index, row in tqdm(df_to_process.iterrows(), total=total, desc="Abstract Classification", unit="doc", mininterval=600.0):
    current_id = row['eid']
    abstract_text = str(row['abstract'])

    if pd.isna(row['abstract']) or len(abstract_text) < 10:
        result = 'None'
    else:
        result = extract_computational_methods(abstract_text)

    new_row = pd.DataFrame({'eid': [current_id], 'computational_methods': [result]})
    new_row.to_csv(RESULTS_FILE, mode='a', header=False, index=False)

print("\nFinished! The CSV is complete and ready for analysis.")