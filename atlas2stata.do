*! atlas2stata.do  v1.0
*! From ATLAS.ti exports to statistics and two-axis maps in Stata 18  (single file, no other scripts)
*!
*! WHAT IT DOES
*!   A. Reads three ATLAS.ti Excel exports (cleaning, alignment, Jaccard distances) in an embedded
*!      Python block and saves Stata datasets (.dta).
*!   B. Ranks codes, words and code pairs.
*!   C. Draws two-axis maps of the codes (multidimensional scaling) and a correspondence-analysis biplot.
*!
*! INPUT FILES (put them in the folder IN, exact names)
*!   code_document.xlsx      ATLAS.ti "Code-Document Table"   (counts = quotations)
*!   code_cooccurrence.xlsx  ATLAS.ti "Code Co-occurrence Table" (Show Count)
*!   word_list.xlsx          ATLAS.ti "Word List"
*!
*! REQUIREMENTS
*!   Stata 18 (Python integration), Python 3.9+ with pandas, numpy, openpyxl.
*!   One-time setup (see README): python search / python set exec "C:/path/python.exe", permanently
*!
*! USE
*!   1. Edit the SETTINGS block.   2. do atlas2stata.do
*!   Save this file as UTF-8 (accents and symbols are handled in the Python block).

version 18
clear all
set more off

*============================ SETTINGS (edit here) ===========================================
global PROJECT "C:/atlas2stata"   // folder with this do-file; use / also on Windows
global IN      "atlas_exports"    // folder with the 3 Excel exports (relative to PROJECT, no spaces)
global OUT     "stata_data"       // results folder (.dta, .csv); created automatically
global FIG     "figures"          // figures folder (.png); created automatically
global LANG    "es"               // stop words for the word list: es | en | none
global MINLEN  4                  // minimum word length kept in the word list
global TOPN    15                 // number of codes shown in the ranking
global WORDN   30                 // number of words shown in the word ranking
global LABPCT  80                 // map labels only for codes above this percentile of n_quotes
*==============================================================================================

cd "$PROJECT"
capture mkdir "$OUT"
capture mkdir "$FIG"

*---------------------------------------------------------------------------------------------
* A. PYTHON STEP: Excel exports -> .dta
*    Outputs in $OUT: codes.dta (code_id code n_quotes n_docs), code_doc_long.dta (code doc n),
*    pairs.dta (code_i code_j n_quote n_doc), dist_quote.dta / dist_doc.dta (Jaccard distances,
*    columns d1..dK, row order = code_id), words.dta (word freq).
*    Jaccard distance: d_ij = 1 - c_ij / (f_i + f_j - c_ij), c = shared quotations (or documents),
*    f = quotations (or documents) of each code. Empty codes/documents and totals are dropped.
*---------------------------------------------------------------------------------------------
capture python query
if _rc {
    di as error "Stata cannot find Python. Run: python search   and   python set exec ""C:/path/python.exe"", permanently"
    exit 198
}
capture python which pandas
if _rc {
    di as error "Python module pandas not found in the Python used by Stata (pip install pandas numpy openpyxl)"
    exit 198
}

python:
import re
from pathlib import Path
import numpy as np
import pandas as pd
from sfi import Macro

IN   = Path(Macro.getGlobal("IN"))
OUT  = Path(Macro.getGlobal("OUT"))
LANG = Macro.getGlobal("LANG")
MINLEN = int(Macro.getGlobal("MINLEN"))
OUT.mkdir(parents=True, exist_ok=True)

STOP_ES = set("de la que el en y a los se del las un por con no una su para es al lo como m\u00e1s pero sus le ya o este s\u00ed porque esta entre cuando muy sin sobre tambi\u00e9n me hasta hay donde quien desde todo nos durante todos uno les ni contra otros ese eso ante ellos e esto m\u00ed antes algunos qu\u00e9 unos yo otro otras otra \u00e9l tanto esa estos mucho quienes nada muchos cual poco ella estar estas algunas algo nosotros mi mis t\u00fa te ti tu tus ellas son era eran fue ser sea est\u00e1 est\u00e1n estaba estaban he ha han hab\u00eda hacer hace hacen tiene tienen tengo ten\u00eda va van voy iba bien as\u00ed aqu\u00ed ah\u00ed all\u00ed entonces pues vamos digo dice dicen mismo misma cosa cosas ahora luego solo s\u00f3lo siempre bueno vez veces tipo forma parte hacia puede pueden puedo creo claro gente".split())
STOP_EN = set("the of and a to in is that it was for on are as with his they at be this from have or by one had not but what all were when we there can an your which their if do will each about how up out them then she many some so these would other into has more her two like him see time could no make than first been its who now people my made over did down only way use may long very after just where most know get through back much before go good new our me man too any day same right look think also around another come work three must because does part even place well such here take why help put different away again off went old number great tell men say small every found still between should home big give set own under last never us left end while might next both few those always often together world going want".split())
STOP = {"es": STOP_ES, "en": STOP_EN, "none": set()}[LANG]

