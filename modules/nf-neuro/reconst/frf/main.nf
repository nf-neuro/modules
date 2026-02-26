

process RECONST_FRF {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec), path(mask), path(wm_mask), path(gm_mask), path(csf_mask)

    output:
        tuple val(meta), path("*__frf.txt")             , emit: frf, optional: true
        tuple val(meta), path("*__wm_frf.txt")          , emit: wm_frf, optional: true
        tuple val(meta), path("*__gm_frf.txt")          , emit: gm_frf, optional: true
        tuple val(meta), path("*__csf_frf.txt")         , emit: csf_frf, optional: true
        path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def fa = task.ext.fa ? "--fa " + task.ext.fa : ""
    def fa_min = task.ext.fa_min ? "--min_fa " + task.ext.fa_min : ""
    def nvox_min = task.ext.nvox_min ? "--min_nvox " + task.ext.nvox_min : ""
    def roi_radius = task.ext.roi_radius ? "--roi_radii " + task.ext.roi_radius : ""
    def dwi_shell_tolerance = task.ext.dwi_shell_tolerance ? "--tolerance " + task.ext.dwi_shell_tolerance : ""
    def max_dti_shell_value = task.ext.max_dti_shell_value ?: 1500
    def min_fodf_shell_value = task.ext.min_fodf_shell_value ?: 100
    def b0_thr_extract_b0 = task.ext.b0_thr_extract_b0 ?: 10
    def dti_shells = task.ext.dti_shells ?: "\$(cut -d ' ' --output-delimiter=\$'\\n' -f 1- $bval | awk -F' ' '{v=int(\$1)}{if(v<=$max_dti_shell_value|| v<=$b0_thr_extract_b0)print v}' | sort | uniq)"
    def fodf_shells = task.ext.fodf_shells ? "0 " + task.ext.fodf_shells : "\$(cut -d ' ' --output-delimiter=\$'\\n' -f 1- $bval | awk -F' ' '{v=int(\$1)}{if(v>=$min_fodf_shell_value|| v<=$b0_thr_extract_b0)print v}' | sort | uniq)"
    def set_method = task.ext.method ? task.ext.method : "ssst"
    def precision = task.ext.precision ? "--precision " + task.ext.precision : ""

    def fa_thr_wm = task.ext.fa_thr_wm ? "--fa_thr_wm " + task.ext.fa_thr_wm : ""
    def fa_thr_gm = task.ext.fa_thr_gm ? "--fa_thr_gm " + task.ext.fa_thr_gm : ""
    def fa_thr_csf = task.ext.fa_thr_csf ? "--fa_thr_csf " + task.ext.fa_thr_csf : ""
    def md_thr_wm = task.ext.md_thr_wm ? "--md_thr_wm " + task.ext.md_thr_wm : ""
    def md_thr_gm = task.ext.md_thr_gm ? "--md_thr_gm " + task.ext.md_thr_gm : ""
    def md_thr_csf = task.ext.md_thr_csf ? "--md_thr_csf " + task.ext.md_thr_csf : ""

    def fix_frf = task.ext.manual_frf ? task.ext.manual_frf : ""
    def fix_wm_frf = task.ext.manual_wm_frf ? task.ext.manual_wm_frf : ""
    def fix_gm_frf = task.ext.manual_gm_frf ? task.ext.manual_gm_frf : ""
    def fix_csf_frf = task.ext.manual_csf_frf ? task.ext.manual_csf_frf : ""
    def set_mask = mask ? "--mask $mask" : ""
    def set_wm_mask = wm_mask ? "--mask_wm $wm_mask" : ""
    def set_gm_mask = gm_mask ? "--mask_gm $gm_mask" : ""
    def set_csf_mask = csf_mask ? "--mask_csf $csf_mask" : ""

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    if [ "$set_method" = "ssst" ]
    then

        scil_dwi_extract_shell $dwi $bval $bvec $dti_shells \
                dwi_dti_shells.nii.gz bval_dti_shells bvec_dti_shells \
                $dwi_shell_tolerance -f -v

        scil_frf_ssst dwi_dti_shells.nii.gz bval_dti_shells bvec_dti_shells ${prefix}__frf.txt \
            $set_mask $fa $fa_min $nvox_min $roi_radius --b0_threshold $b0_thr_extract_b0 $precision -v

        if ( "$task.ext.set_frf" = true ); then
            scil_frf_set_diffusivities ${prefix}__frf.txt "${fix_frf}" \
                ${prefix}__frf.txt $precision -f -v
        fi

    elif [ "$set_method" = "msmt" ]
    then

        scil_dwi_extract_shell $dwi $bval $bvec $fodf_shells \
            dwi_fodf_shells.nii.gz bval_fodf_shells bvec_fodf_shells \
            $dwi_shell_tolerance -f -v

        scil_frf_msmt dwi_fodf_shells.nii.gz bval_fodf_shells bvec_fodf_shells \
            ${prefix}__wm_frf.txt ${prefix}__gm_frf.txt ${prefix}__csf_frf.txt \
            $set_mask $set_wm_mask $set_gm_mask $set_csf_mask $fa_thr_wm $fa_thr_gm \
            $fa_thr_csf $md_thr_wm $md_thr_gm $md_thr_csf $nvox_min $roi_radius \
            $dwi_shell_tolerance --dti_bval_limit $max_dti_shell_value $precision -v

        if ( "$task.ext.set_frf" = true ); then
            scil_frf_set_diffusivities ${prefix}__wm_frf.txt "${fix_wm_frf}" \
                ${prefix}__wm_frf.txt $precision -f -v
            scil_frf_set_diffusivities ${prefix}__gm_frf.txt "${fix_gm_frf}" \
                ${prefix}__gm_frf.txt $precision -f -v
            scil_frf_set_diffusivities ${prefix}__csf_frf.txt "${fix_csf_frf}" \
                ${prefix}__csf_frf.txt $precision -f -v
        fi

    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_dwi_extract_shell -h
    scil_frf_ssst -h
    scil_frf_set_diffusivities -h
    scil_frf_msmt -h

    touch ${prefix}__frf.txt
    touch ${prefix}__wm_frf.txt
    touch ${prefix}__gm_frf.txt
    touch ${prefix}__csf_frf.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
