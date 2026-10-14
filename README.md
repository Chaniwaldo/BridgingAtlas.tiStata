# atlas2stata

Turn three ATLAS.ti Excel exports (table code cooccurrences, table document_code and wordlist) into statistics and two-axis maps of your codes, **all from one Stata 18 do-file** (`atlas2stata.do`). The file embeds a short Python block for the data preparation, so there is nothing else to run.

## What you get

| Output | Folder | Content |
|---|---|---|
| Code ranking | `figures/01_code_frequencies.png`, `stata_data/code_statistics.csv` | Quotations and documents per code |
| Word ranking | `figures/02_word_frequencies.png` | Word frequencies (stop words removed) |
| Top code pairs | `stata_data/top_pairs.csv` | Co-occurrences in quotations and documents |
| Code maps | `figures/03_mds_quote.png`, `03_mds_doc.png`, `stata_data/mds_coords_*.csv` | 2-D map (MDS on Jaccard distances) |
| Correspondence analysis | `figures/04_ca_biplot.png` | Codes x documents |
| Datasets | `stata_data/*.dta` | `codes`, `code_doc_long`, `pairs`, `dist_quote`, `dist_doc`, `words` |

## Requirements

- Stata 18 (Python integration) and Python 3.9+.
- Python packages: `pip install pandas numpy openpyxl` (in the same Python that Stata uses).

## Set-up (once)

In Stata:

```stata
python search
python set exec "C:/path/to/python.exe", permanently
python query
python which pandas
```

## Use

1. **Export from ATLAS.ti to Excel** and save in a folder `atlas_exports/` with these exact names:
   - `code_document.xlsx`: Code-Document Table, counts = quotations.
   - `code_cooccurrence.xlsx`: Code Co-occurrence Table, Show Count (not the coefficient).
   - `word_list.xlsx`: Word List.
2. Put `atlas2stata.do` and `atlas_exports/` in one project folder.
3. Open `atlas2stata.do`, edit the **SETTINGS** block (at least `global PROJECT`, use `/` in paths).
4. Run: `do atlas2stata.do`

### Settings

| Global | Default | Meaning |
|---|---|---|
| `PROJECT` | `C:/atlas2stata` | Project folder |
| `IN`, `OUT`, `FIG` | `atlas_exports`, `stata_data`, `figures` | Folders (no spaces) |
| `LANG` | `es` | Stop words: `es`, `en` or `none` |
| `MINLEN` | `4` | Minimum word length |
| `TOPN`, `WORDN` | `15`, `30` | Items in code and word rankings |
| `LABPCT` | `80` | Only codes above this percentile of quotations are labelled on maps |

## How it works

1. **Python block:** reads the Excel files; removes symbols, `Gr=n` tags, totals, codes without quotations and documents without coded quotations; aligns the co-occurrence matrix with the code list; builds document-level co-occurrence; computes Jaccard distances `d = 1 - c / (f_i + f_j - c)` (c = shared quotations or documents, f = quotations or documents per code); saves `.dta` files.
2. **Stata:** rankings, `mdsmat` (classical MDS, 2 dimensions), `ca` + `cabiplot`, graph and CSV export.

## Notes and limitations

- Maps show proximity of codes, not causal relations; axes are exploratory.
- Results depend on coding decisions; overlapping parent/child codes inflate co-occurrence.
- The word list only covers the documents in the export. ATLAS.ti exports word clouds only as images, so frequencies are rebuilt from the list.
- Code names must be unique. Close the Excel files before running.
- The do-file must be saved as UTF-8.
- Stata/BE limits matrices to 800 rows: codebooks with more codes need SE/MP.
- The Python block was tested outside Stata on real ATLAS.ti exports. The Stata part targets Stata 18; report any error with your Stata edition and `python query` output.

## Data protection

Exports contain code names and words from interviews. Do not publish them if they could identify participants; add `atlas_exports/`, `stata_data/` and `figures/` to `.gitignore`.

## License

MIT. Cite as: [Author]. (2026). *atlas2stata: from ATLAS.ti exports to statistics and maps in Stata*. GitHub: <repository URL>.
