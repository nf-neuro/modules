process STATS_ROIVOLUMES {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ 'community.wave.seqera.io/library/nibabel_numpy:4148b92a8cbc6976' }"

    input:
    tuple val(meta), path(rois), path(rois_lut)  /* optional, input = [] */

    output:
    tuple val(meta), path("*_volumes.csv"), emit: volumes
    path "versions.yml",                    emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix            = task.ext.prefix ?: "${meta.id}"
    def suffix            = task.ext.first_suffix ? "${task.ext.first_suffix}_volumes" : "volumes"
    def use_label         = task.ext.use_label ? true : false
    def use_label_py      = use_label ? "True" : "False"
    def substrs_to_remove = task.ext.key_substrs_to_remove ?: []
    def substrs_json      = groovy.json.JsonOutput.toJson(substrs_to_remove)
    // For labels mode: rois is a list; join paths as space-separated string for Python to split
    def rois_str          = rois instanceof List ? rois.join(' ') : "${rois}"
    def subject_id        = meta.id ?: ""
    def session_id        = meta.session ?: ""
    def run_id            = meta.run ?: ""
    """
    python3 << 'PYEOF'
import nibabel as nib
import numpy as np
import json
import os

prefix     = "${prefix}"
suffix     = "${suffix}"
use_label  = ${use_label_py}
substrs    = ${substrs_json}
subject_id = "${subject_id}"
session_id = "${session_id}"
run_id     = "${run_id}"

output_file = f"{prefix}_{suffix}.csv"

if use_label:
    # Labelmap mode: single atlas/labelmap image — load once, count all labels in one pass.
    # Equivalent per label to:
    #   mrcalc atlas <label_id> -eq mask + mrstats mask -mask mask -output count
    img  = nib.load("${rois}")
    data = img.get_fdata()
    # Round to nearest integer to guard against MultiLabel warp float precision
    data_int = np.round(data).astype(np.int32)
    vox_vol  = float(np.prod(img.header.get_zooms()[:3]))

    with open("${rois_lut}") as f:
        lut = json.load(f)

    with open(output_file, 'w') as out:
        out.write("sid,session,run,roi,volume_voxels,volume_mm3\\n")
        for label_id, label_name in sorted(lut.items(), key=lambda x: int(x[0])):
            count   = int(np.sum(data_int == int(label_id)))
            vol_mm3 = count * vox_vol
            out.write(f"{subject_id},{session_id},{run_id},{label_name},{count},{vol_mm3:.4f}\\n")
else:
    # Labels mode: list of binary/weighted ROI masks, one file per label.
    # Equivalent per mask to:
    #   mrstats mask -mask mask -output count
    # np.sum(data > 0) counts finite non-zero voxels (NaN > 0 == False, excluded).
    mask_files = sorted("${rois_str}".split())

    with open(output_file, 'w') as out:
        out.write("sid,session,run,roi,volume_voxels,volume_mm3\\n")
        for mask_file in mask_files:
            roi_name = os.path.basename(mask_file)
            for ext in ('.nii.gz', '.nii'):
                if roi_name.endswith(ext):
                    roi_name = roi_name[:-len(ext)]
                    break
            for s in substrs:
                roi_name = roi_name.removeprefix(s).removesuffix(s)

            img     = nib.load(mask_file)
            data    = img.get_fdata()
            vox_vol = float(np.prod(img.header.get_zooms()[:3]))
            count   = int(np.sum(data > 0))
            vol_mm3 = count * vox_vol
            out.write(f"{subject_id},{session_id},{run_id},{roi_name},{count},{vol_mm3:.4f}\\n")

with open("versions.yml", "w") as v:
    v.write('"${task.process}":\\n')
    v.write(f"    nibabel: {nib.__version__}\\n")
    v.write(f"    numpy: {np.__version__}\\n")
PYEOF
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.first_suffix ? "${task.ext.first_suffix}_volumes" : "volumes"
    """
    touch ${prefix}_${suffix}.csv

    python3 -c "
with open('versions.yml', 'w') as v:
    import nibabel, numpy
    v.write('\"${task.process}\":\\n')
    v.write(f'    nibabel: {nibabel.__version__}\\n')
    v.write(f'    numpy: {numpy.__version__}\\n')
"
    """
}