def clean_label(x):
    t = str(x)
    m = re.search(r"Gr\s*=\s*(\d+)", t)
    gr = float(m.group(1)) if m else np.nan
    name = re.sub(r"Gr\s*=\s*\d+", "", t).replace("\n", " ").strip()
    name = re.sub("^[\u25cf\u25cb\u25e6\u2022]\\s*", "", name).strip()
    return name, gr

def read_matrix(fname):
    f = IN / fname
    if not f.exists():
        raise FileNotFoundError("Missing input file: " + str(f))
    m = pd.read_excel(f, index_col=0)
    rows = [clean_label(i) for i in m.index]
    cols = [clean_label(c) for c in m.columns]
    m.index = [r[0] for r in rows]
    m.columns = [c[0] for c in cols]
    gr = pd.Series([r[1] for r in rows], index=m.index)
    tot = re.compile(r"^(?:total|totales|totals|sum)", re.I)
    kr = [not tot.match(str(i)) for i in m.index]
    kc = [not tot.match(str(c)) for c in m.columns]
    m = m.loc[kr, kc].apply(pd.to_numeric, errors="coerce").fillna(0)
    return m, gr[kr]

def jaccard(co, f):
    a = co.values.astype(float)
    with np.errstate(divide="ignore", invalid="ignore"):
        j = np.nan_to_num(a / (f[:, None] + f[None, :] - a))
    d = 1 - j
    np.fill_diagonal(d, 0)
    return pd.DataFrame(d, columns=["d" + str(i) for i in range(1, len(f) + 1)])

cd, gr = read_matrix("code_document.xlsx")
cd = cd.loc[cd.sum(axis=1) > 0, cd.sum(axis=0) > 0]
codes = cd.index.tolist()
if len(set(codes)) != len(codes):
    raise ValueError("Duplicate code names: rename them in ATLAS.ti and re-export")
cq_raw, _ = read_matrix("code_cooccurrence.xlsx")
cq = cq_raw.reindex(index=codes, columns=codes).fillna(0)
if not np.allclose(cq.values, cq.values.T):
    cq = (cq + cq.T) / 2
np.fill_diagonal(cq.values, 0)

cmap = pd.DataFrame({"code_id": range(1, len(codes) + 1), "code": codes})
dmap = pd.DataFrame({"doc_id": range(1, cd.shape[1] + 1), "doc": cd.columns})
B = (cd.values > 0).astype(int)
cdd = pd.DataFrame(B @ B.T, index=codes, columns=codes)
np.fill_diagonal(cdd.values, 0)

cdf = cmap.copy()
cdf["n_quotes"] = gr.reindex(codes).fillna(cd.sum(axis=1)).values.astype(int)
cdf["n_docs"] = B.sum(axis=1)

long = cd.stack().rename("n").reset_index()
long.columns = ["code", "doc", "n"]
long = long.merge(cmap).merge(dmap)
long["n"] = long["n"].astype(int)

def tolong(m, name):
    s = m.stack().rename(name).reset_index()
    s.columns = ["code_i", "code_j", name]
    return s

pairs = tolong(cq, "n_quote").merge(tolong(cdd, "n_doc"), on=["code_i", "code_j"])
pairs = pairs.merge(cmap.rename(columns={"code_id": "id_i", "code": "code_i"}))
pairs = pairs.merge(cmap.rename(columns={"code_id": "id_j", "code": "code_j"}))
pairs[["n_quote", "n_doc"]] = pairs[["n_quote", "n_doc"]].round().astype(int)

w = pd.read_excel(IN / "word_list.xlsx")
w = w[~w.iloc[:, 0].astype(str).str.match(r"^(?i:total|totales|totals)")]
tc = [c for c in w.columns if str(c).lower().startswith("total")]
if tc:
    freq = pd.to_numeric(w[tc[0]], errors="coerce")
else:
    use = [c for c in w.columns[1:] if not str(c).startswith("%") and str(c).lower() not in ("largo", "length")]
    freq = w[use].apply(pd.to_numeric, errors="coerce").sum(axis=1)
