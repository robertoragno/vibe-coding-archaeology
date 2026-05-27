import pandas as pd

df = pd.read_csv("scopus_results.csv")
df = df.loc[df.doc_type == "Article"]
df['authors'] = df['authors'].replace('', pd.NA)
df['abstract'] = df['abstract'].replace('', pd.NA)
df = df.dropna(subset=['authors', 'abstract'])
df.to_excel("./df_cleaned.xlsx")