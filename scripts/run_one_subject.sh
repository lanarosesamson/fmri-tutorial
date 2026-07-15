#!/bin/bash

SUBNUM=$1

BIDS_SUB="sub-108TUSW011${SUBNUM}"
OUT_SUB="sub_${SUBNUM#0}"

BOLD_FILE=$(find ~/fMRI_tutorial_project/righthanded/bids/derivatives/fmriprep_output/$BIDS_SUB \
-name "*space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz")

echo "Numéro sujet : $SUBNUM"
echo "Sujet BIDS : $BIDS_SUB"
echo "Dossier output : $OUT_SUB"

echo "BOLD trouvé :"
echo "$BOLD_FILE"

CONFOUNDS_TSV=$(find ~/fMRI_tutorial_project/righthanded/bids/derivatives/fmriprep_output/$BIDS_SUB \
-name "*desc-confounds_timeseries.tsv")

echo
echo "Confounds TSV trouvé :"
echo "$CONFOUNDS_TSV"

echo
echo "=== Vérifications ==="

if [ -f "$BOLD_FILE" ]; then
    echo "BOLD OK"
else
    echo "BOLD MANQUANT"
fi

if [ -f "$CONFOUNDS_TSV" ]; then
    echo "CONFOUNDS OK"
else
    echo "CONFOUNDS MANQUANT"
fi

OUT_DIR=~/fMRI_tutorial_project/righthanded/bids/derivatives/fsl_output/$OUT_SUB
CONFOUNDS_TXT=$OUT_DIR/confounds.txt

mkdir -p "$OUT_DIR"

echo
echo "=== Création confounds.txt ==="

if [ -f "$CONFOUNDS_TXT" ]; then
    echo "confounds.txt existe déjà : $CONFOUNDS_TXT"
    echo "Je ne l'écrase pas."
else
    python3 - "$CONFOUNDS_TSV" "$CONFOUNDS_TXT" <<'PY'
import csv
import sys
from pathlib import Path

infile = Path(sys.argv[1])
outfile = Path(sys.argv[2])

base_cols = [
    "trans_x", "trans_y", "trans_z",
    "rot_x", "rot_y", "rot_z",
    "trans_x_derivative1", "trans_y_derivative1", "trans_z_derivative1",
    "rot_x_derivative1", "rot_y_derivative1", "rot_z_derivative1",
]

acompcor_cols = [f"a_comp_cor_{i:02d}" for i in range(13)]

with infile.open() as f:
    reader = csv.DictReader(f, delimiter="\t")
    all_cols = reader.fieldnames
    motion_outlier_cols = [c for c in all_cols if c.startswith("motion_outlier")]
    selected_cols = base_cols + acompcor_cols + motion_outlier_cols

    with outfile.open("w") as out:
        for row in reader:
            values = []
            for col in selected_cols:
                val = row[col]
                if val in ("n/a", "nan", "NaN", ""):
                    val = "0"
                values.append(val)
            out.write("\t".join(values) + "\n")

print(f"Fichier créé : {outfile}")
print(f"Colonnes utilisées : {len(selected_cols)}")
print(f"Motion outliers : {len(motion_outlier_cols)}")
PY
fi

EVENTS_FILE=$(find ~/fMRI_tutorial_project/righthanded/bids/$BIDS_SUB/ses-1/func -name "*events.tsv")

RIGHT_EV=$OUT_DIR/regressors_right_hand.txt
LEFT_EV=$OUT_DIR/regressors_left_hand.txt
BOTH_EV=$OUT_DIR/regressors_both_hands.txt

echo
echo "=== Création des regressors ==="
echo "Events trouvé : $EVENTS_FILE"

mkdir -p "$OUT_DIR"

awk '{gsub(/\r/,""); if ($3=="Right") print $1 "\t" $2 "\t1"}' "$EVENTS_FILE" > "$RIGHT_EV"
awk '{gsub(/\r/,""); if ($3=="Left") print $1 "\t" $2 "\t1"}' "$EVENTS_FILE" > "$LEFT_EV"
awk '{gsub(/\r/,""); if ($3=="Both") print $1 "\t" $2 "\t1"}' "$EVENTS_FILE" > "$BOTH_EV"

echo "Right EV créé : $RIGHT_EV"
echo "Left EV créé : $LEFT_EV"
echo "Both EV créé : $BOTH_EV"

TEMPLATE_FSF=~/fMRI_tutorial_project/righthanded/bids/derivatives/fsl_output/sub_51/sub051_right_left_confounds.fsf
FSF_FILE=$OUT_DIR/sub${SUBNUM}_right_left_confounds.fsf
FEAT_DIR=$OUT_DIR/sub${SUBNUM}_right_left_confounds.feat

NPTS=$(fslval "$BOLD_FILE" dim4)

echo
echo "=== Création du fichier FSF ==="

if [ -f "$FSF_FILE" ]; then
    echo "FSF existe déjà : $FSF_FILE"
    echo "Je ne l'écrase pas."
else
    cp "$TEMPLATE_FSF" "$FSF_FILE"

    sed -i "s|^set fmri(outputdir).*|set fmri(outputdir) \"$FEAT_DIR\"|" "$FSF_FILE"
    sed -i "s|^set feat_files(1).*|set feat_files(1) \"${BOLD_FILE%.nii.gz}\"|" "$FSF_FILE"
    sed -i "s|^set confoundev_files(1).*|set confoundev_files(1) \"$CONFOUNDS_TXT\"|" "$FSF_FILE"
    sed -i "s|^set fmri(custom1).*|set fmri(custom1) \"$RIGHT_EV\"|" "$FSF_FILE"
    sed -i "s|^set fmri(custom2).*|set fmri(custom2) \"$LEFT_EV\"|" "$FSF_FILE"
    sed -i "s|^set fmri(custom3).*|set fmri(custom3) \"$BOTH_EV\"|" "$FSF_FILE"
    sed -i "s|^set fmri(regstandard).*|set fmri(regstandard) \"$FSLDIR/data/standard/MNI152_T1_2mm_brain\"|" "$FSF_FILE"


    sed -i "s|set fmri(npts) [0-9]*|set fmri(npts) $NPTS|g" "$FSF_FILE"

    echo "FSF créé : $FSF_FILE"
fi

echo
echo "=== Lancement FEAT ==="

if [ "$2" = "run" ]; then
    echo "Je lance FEAT avec : $FSF_FILE"
    feat "$FSF_FILE"
else
    echo "Mode préparation seulement."
    echo "Pour lancer FEAT : ./run_one_subject.sh $SUBNUM run"
fi