words = pd.DataFrame({"word": w.iloc[:, 0].astype(str).str.lower(), "freq": freq}).dropna()
words = words[(words.word.str.len() >= MINLEN) & (~words.word.isin(STOP)) & (words.freq > 0)]
words = words.astype({"freq": int}).sort_values("freq", ascending=False)

kw = dict(write_index=False, version=118)
cdf.to_stata(OUT / "codes.dta", **kw)
long.to_stata(OUT / "code_doc_long.dta", **kw)
pairs.to_stata(OUT / "pairs.dta", **kw)
jaccard(cq, cdf["n_quotes"].values.astype(float)).to_stata(OUT / "dist_quote.dta", **kw)
jaccard(cdd, cdf["n_docs"].values.astype(float)).to_stata(OUT / "dist_doc.dta", **kw)
words.to_stata(OUT / "words.dta", **kw)
print("Python step OK: %d codes, %d documents, %d words" % (len(codes), cd.shape[1], len(words)))
end

*---------------------------------------------------------------------------------------------
* B1. CODE STATISTICS: ranking of codes by number of quotations
*---------------------------------------------------------------------------------------------
use "$OUT/codes.dta", clear
quietly summarize n_quotes
di as text _n "Codes: " _N "    Quotations: " r(sum)
gsort -n_quotes
list code n_quotes n_docs in 1/$TOPN, noobs
graph hbar n_quotes in 1/$TOPN, over(code, sort(1) descending label(labsize(small))) ///
    ytitle("Number of quotations") title("Most frequent codes")
graph export "$FIG/01_code_frequencies.png", replace width(2000)
export delimited using "$OUT/code_statistics.csv", replace

*---------------------------------------------------------------------------------------------
* B2. WORD FREQUENCIES (substitute for the word cloud, which ATLAS.ti exports only as an image)
*---------------------------------------------------------------------------------------------
use "$OUT/words.dta", clear
gsort -freq
list word freq in 1/$WORDN, noobs
graph hbar freq in 1/$WORDN, over(word, sort(1) descending label(labsize(vsmall))) ///
    ytitle("Frequency") title("Most frequent words")
graph export "$FIG/02_word_frequencies.png", replace width(2000)

*---------------------------------------------------------------------------------------------
* B3. STRONGEST CODE PAIRS (quotation-level and document-level co-occurrence)
*---------------------------------------------------------------------------------------------
use "$OUT/pairs.dta", clear
keep if id_i < id_j                       // each unordered pair once
gsort -n_quote
list code_i code_j n_quote n_doc in 1/20, noobs
export delimited using "$OUT/top_pairs.csv", replace

*---------------------------------------------------------------------------------------------
* C1. TWO-AXIS MAPS OF THE CODES (MDS on Jaccard distances)
*     Close codes co-occur often. Bubble size = number of quotations. Axes are exploratory.
*     Run for quotation level ("quote") and document level ("doc").
*---------------------------------------------------------------------------------------------
foreach t in quote doc {
    use "$OUT/dist_`t'.dta", clear
    mkmat d*, matrix(D)                        // K x K distance matrix
    mdsmat D, dimension(2) method(classical) noplot
    matrix Y = e(Y)                            // K x 2 coordinates (same order as code_id)
    use "$OUT/codes.dta", clear
    sort code_id
    svmat Y, names(dim)                        // creates dim1 dim2
    quietly _pctile n_quotes, p($LABPCT)
    gen lab = code if n_quotes >= r(r1)        // label only the most frequent codes
    twoway scatter dim2 dim1 [aw=n_quotes], mlabel(lab) mlabpos(12) mlabsize(small) ///
        msymbol(Oh) xline(0, lcolor(gs12)) yline(0, lcolor(gs12)) legend(off)     ///
        xtitle("Dimension 1") ytitle("Dimension 2")                                ///
        title("Code map: co-occurrence in `t's (MDS, Jaccard)")
    graph export "$FIG/03_mds_`t'.png", replace width(2000)
    keep code_id code dim1 dim2 n_quotes n_docs
    export delimited using "$OUT/mds_coords_`t'.csv", replace
}

*---------------------------------------------------------------------------------------------
* C2. CORRESPONDENCE ANALYSIS: which codes are over-represented in which documents
*---------------------------------------------------------------------------------------------
use "$OUT/code_doc_long.dta", clear
encode code, gen(code_e)
encode doc,  gen(doc_e)
ca code_e doc_e [fweight=n], dimensions(2)
cabiplot
graph export "$FIG/04_ca_biplot.png", replace width(2000)

di as result _n "Done. Tables: $OUT/    Figures: $FIG/"
